local util = OSSecurity.Util
OSSecurity.InstallationService = {}

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

-- Posiciones a 0,1 mm y angulos a 0,01 grados: valores que el JSON del runtime relee exactamente.
local function canonical(vector, decimals)
    local round = OSSecurity.Util.round
    return { x = round(vector.x, decimals or 4), y = round(vector.y, decimals or 4), z = round(vector.z, decimals or 4) }
end

function OSSecurity.InstallationService.new(options)
    local config, contexts, watching = OSSecurity.GameplayConfig, {}, false
    local service = {}
    local holdingsCheck
    local function world(source)
        local point, bucket = options.world(source)
        if not OSSecurity.InventoryState.vector(point, 1000000) or not util.integer(bucket, 0, 2147483647) then
            return nil, 'Posicion de servidor no disponible; comprobar OneSync.'
        end
        return point, bucket
    end
    local function watch()
        if watching or not options.schedule or not next(contexts) then return end
        watching = true
        options.schedule(function()
            watching = false
            for source, context in pairs(contexts) do
                local point, bucket = world(source)
                if options.now() > context.expires or not options.alive(source) or not point
                    or bucket ~= context.bucket or distance(point, context.origin) > config.MaxPlacementMove then
                    contexts[source] = nil; options.invalidate(source)
                end
            end
            watch()
        end)
    end
    local function devices()
        local result = {}
        local page, err = options.registry.list(0, 0, 100)
        if not page then return nil, err end
        for offset = 0, math.max(0, page.total - 1), 100 do
            local current = offset == 0 and page or options.registry.list(0, offset, 100)
            if not current then return nil, 'Registro no disponible.' end
            for _, summary in ipairs(current.items) do
                local device = options.registry.get(0, summary.id)
                if not device then return nil, 'Registro no disponible.' end
                result[#result + 1] = device
            end
        end
        return result
    end
    -- Producto instalable a partir del kit usado (camara por defecto) o del modelo de una instalacion.
    local function product(kit) return config.Products[kit or 'os_cctv_kit'] end
    local function productOfModel(model)
        for _, definition in pairs(config.Products) do if definition.model == model then return definition end end
    end
    service.productOfModel = productOfModel
    -- Herramientas (no se consumen) y materiales del actor, en el registro local o en el proveedor externo.
    function holdingsCheck(actor, definition)
        definition = definition or product()
        for item, amount in pairs(definition.materials) do
            if not options.holdings.has(actor, item, amount) then
                return OSSecurity.ItemCatalog[item].category == 'kit' and ('No posee: ' .. OSSecurity.ItemCatalog[item].name .. '.') or 'Faltan materiales de instalacion.'
            end
        end
        for _, item in ipairs(config.Tools) do
            if not options.holdings.has(actor, item, 1) then return 'Faltan herramientas de instalacion.' end
        end
        return nil
    end
    -- Anula una reserva devolviendo antes los materiales externos; si la devolucion no se puede
    -- confirmar, la reserva queda pendiente para reintentarse en la siguiente recuperacion.
    local function cancel(installation, reason)
        local refunded, refundError = options.holdings.refund(installation)
        if not refunded then return nil, refundError end
        return options.inventory.apply({ kind = 'cancel', installationId = installation.id, reason = reason })
    end
    function service.find(installationId)
        local list, err = devices()
        if not list then return nil, err end
        local found
        for _, device in ipairs(list) do
            if device.metadata.installationId == installationId then
                if found then return nil, 'Vinculo de instalacion duplicado; requiere revision.' end
                found = device
            end
        end
        return found
    end
    function service.begin(source, session, kit)
        local definition = product(kit)
        if not definition then return nil, 'Producto no instalable.' end
        if session.actor.kind ~= 'operations' or not config.Profiles[session.actor.role].install then return nil, 'Perfil sin permiso de instalacion.' end
        local point, bucket = world(source)
        if not point then return nil, bucket end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        local missing = holdingsCheck(session.actor, definition)
        if missing then return nil, missing end
        local mounts = {}
        for id, anchor in pairs(snapshot.anchors) do
            if anchor.installer == session.actor.principal and anchor.bucket == bucket and distance(point, anchor.position) <= config.PlacementDistance then
                local occupied = false
                for _, installation in pairs(snapshot.installations) do
                    if installation.anchorId == id and installation.status ~= 'cancelled' and installation.status ~= 'removed' then occupied = true end
                end
                if not occupied then mounts[#mounts + 1] = { id = id, position = util.copy(anchor.position), normal = util.copy(anchor.normal), radius = anchor.radius } end
            end
        end
        table.sort(mounts, function(a, b) return a.id < b.id end)
        if #mounts == 0 then return nil, 'No hay un montaje libre asignado y cercano.' end
        contexts[source] = { token = session.token, origin = point, bucket = bucket, expires = options.now() + config.PlacementSeconds, kit = kit or 'os_cctv_kit' }
        watch()
        return { model = definition.model, mounts = mounts, maxDistance = config.PlacementDistance, seconds = config.PlacementSeconds }
    end
    local function finalize(installation, device)
        local definition = productOfModel(installation.model)
        if not definition or device.type ~= definition.deviceType or device.model ~= installation.model or device.owner ~= installation.owner
            or not util.equal(device.position, installation.position) or not util.equal(device.rotation, installation.rotation) then
            return nil, 'El dispositivo no coincide con la reserva; requiere revision.'
        end
        if device.state == 'retired' then return cancel(installation, 'retired') end
        local nextState = { registered = 'installing', installing = 'installed', installed = 'active' }
        while nextState[device.state] do
            local updated, err = options.registry.setState(0, device.id, nextState[device.state])
            if not updated then return nil, err end
            device = updated
        end
        if device.state ~= 'active' then return nil, 'Instalacion pendiente: estado administrativo incompatible.' end
        return options.inventory.apply({ kind = 'finish', installationId = installation.id, deviceId = device.id })
    end
    function service.confirm(source, session, proposal)
        local context = contexts[source]
        contexts[source] = nil -- Confirmacion de un solo uso, tambien si se rechaza.
        if not context or context.token ~= session.token or options.now() > context.expires
            or session.actor.kind ~= 'operations' or not config.Profiles[session.actor.role].install
            or not util.object(proposal, { anchorId = true, position = true, rotation = true, pivot = true }) then return nil, 'Colocacion no valida o caducada.' end
        local point, bucket = world(source)
        if not point then return nil, bucket end
        if bucket ~= context.bucket or distance(point, context.origin) > config.MaxPlacementMove then return nil, 'Se ha alejado de la colocacion.' end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        local anchor = type(proposal.anchorId) == 'string' and snapshot.anchors[proposal.anchorId]
        -- Pivote: centro visual del modelo, sobre el que gira en el editor. Es el que se valida contra el
        -- cuadrado y el plano; el origen del modelo (lo que se guarda) debe quedar muy cerca de el.
        local pivot = proposal.position
        if proposal.pivot ~= nil then
            if not OSSecurity.InventoryState.vector(proposal.pivot, 1000000) or not OSSecurity.InventoryState.vector(proposal.position, 1000000)
                or distance(proposal.pivot, proposal.position) > config.MaxPivotOffset then return nil, 'Montaje, proximidad o coordenadas no autorizados.' end
            pivot = proposal.pivot
        end
        if not anchor or anchor.installer ~= session.actor.principal or anchor.bucket ~= bucket
            or not OSSecurity.InventoryState.vector(proposal.position, 1000000)
            or not OSSecurity.InventoryState.vector(proposal.rotation, 360)
            or math.abs(proposal.rotation.x) > 90 or math.abs(proposal.rotation.y) > 180
            or distance(point, pivot) > config.PlacementDistance
            or not OSSecurity.Geometry.inside(anchor, pivot) then return nil, 'Montaje, proximidad o coordenadas no autorizados.' end
        local delta = { x = pivot.x - anchor.position.x, y = pivot.y - anchor.position.y, z = pivot.z - anchor.position.z }
        local planeDistance = delta.x * anchor.normal.x + delta.y * anchor.normal.y + delta.z * anchor.normal.z
        -- Profundidad elegida en el editor (Q/Z): el origen del modelo puede quedar algo dentro o separado
        -- de la superficie, dentro de MinDepth..MaxDepth. Se guarda tal cual, sin proyectar.
        if planeDistance < config.MinDepth or planeDistance > config.MaxDepth then
            return nil, 'La posicion no pertenece al plano de montaje autorizado.'
        end
        local position = canonical(proposal.position)
        local holder
        if options.holdings.external() then
            -- El personaje debe seguir siendo el de la sesion: nunca cobrar a otro personaje de la cuenta.
            holder = options.holdings.holder(source)
            if not holder or holder ~= session.actor.holder then return nil, 'El personaje activo cambio; vuelve a abrir la tablet.' end
            local missing = holdingsCheck(session.actor, product(context.kit))
            if missing then return nil, missing end
        end
        local definition = product(context.kit)
        local installation = {
            id = ('g6i_%010d'):format(snapshot.nextInstallation), anchorId = anchor.id, owner = anchor.owner,
            installer = session.actor.principal, position = position, rotation = canonical(proposal.rotation, 2), bucket = bucket,
            model = definition.model, status = 'pending', createdAt = options.now(), updatedAt = options.now(),
            materials = util.copy(definition.materials), tools = util.copy(config.Tools), holder = holder
        }
        local reserved, reserveError = options.inventory.apply({ kind = 'reserve', installation = installation })
        if not reserved then return nil, reserveError end
        installation = reserved.installations[installation.id]
        -- Proveedor externo: la reserva ya esta registrada; ahora se cobran los materiales.
        local taken, takeError = options.holdings.take(installation)
        if not taken then
            if not cancel(installation, 'creation_rejected') then return nil, 'Cobro fallido y devolucion pendiente; revisar servidor.' end
            return nil, takeError or 'Faltan materiales de instalacion.'
        end
        local device, createError = options.registry.create(0, { type = definition.deviceType, model = installation.model,
            owner = installation.owner, position = position, rotation = installation.rotation, metadata = { installationId = installation.id } })
        if not device then
            if options.registry.status() then
                local existing, lookupError = service.find(installation.id)
                if not existing and not lookupError then
                    local refunded = cancel(installation, 'creation_rejected')
                    if not refunded then return nil, 'Fallo de creacion y compensacion pendiente; revisar servidor.' end
                end
            end
            return nil, createError or 'Creacion pendiente de recuperacion.'
        end
        local saved, finishError = finalize(installation, device)
        if not saved then return nil, finishError or 'Instalacion pendiente de recuperacion.' end
        options.audit('installation_committed', source, device.id)
        return { id = device.id, installationId = installation.id, status = 'committed' }
    end
    function service.recover()
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        for _, installation in pairs(snapshot.installations) do
            if installation.status == 'pending' then
                local device, findError = service.find(installation.id)
                if findError then return nil, findError end
                if not device and installation.holder and not options.holdings.available() then
                    -- Sin proveedor no se puede liquidar el cobro: se deja pendiente, sin bloquear el resto.
                    if options.log then options.log(('Instalacion %s pendiente: proveedor de objetos no disponible.'):format(installation.id)) end
                else
                    local result, reason
                    if device then result, reason = finalize(installation, device)
                    else result, reason = cancel(installation, 'recovery_cancelled') end
                    if not result then return nil, reason end
                end
            end
        end
        return true
    end
    function service.stream(source)
        local point, bucket = world(source)
        if not point then return nil, bucket end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        local result = {}
        for _, installation in pairs(snapshot.installations) do
            if installation.status == 'committed' and installation.bucket == bucket and distance(point, installation.position) <= config.StreamDistance then
                local device = options.registry.get(0, installation.deviceId)
                if device and device.state ~= 'retired' and device.metadata.installationId == installation.id
                    and util.equal(device.position, installation.position) then
                    result[#result + 1] = { id = device.id, model = installation.model, position = util.copy(installation.position),
                        rotation = util.copy(installation.rotation), kind = device.type }
                end
            end
        end
        table.sort(result, function(a, b) return distance(point, a.position) < distance(point, b.position) end)
        while #result > config.MaxStreamedProps do result[#result] = nil end
        return result
    end
    -- Desmontaje de cualquier producto instalado (camara, alarma...). Exige estar junto al dispositivo
    -- con las herramientas; tras el minijuego el dispositivo se retira, el montaje queda libre y el kit
    -- vuelve al inventario de quien desmonta. La bateria se da por gastada.
    local removals = {}
    local function installed(deviceId)
        if not OSSecurity.DeviceValidation.id(deviceId) then return nil, 'Dispositivo no valido.' end
        local device = options.registry.get(0, deviceId)
        local snapshot = options.inventory.snapshot()
        local installation = device and snapshot and device.metadata and device.metadata.installationId and snapshot.installations[device.metadata.installationId]
        if not device or not installation or installation.status ~= 'committed' or installation.deviceId ~= device.id then
            return nil, 'El dispositivo no esta montado fisicamente.'
        end
        if device.state == 'retired' then return nil, 'El dispositivo ya esta retirado.' end
        return device, installation
    end
    local function removable(source, session, deviceId)
        local device, installation = installed(deviceId)
        if not device then return nil, installation end
        if not options.canRemove(session.actor, device) then return nil, 'Sin permiso para desmontar este dispositivo.' end
        local point, bucket = world(source)
        if not point then return nil, bucket end
        if bucket ~= installation.bucket or distance(point, installation.position) > config.PlacementDistance then
            return nil, 'Acercate al dispositivo para desmontarlo.'
        end
        for _, item in ipairs(config.Tools) do
            if not options.holdings.has(session.actor, item, 1) then return nil, 'Faltan herramientas para desmontar.' end
        end
        return device, installation, point
    end
    function service.removeBegin(source, session, deviceId)
        local device, installation, point = removable(source, session, deviceId)
        if not device then return nil, installation end
        removals[source] = { token = session.token, deviceId = device.id, expires = options.now() + config.PlacementSeconds, origin = point }
        return { deviceId = device.id, model = installation.model, seconds = config.PlacementSeconds }
    end
    function service.removeConfirm(source, session, deviceId)
        local context = removals[source]
        removals[source] = nil
        if not context or context.token ~= session.token or context.deviceId ~= deviceId or options.now() > context.expires then
            return nil, 'Desmontaje no valido o caducado.'
        end
        local device, installation = removable(source, session, deviceId)
        if not device then return nil, installation end
        local definition = productOfModel(installation.model)
        local kit
        for item in pairs(definition and definition.materials or {}) do
            if OSSecurity.ItemCatalog[item].category == 'kit' then kit = item end
        end
        local retired, retireError = options.registry.retire(0, device.id)
        if not retired then return nil, retireError end
        local external = options.holdings.external()
        local removed, removeError = options.inventory.apply({ kind = 'remove', installationId = installation.id,
            principal = (kit and not external) and session.actor.principal or nil, item = (kit and not external) and kit or nil })
        if not removed then return nil, removeError end
        if kit and external then
            local holder = options.holdings.holder(source)
            local granted = holder and options.holdings.grant(holder, kit, 1, 'g6rm:' .. installation.id)
            if not granted and options.log then options.log(('Desmontaje %s: kit no devuelto; revisar inventario.'):format(installation.id)) end
        end
        if options.removed then options.removed(device.id) end
        options.audit('installation_removed', source, device.id)
        return { id = device.id, removed = true, kit = kit }
    end
    function service.removeCancel(source) removals[source] = nil end
    function service.cancel(source) contexts[source] = nil; removals[source] = nil end
    function service.clear() contexts = {}; removals = {} end
    return service
end
