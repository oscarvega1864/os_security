-- Bodycams Gruppe Sechs.
-- El vigilante de servicio con el objeto os_bodycam la enciende o apaga (/bodycam o "Usar" en el inventario).
-- Desde G6 Operations > Bodycams, un supervisor o administrador ve en directo lo que ve ese vigilante (la camara
-- del juego va sujeta a su pecho). Para que el personaje del vigilante exista en el equipo de quien mira, mientras
-- mira se amplia su radio de visibilidad de entidades (OneSync) y se restaura al salir.
-- Todo se valida aqui; la identidad, el empleo, el objeto y la posicion llegan por 'options'.
local util = OSSecurity.Util
OSSecurity.BodycamService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

function OSSecurity.BodycamService.new(options)
    local config = OSSecurity.GameplayConfig.Bodycams
    local T = OSSecurity.Brand.Text.bodycams
    local service = {}
    local active = {}   -- vigilante -> { since }
    local watching = {} -- quien mira -> vigilante

    local function name(source)
        local value = options.playerName and options.playerName(source)
        return type(value) == 'string' and value:gsub('[%c<>]', ''):sub(1, 64) or ('Jugador ' .. tostring(source))
    end
    local function notify(source, text, kind) if source and options.notify then options.notify(source, text, kind or 'info') end end
    local function canWatch(actor) return actor.kind == 'operations' and (actor.role == 'supervisor' or actor.role == 'admin') end
    local function stopViewers(target)
        for viewer, watched in pairs(watching) do
            if watched == target then
                watching[viewer] = nil
                options.cull(viewer, nil)
                options.send(viewer, 'bodycamLost', T.lost)
            end
        end
    end
    local function turnOff(source, message)
        if not active[source] then return end
        active[source] = nil
        stopViewers(source)
        options.send(source, 'bodycamState', false)
        if message then notify(source, message, 'warning') end
    end
    local function list(viewer)
        local here = options.world(viewer)
        local result = {}
        -- Incluye la propia (marcada): sirve para comprobar que funciona estando solo.
        for source, entry in pairs(active) do
            local point = options.world(source)
            result[#result + 1] = { id = source, name = name(source), since = entry.since, self = source == viewer or nil,
                distance = here and point and util.round(distance(here, point), 0) or nil }
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end

    function service.isOn(source) return active[source] ~= nil end
    -- Encender o apagar la propia bodycam.
    function service.toggle(source)
        if active[source] then
            turnOff(source)
            options.audit('bodycam_off', source)
            return { on = false, message = T.off }
        end
        if not options.isStaff(source) then return nil, T.needDuty end
        if not options.hasItem(source) then return nil, T.needItem end
        active[source] = { since = options.now() }
        options.send(source, 'bodycamState', true)
        options.audit('bodycam_on', source)
        return { on = true, message = T.on }
    end
    -- Tablet: bodycams encendidas (solo supervisores y administradores).
    function service.staffList(actor)
        if not canWatch(actor) then return nil, T.noAccess end
        return { items = list(actor.source), canWatch = true }
    end
    function service.live(actor, args)
        if not canWatch(actor) then return nil, T.noAccess end
        if not util.object(args, { target = true }) or not util.integer(args.target, 1, 2147483647) then return nil, T.notFound end
        local target = args.target
        if not active[target] then return nil, T.notFound end
        if not options.isStaff(target) or not options.hasItem(target) then turnOff(target, T.autoOff); return nil, T.notFound end
        local _, viewerBucket = options.world(actor.source)
        local point, targetBucket = options.world(target)
        if not point or viewerBucket ~= targetBucket then return nil, T.noSignal end
        watching[actor.source] = target
        options.cull(actor.source, config.CullingRadius)
        local cameras = list(actor.source)
        local index = 1
        for i, entry in ipairs(cameras) do if entry.id == target then index = i end end
        options.audit('bodycam_view', actor.source)
        return { target = target, name = name(target), since = active[target].since, position = util.copy(point), cameras = cameras, index = index }
    end
    function service.stop(source)
        if watching[source] then watching[source] = nil; options.cull(source, nil) end
        return { stopped = true }
    end
    -- Cada pocos segundos: quien deja el servicio o se queda sin el objeto, la apaga.
    function service.tick()
        for source in pairs(active) do
            if not options.connected(source) then active[source] = nil; stopViewers(source)
            elseif not options.isStaff(source) or not options.hasItem(source) then turnOff(source, T.autoOff) end
        end
    end
    function service.forget(source)
        active[source] = nil
        stopViewers(source)
        watching[source] = nil
    end
    return service
end
