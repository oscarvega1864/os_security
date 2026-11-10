-- Zonas de montaje gestionadas desde la tablet G6 Operations (seccion Instalaciones).
-- Un tecnico con permiso de instalacion elige el cliente (el mismo o un jugador a su lado), marca la zona
-- con el visor de camara y la zona queda a su nombre: despues instala en ella desde la misma tablet.
-- Si el cliente es titular de una propiedad o negocio cercano, la zona queda vinculada a ese sitio.
-- El cliente solo propone punto, normal, tamano y el nombre del lugar; el servidor valida todo.
local util = OSSecurity.Util
OSSecurity.ZoneService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

-- Punto a 0,1 mm y normal unitaria a 9 decimales (componentes residuales del raycast a cero).
function OSSecurity.ZoneService.normalize(position, normal)
    local round = util.round
    normal = { x = round(normal.x, 6), y = round(normal.y, 6), z = round(normal.z, 6) }
    local length = math.sqrt(normal.x ^ 2 + normal.y ^ 2 + normal.z ^ 2)
    if length < 0.001 then return nil, 'La normal no puede ser cero.' end
    for _, axis in ipairs({ 'x', 'y', 'z' }) do normal[axis] = round(normal[axis] / length, 9) end
    return { x = round(position.x, 4), y = round(position.y, 4), z = round(position.z, 4) }, normal
end

-- Superficie a partir de la normal: suelo, techo o pared.
function OSSecurity.ZoneService.surface(normal)
    if normal.z >= 0.7 then return 'floor' elseif normal.z <= -0.7 then return 'ceiling' end
    return 'wall'
end

function OSSecurity.ZoneService.new(options)
    local config = OSSecurity.GameplayConfig
    local zonesConfig = config.Zones
    local zones = {}
    local pending = {} -- source -> zona en marcado { id, owner, client, site, installer, expires }

    local function canInstall(actor)
        return actor and actor.kind == 'operations' and config.Profiles[actor.role] and config.Profiles[actor.role].install == true
    end
    local function clean(text)
        if type(text) ~= 'string' then return nil end
        text = text:gsub('[%c<>]', ''):sub(1, 64)
        return text ~= '' and text or nil
    end
    local function nextId(snapshot)
        local highest = 0
        for id in pairs(snapshot.anchors) do
            local number = tonumber(id:match('^zona_(%d+)$'))
            if number and number > highest then highest = number end
        end
        return ('zona_%d'):format(highest + 1)
    end
    -- Estado de una zona: libre, pendiente o instalada (con su dispositivo).
    local function status(snapshot, id)
        local result = { status = 'free', used = false }
        for _, installation in pairs(snapshot.installations) do
            if installation.anchorId == id then
                result.used = true
                if installation.status == 'pending' then result.status = 'pending'
                elseif installation.status == 'committed' then
                    result.status, result.deviceId = 'installed', installation.deviceId
                    local definition = options.productOfModel(installation.model)
                    result.deviceType = definition and definition.deviceType or nil
                end
            end
        end
        return result
    end
    -- Clientes posibles: el propio tecnico y los jugadores a su lado en el mismo bucket.
    local function clients(source)
        local here, bucket = options.world(source)
        local list = {}
        if not here then return list end
        for _, player in ipairs(options.players and options.players() or {}) do
            local point, playerBucket = options.world(player)
            if player == source or (point and playerBucket == bucket and distance(point, here) <= zonesConfig.ClientDistance) then
                list[#list + 1] = { id = player, name = clean(options.playerName and options.playerName(player)) or ('Jugador ' .. player), self = player == source }
            end
        end
        table.sort(list, function(a, b) if a.self ~= b.self then return a.self end; return a.id < b.id end)
        return list
    end

    -- Seccion Instalaciones: zonas del tecnico (todas para un administrador), clientes cercanos y kits.
    function zones.list(source, session)
        local actor = session.actor
        if not canInstall(actor) then return nil, 'Perfil sin permiso de instalacion.' end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        local here = options.world(source)
        local list = {}
        for id, anchor in pairs(snapshot.anchors) do
            if actor.role == 'admin' or anchor.installer == actor.principal then
                local state = status(snapshot, id)
                list[#list + 1] = { id = id, place = anchor.place, client = anchor.client, createdAt = anchor.createdAt,
                    surface = OSSecurity.ZoneService.surface(anchor.normal), size = util.round(anchor.radius * 2, 2),
                    site = anchor.site and options.sites and options.sites.label(anchor.site) or nil,
                    distance = here and util.round(distance(here, anchor.position), 1) or nil,
                    mine = anchor.installer == actor.principal, status = state.status, deviceId = state.deviceId, deviceType = state.deviceType,
                    deletable = not state.used and (anchor.installer == actor.principal or actor.role == 'admin') }
            end
        end
        -- La mas cercana primero (la que tienes delante); sin posicion conocida, la mas reciente.
        table.sort(list, function(a, b)
            if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
            if (a.createdAt or 0) ~= (b.createdAt or 0) then return (a.createdAt or 0) > (b.createdAt or 0) end
            return a.id < b.id
        end)
        local counts = options.holdings.list(actor) or {}
        local kits = {}
        for item, definition in pairs(config.Products) do
            local catalog = OSSecurity.ItemCatalog[item]
            kits[#kits + 1] = { id = item, name = catalog and catalog.name or item, deviceType = definition.deviceType, count = counts[item] or 0 }
        end
        table.sort(kits, function(a, b) return a.id < b.id end)
        return { zones = list, clients = clients(source), kits = kits, installDistance = config.PlacementDistance }
    end

    -- Paso 1: elegir cliente. Reserva el marcado (unos minutos) y devuelve el id de la zona.
    function zones.begin(source, session, client)
        local actor = session.actor
        if not canInstall(actor) then return nil, 'Perfil sin permiso de instalacion.' end
        if not util.integer(client, 1, 2147483647) then return nil, 'Elige un cliente.' end
        local allowed
        for _, entry in ipairs(clients(source)) do if entry.id == client then allowed = entry end end
        if not allowed then return nil, 'El cliente debe estar a tu lado.' end
        local owner = options.identity.resolve(client)
        if not owner then return nil, 'Cliente no disponible.' end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        local count = 0
        for _ in pairs(snapshot.anchors) do count = count + 1 end
        if count >= config.MaxAnchors then return nil, 'Limite de zonas alcanzado: borra zonas sin usar.' end
        -- Propiedad o negocio del cliente cerca del tecnico: la zona se vincula a ese sitio.
        local site, siteLabel
        local here = options.world(source)
        local alias = options.alias and options.alias(client)
        if here and alias and options.sites and options.sites.owned then
            local best
            for _, candidate in ipairs(options.sites.owned()) do
                local d = distance(here, candidate.position)
                if candidate.owner == alias and d <= zonesConfig.SiteDistance and (not best or d < best) then
                    best, site = d, { kind = candidate.kind, id = candidate.id }
                end
            end
            siteLabel = site and options.sites.label(site) or nil
        end
        local id = nextId(snapshot)
        pending[source] = { id = id, owner = owner, installer = actor.principal, client = allowed.name, site = site,
            expires = options.now() + zonesConfig.MarkSeconds }
        return { id = id, client = allowed.name, site = siteLabel, seconds = zonesConfig.MarkSeconds }
    end

    -- Paso 2: el visor envia la zona marcada. Se revalida perfil, cercania y datos.
    function zones.commit(source, payload)
        local mark = pending[source]
        pending[source] = nil
        if not mark or options.now() > mark.expires then return nil, 'Marcado caducado: vuelve a empezar desde la tablet.' end
        local actor = options.profile(source)
        if not canInstall(actor) or actor.principal ~= mark.installer then return nil, 'Perfil sin permiso de instalacion.' end
        if not util.object(payload, { radius = true, position = true, normal = true, place = true })
            or not util.finite(payload.radius) or payload.radius < 0.25 or payload.radius > 2
            or not OSSecurity.InventoryState.vector(payload.position, 1000000) or not OSSecurity.InventoryState.vector(payload.normal, 1000) then
            return nil, 'Zona no valida.'
        end
        local here, bucket = options.world(source)
        if not here then return nil, 'Posicion no disponible.' end
        if distance(here, payload.position) > config.AnchorAimDistance then return nil, 'La zona esta demasiado lejos.' end
        local position, normal = OSSecurity.ZoneService.normalize(payload.position, payload.normal)
        if not position then return nil, normal end
        local result, err = options.inventory.apply({ kind = 'anchor', anchor = { id = mark.id, owner = mark.owner, installer = mark.installer,
            position = position, normal = normal, radius = util.round(payload.radius, 3), bucket = bucket, site = mark.site and util.copy(mark.site) or nil,
            place = clean(payload.place), client = mark.client, createdAt = options.now() } })
        if not result then return nil, err end
        options.audit('zone_created', source)
        return { id = mark.id, message = ('Zona %s registrada. Ya puedes instalar en ella desde la tablet.'):format(mark.id) }
    end

    function zones.delete(source, session, anchorId)
        local actor = session.actor
        if not canInstall(actor) then return nil, 'Perfil sin permiso de instalacion.' end
        local snapshot, err = options.inventory.snapshot()
        if not snapshot then return nil, err end
        local anchor = type(anchorId) == 'string' and snapshot.anchors[anchorId]
        if not anchor or (anchor.installer ~= actor.principal and actor.role ~= 'admin') then return nil, 'Zona no disponible.' end
        local result, reason = options.inventory.apply({ kind = 'unanchor', anchorId = anchorId })
        if not result then return nil, reason end
        options.audit('zone_deleted', source)
        return { deleted = anchorId }
    end

    function zones.cancel(source) pending[source] = nil end
    function zones.clear() pending = {} end
    return zones
end
