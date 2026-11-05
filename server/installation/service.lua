local util = OSSecurity.Util
OSSecurity.InstallationService = {}

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end

local function canonical(vector)
    return { x = OSSecurity.ComponentWear.number(vector.x), y = OSSecurity.ComponentWear.number(vector.y), z = OSSecurity.ComponentWear.number(vector.z) }
end

function OSSecurity.InstallationService.new(options)
    local config, contexts, watching = OSSecurity.GameplayConfig, {}, false
    local service = {}
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
    function service.begin(source, session)
        if session.actor.kind ~= 'operations' or not config.Profiles[session.actor.role].install then return nil, 'Perfil sin permiso de instalacion.' end
        local point, bucket = world(source)
        if not point then return nil, bucket end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        if not options.inventory.has(session.actor.principal, 'os_cctv_kit', 1) then return nil, 'No posee un kit CCTV.' end
        for _, item in ipairs(config.Tools) do
            if not options.inventory.has(session.actor.principal, item, 1) then return nil, 'Faltan herramientas de instalacion.' end
        end
        for item, amount in pairs(config.Materials) do
            if not options.inventory.has(session.actor.principal, item, amount) then return nil, 'Faltan materiales de instalacion.' end
        end
        local mounts = {}
        for id, anchor in pairs(snapshot.anchors) do
            if anchor.installer == session.actor.principal and anchor.bucket == bucket and distance(point, anchor.position) <= config.PlacementDistance then
                local occupied = false
                for _, installation in pairs(snapshot.installations) do
                    if installation.anchorId == id and installation.status ~= 'cancelled' then occupied = true end
                end
                if not occupied then mounts[#mounts + 1] = { id = id, position = util.copy(anchor.position), normal = util.copy(anchor.normal), radius = anchor.radius } end
            end
        end
        table.sort(mounts, function(a, b) return a.id < b.id end)
        if #mounts == 0 then return nil, 'No hay un montaje libre asignado y cercano.' end
        contexts[source] = { token = session.token, origin = point, bucket = bucket, expires = options.now() + config.PlacementSeconds }
        watch()
        return { model = config.CameraModel, mounts = mounts, maxDistance = config.PlacementDistance, seconds = config.PlacementSeconds }
    end
    local function finalize(installation, device)
        if device.type ~= 'cctv_camera' or device.model ~= installation.model or device.owner ~= installation.owner
            or not util.equal(device.position, installation.position) or not util.equal(device.rotation, installation.rotation) then
            return nil, 'El dispositivo no coincide con la reserva; requiere revision.'
        end
        if device.state == 'retired' then
            return options.inventory.apply({ kind = 'cancel', installationId = installation.id, reason = 'retired' })
        end
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
            or not util.object(proposal, { anchorId = true, position = true, rotation = true }) then return nil, 'Colocacion no valida o caducada.' end
        local point, bucket = world(source)
        if not point then return nil, bucket end
        if bucket ~= context.bucket or distance(point, context.origin) > config.MaxPlacementMove then return nil, 'Se ha alejado de la colocacion.' end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        local anchor = type(proposal.anchorId) == 'string' and snapshot.anchors[proposal.anchorId]
        if not anchor or anchor.installer ~= session.actor.principal or anchor.bucket ~= bucket
            or not OSSecurity.InventoryState.vector(proposal.position, 1000000)
            or not OSSecurity.InventoryState.vector(proposal.rotation, 360)
            or math.abs(proposal.rotation.x) > 45 or math.abs(proposal.rotation.y) > 5
            or distance(point, proposal.position) > config.PlacementDistance
            or distance(anchor.position, proposal.position) > anchor.radius then return nil, 'Montaje, proximidad o coordenadas no autorizados.' end
        local delta = { x = proposal.position.x - anchor.position.x, y = proposal.position.y - anchor.position.y, z = proposal.position.z - anchor.position.z }
        local planeDistance = delta.x * anchor.normal.x + delta.y * anchor.normal.y + delta.z * anchor.normal.z
        if math.abs(planeDistance) > 0.08 then return nil, 'La posicion no pertenece al plano de montaje autorizado.' end
        local position = canonical({ x = proposal.position.x - planeDistance * anchor.normal.x + 0.02 * anchor.normal.x,
            y = proposal.position.y - planeDistance * anchor.normal.y + 0.02 * anchor.normal.y,
            z = proposal.position.z - planeDistance * anchor.normal.z + 0.02 * anchor.normal.z })
        local installation = {
            id = ('g6i_%010d'):format(snapshot.nextInstallation), anchorId = anchor.id, owner = anchor.owner,
            installer = session.actor.principal, position = position, rotation = canonical(proposal.rotation), bucket = bucket,
            model = config.CameraModel, status = 'pending', createdAt = options.now(), updatedAt = options.now(),
            materials = util.copy(config.Materials), tools = util.copy(config.Tools)
        }
        local reserved, reserveError = options.inventory.apply({ kind = 'reserve', installation = installation })
        if not reserved then return nil, reserveError end
        installation = reserved.installations[installation.id]
        local device, createError = options.registry.create(0, { type = 'cctv_camera', model = installation.model,
            owner = installation.owner, position = position, rotation = installation.rotation, metadata = { installationId = installation.id } })
        if not device then
            if options.registry.status() then
                local existing, lookupError = service.find(installation.id)
                if not existing and not lookupError then
                    local refunded = options.inventory.apply({ kind = 'cancel', installationId = installation.id, reason = 'creation_rejected' })
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
                local result, reason
                if device then result, reason = finalize(installation, device)
                else result, reason = options.inventory.apply({ kind = 'cancel', installationId = installation.id, reason = 'recovery_cancelled' }) end
                if not result then return nil, reason end
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
                    result[#result + 1] = { id = device.id, model = installation.model, position = util.copy(installation.position), rotation = util.copy(installation.rotation) }
                end
            end
        end
        table.sort(result, function(a, b) return distance(point, a.position) < distance(point, b.position) end)
        while #result > config.MaxStreamedProps do result[#result] = nil end
        return result
    end
    function service.cancel(source) contexts[source] = nil end
    function service.clear() contexts = {} end
    return service
end
