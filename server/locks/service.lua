-- Cerraduras de puertas de propiedades y negocios.
-- Las puertas son las que ya trae el mapa (GTA o MLO) junto al punto de cada propiedad o negocio con
-- titular: un jugador cercano las detecta y el servidor las valida y guarda con el bombin de serie
-- (nivel 1); las de propiedades quedan cerradas con llave. La llave la tiene el titular de cada momento
-- (su personaje; un administrador no tiene llave de otros personajes): al reasignar la propiedad pasa al nuevo titular; sin titular no hay cerradura.
-- Para mas seguridad se cambia el bombin por otro kit (nivel 2 o 3) con la puerta abierta: el titular o
-- un tecnico G6 de servicio, con destornillador, tras el minijuego. El bombin retirado vuelve al inventario.
-- Todo se valida en el servidor; el cliente solo informa de las puertas que ve y pide acciones.
OSSecurity.LockService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

function OSSecurity.LockService.new(options)
    local config = OSSecurity.GameplayConfig.Locks
    local gameplayConfig = OSSecurity.GameplayConfig
    local util, state = OSSecurity.Util, OSSecurity.InventoryState
    local locks = {}
    local changes = {}  -- source -> { doorId, item, expires, changes, holder }
    local scanned = {}  -- 'kind:id' -> ultimo informe aceptado (limita la deteccion)

    local function doors() return options.inventory.doors() or {} end
    local function tierLabel(tier) return config.Tiers[tier] or config.Tiers[1] end
    local function key(site) return site.kind .. ':' .. site.id end
    -- Propiedades y negocios con titular, por clave.
    local function ownedSites()
        local result = {}
        if not options.sites or not options.sites.owned then return result end
        for _, site in ipairs(options.sites.owned()) do result[key(site)] = site end
        return result
    end
    -- Puertas activas: solo las de un sitio con titular.
    local function active()
        local owned, result = ownedSites(), {}
        for id, door in pairs(doors()) do if owned[key(door.site)] and not door.ignored then result[id] = door end end
        return result
    end
    function locks.list()
        local result = {}
        for _, door in pairs(active()) do
            result[#result + 1] = { id = door.id, model = door.model, position = util.copy(door.position), locked = door.locked }
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    -- Tablet Client: puertas de los sitios cuyo titular es el personaje activo del jugador.
    function locks.owned(source)
        local result, mine = {}, {}
        if not options.sites or not options.sites.owns then return result end
        for _, door in pairs(active()) do
            local k = key(door.site)
            if mine[k] == nil then mine[k] = options.sites.owns(source, door.site) == true end
            if mine[k] then
                result[#result + 1] = { id = door.id, site = options.sites.label(door.site) or k, tier = tierLabel(door.tier), level = door.tier or 1,
                    locked = door.locked == true }
            end
        end
        table.sort(result, function(a, b) if a.site ~= b.site then return a.site < b.site end; return a.id < b.id end)
        return result
    end
    -- Sitios con titular donde buscar puertas (el cliente escanea al acercarse).
    function locks.targets()
        local result = {}
        for _, site in pairs(ownedSites()) do result[#result + 1] = { kind = site.kind, id = site.id, position = util.copy(site.position) } end
        table.sort(result, function(a, b) return key(a) < key(b) end)
        return result
    end
    local function notify() if options.changed then options.changed(locks.list()) end end
    local function write(door)
        door.updatedAt = options.now()
        return options.inventory.apply({ kind = 'door', doorId = door.id, door = door })
    end
    -- Hojas de la misma puerta (dobles): mismo sitio y muy juntas.
    local function group(door, all)
        local result = {}
        for _, other in pairs(all) do
            if other.site.kind == door.site.kind and other.site.id == door.site.id and other.bucket == door.bucket
                and distance(other.position, door.position) <= config.PairDistance then result[#result + 1] = other end
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    -- Puerta activa mas cercana al jugador, en su bucket y a la distancia indicada.
    local function nearest(source, reach)
        local point, bucket = options.world(source)
        if not point then return nil, 'Posicion de servidor no disponible.' end
        local best, bestDistance
        for _, door in pairs(active()) do
            local d = distance(point, door.position)
            if door.bucket == bucket and d <= reach and (not bestDistance or d < bestDistance) then best, bestDistance = door, d end
        end
        if not best then return nil, 'No hay ninguna puerta con cerradura a tu alcance.' end
        return best, point
    end
    -- La llave es del personaje titular (tambien para los administradores).
    local function owner(source, door)
        return options.sites ~= nil and options.sites.owns(source, door.site) == true
    end
    -- Alta de una puerta nueva para un sitio (comun a la deteccion y al registro manual).
    local function add(site, model, position, bucket, all)
        local total, used = 0, {}
        for _, door in pairs(all) do
            total = total + 1
            if door.bucket == bucket and distance(door.position, position) <= config.DuplicateDistance then return nil, 'duplicate', door end
            if door.site.kind == site.kind and door.site.id == site.id then used[door.id] = true end
        end
        local perSite = 0
        for _ in pairs(used) do perSite = perSite + 1 end
        if total >= config.MaxDoors then return nil, 'Limite de puertas registradas alcanzado.' end
        if perSite >= config.MaxDoorsPerSite then return nil, 'Esa propiedad ya tiene el maximo de puertas.' end
        local id, index = nil, 1
        repeat id = ('%s%d_%d'):format(site.kind == 'property' and 'p' or 'n', site.id, index); index = index + 1 until not used[id]
        local door = { id = id, site = { kind = site.kind, id = site.id }, model = model, position = position, bucket = bucket, tier = 1,
            locked = config.LockedByDefault[site.kind] == true, changes = 0, updatedAt = options.now() }
        local saved, err = write(door)
        if not saved then return nil, err end
        all[id] = door
        return door
    end
    local function round(p) return { x = util.round(p.x, 3), y = util.round(p.y, 3), z = util.round(p.z, 3) } end

    -- Deteccion automatica: un cliente informa de las puertas del mapa junto a una propiedad con titular.
    -- report: { kind, id, doors = { { model, x, y, z }, ... } }. Devuelve cuantas puertas nuevas se guardan.
    function locks.report(source, report)
        if not util.object(report, { kind = true, id = true, doors = true }) or not util.array(report.doors, 32) then return 0 end
        local site = ownedSites()[tostring(report.kind) .. ':' .. tostring(report.id)]
        if not site then return 0 end
        local now = options.now()
        if scanned[key(site)] and now - scanned[key(site)] < config.ScanCooldown then return 0 end
        local point, bucket = options.world(source)
        if not point or bucket ~= 0 or distance(point, site.position) > config.ReportRange then return 0 end
        scanned[key(site)] = now
        local all, added = doors(), 0
        for _, entry in ipairs(report.doors) do
            if type(entry) == 'table' and util.integer(entry.model, -2147483648, 4294967295)
                and util.finite(entry.x) and util.finite(entry.y) and util.finite(entry.z) then
                local position = round(entry)
                if distance(position, site.position) <= config.DetectRadius then
                    local door, err = add(site, entry.model, position, bucket, all)
                    if door then added = added + 1
                    elseif err ~= 'duplicate' then break end
                end
            end
        end
        if added > 0 then
            notify()
            if options.log then options.log(('%d puertas detectadas en %s.'):format(added, options.sites.label(site) or key(site))) end
        end
        return added
    end

    -- Apano manual para una puerta que no se detecte sola (admin apuntando a ella).
    -- payload: { kind, id, model, position }.
    function locks.register(source, payload)
        if not options.isAdmin(source) then return nil, 'Se requiere ossecurity.admin.' end
        if not util.object(payload, { kind = true, id = true, model = true, position = true }) then
            return nil, 'Uso: /g6puerta <propiedad|negocio> <id>, apuntando a la puerta.'
        end
        local kind = ({ propiedad = 'property', property = 'property', negocio = 'business', business = 'business' })[payload.kind]
        local site = { kind = kind, id = payload.id }
        if not kind or not state.site(site) then return nil, 'Tipo o ID de propiedad no validos.' end
        if not util.integer(payload.model, -2147483648, 4294967295) or not state.vector(payload.position, 1000000) then
            return nil, 'No se ha detectado una puerta valida.'
        end
        if not options.sites or not options.sites.available() then return nil, 'Proveedor de propiedades no disponible.' end
        if not options.sites.get(site) then return nil, ('%s %d inexistente.'):format(OSSecurity.Sites.Labels[kind], site.id) end
        local point, bucket = options.world(source)
        if not point then return nil, 'Posicion de servidor no disponible.' end
        local position = round(payload.position)
        if distance(point, position) > gameplayConfig.AnchorAimDistance then return nil, 'La puerta apuntada esta demasiado lejos.' end
        local door, err, existing = add(site, payload.model, position, bucket, doors())
        if not door and err == 'duplicate' and existing.ignored and existing.site.kind == site.kind and existing.site.id == site.id then
            existing.ignored = nil -- se reactiva una puerta dada de baja
            local saved, saveError = write(existing)
            if not saved then return nil, saveError end
            door = existing
        elseif not door then return nil, err == 'duplicate' and ('Esa puerta ya esta registrada (%s).'):format(existing.id) or err end
        notify()
        options.audit('door_registered', source, door.id)
        return ('Puerta %s registrada en %s.'):format(door.id, options.sites.label(site))
    end
    function locks.unregister(source, doorId)
        if not options.isAdmin(source) then return nil, 'Se requiere ossecurity.admin.' end
        local door
        if doorId then door = state.doorId(doorId) and doors()[doorId] or nil
        else
            local point, bucket = options.world(source)
            for _, candidate in pairs(point and doors() or {}) do
                if candidate.bucket == bucket and distance(point, candidate.position) <= 3.0
                    and (not door or distance(point, candidate.position) < distance(point, door.position)) then door = candidate end
            end
        end
        if not door or door.ignored then return nil, 'Puerta no encontrada.' end
        -- Se conserva marcada como ignorada para que la deteccion automatica no la vuelva a anadir.
        door.ignored, door.locked = true, false
        local saved, err = write(door)
        if not saved then return nil, err end
        for player, context in pairs(changes) do if context.doorId == door.id then changes[player] = nil end end
        notify()
        options.audit('door_removed', source, door.id)
        return ('Puerta %s dada de baja: queda libre y no se volvera a detectar.'):format(door.id)
    end
    -- Resumen administrativo, una linea por puerta (incluidas las de sitios sin titular).
    function locks.describe()
        local list, owned, lines = doors(), ownedSites(), {}
        local ids = {}
        for id in pairs(list) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local door = list[id]
            lines[#lines + 1] = ('%s | %s | %s | %s | %.1f, %.1f, %.1f'):format(door.id,
                options.sites and options.sites.label(door.site) or key(door.site), tierLabel(door.tier),
                door.ignored and 'dada de baja' or not owned[key(door.site)] and 'sin titular' or (door.locked and 'cerrada' or 'abierta'),
                door.position.x, door.position.y, door.position.z)
        end
        return lines
    end

    -- Llave: abrir o cerrar la puerta mas cercana (y su otra hoja) estando junto a ella.
    function locks.toggle(source, doorId)
        local door, err = nearest(source, config.InteractDistance + 0.5)
        if not door then return nil, err end
        if doorId ~= nil and door.id ~= doorId then return nil, 'Acercate a la puerta.' end
        if not owner(source, door) then return nil, 'No tienes la llave de esta puerta.' end
        local leaves = group(door, active())
        for _, context in pairs(changes) do
            for _, leaf in ipairs(leaves) do
                if context.doorId == leaf.id then return nil, 'Estan cambiando el bombin de esta puerta.' end
            end
        end
        local locked = not door.locked
        for _, leaf in ipairs(leaves) do
            leaf.locked = locked
            local saved, saveError = write(leaf)
            if not saved then notify(); return nil, saveError end
        end
        notify()
        return { id = door.id, locked = locked, message = locked and 'Puerta cerrada con llave.' or 'Puerta abierta.' }
    end

    -- Ganzua: puerta cerrada mas cercana (cualquiera puede intentarlo) y apertura forzada de sus hojas.
    function locks.pickTarget(source, reach)
        local door, err = nearest(source, reach)
        if not door then return nil, err end
        if not door.locked then return nil, 'Esa puerta ya esta abierta.' end
        for _, context in pairs(changes) do if context.doorId == door.id then return nil, 'Estan cambiando el bombin de esta puerta.' end end
        local site = ownedSites()[key(door.site)]
        return { id = door.id, tier = door.tier, position = util.copy(door.position), owner = site and site.owner or nil,
            label = options.sites and options.sites.label(door.site) or key(door.site) }
    end
    function locks.forceOpen(doorId)
        local door = active()[doorId]
        if not door or not door.locked then return nil, 'La puerta ya no esta cerrada.' end
        for _, leaf in ipairs(group(door, active())) do
            leaf.locked = false
            local saved, err = write(leaf)
            if not saved then notify(); return nil, err end
        end
        notify()
        return true
    end

    -- Cambio de bombin, paso 1: comprobar todo y reservar el cambio mientras dura el minijuego.
    function locks.changeBegin(source, item)
        local tier = config.Cylinders[item]
        if not tier then return nil, 'Ese objeto no es un bombin.' end
        if not options.holdings.external() then return nil, 'El cambio de bombin requiere el inventario de personajes (os_inventory).' end
        local holder = options.holdings.holder(source)
        if not holder then return nil, 'Personaje activo no disponible.' end
        local door, point = nearest(source, config.InteractDistance)
        if not door then return nil, point end
        local staff = options.employment and options.employment(source, holder) == 'technician'
        if not owner(source, door) and not staff and not options.isAdmin(source) then return nil, 'Solo el titular o un tecnico G6 de servicio puede cambiar el bombin.' end
        if door.locked then return nil, 'Abre la puerta antes de cambiar el bombin.' end
        if door.cylinder == item then return nil, ('Esta puerta ya tiene un %s.'):format(tierLabel(tier):lower()) end
        local actor = { holder = holder }
        if not options.holdings.has(actor, item, 1) then return nil, 'No tienes ese bombin.' end
        for _, tool in ipairs(config.Tools) do
            if not options.holdings.has(actor, tool, 1) then return nil, 'Necesitas un destornillador.' end
        end
        for player, context in pairs(changes) do
            if player ~= source and context.doorId == door.id then return nil, 'Otra persona esta cambiando este bombin.' end
        end
        changes[source] = { doorId = door.id, item = item, holder = holder, changes = door.changes, expires = options.now() + config.ChangeSeconds }
        return { doorId = door.id, from = tierLabel(door.tier), to = tierLabel(tier), tier = tier }
    end
    -- Paso 2: resultado del minijuego. Cobra el bombin nuevo, guarda la puerta y devuelve el viejo.
    function locks.changeFinish(source, success)
        local context = changes[source]
        changes[source] = nil
        if not context then return nil, 'No hay ningun cambio de bombin en curso.' end
        if success ~= true then return nil, 'Cambio de bombin cancelado: no se ha gastado nada.' end
        if options.now() > context.expires then return nil, 'El cambio de bombin ha caducado.' end
        local door = active()[context.doorId]
        local point, bucket = options.world(source)
        if not door or door.changes ~= context.changes or door.locked or not point or bucket ~= door.bucket
            or distance(point, door.position) > config.InteractDistance + 0.5 then
            return nil, 'La puerta ha cambiado o te has alejado; no se ha gastado nada.'
        end
        local holder = options.holdings.holder(source)
        if holder ~= context.holder then return nil, 'El personaje activo cambio; no se ha gastado nada.' end
        local operation = { id = ('g6lk:%s:%d'):format(door.id, door.changes + 1), holder = holder, materials = { [context.item] = 1 } }
        local taken, takeError = options.holdings.take(operation)
        if not taken then
            options.holdings.refund(operation)
            return nil, takeError or 'No tienes ese bombin.'
        end
        local previous = door.cylinder
        door.cylinder, door.tier, door.changes = context.item, config.Cylinders[context.item], door.changes + 1
        local saved, saveError = write(door)
        if not saved then
            options.holdings.refund(operation)
            return nil, saveError
        end
        notify()
        if previous then
            local granted = options.holdings.grant(holder, previous, 1, operation.id .. ':old')
            if not granted and options.log then options.log(('Puerta %s: bombin retirado no devuelto; revisar inventario.'):format(door.id)) end
        end
        options.audit('door_cylinder', source, door.id)
        return { id = door.id, tier = door.tier,
            message = ('Bombin cambiado: %s instalado.%s'):format(tierLabel(door.tier):lower(), previous and ' El anterior vuelve a tu inventario.' or '') }
    end
    -- Nivel de seguridad (1-3) de una puerta activa, para futuros robos y ganzuas.
    function locks.security(doorId)
        local door = state.doorId(doorId) and active()[doorId]
        return door and door.tier or nil
    end
    function locks.drop(source) changes[source] = nil end
    function locks.clear() changes = {}; scanned = {} end
    return locks
end
