-- Ganzua: forzar una puerta cerrada de una propiedad o negocio, o un vehiculo de os_devtools cerrado.
-- La dificultad sale del nivel de seguridad (bombin de la puerta; cierre del vehiculo): mas pines y zona
-- verde mas pequena. El minijuego es de la NUI; el servidor reserva el intento, comprueba distancia,
-- objeto y un tiempo minimo por pin, y decide: si sale bien, abre y avisa al dueno (y la alarma del
-- vehiculo salta); si sale mal, la ganzua puede romperse. Requiere el inventario de personajes.
OSSecurity.LockpickService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

function OSSecurity.LockpickService.new(options)
    local config = OSSecurity.GameplayConfig.Lockpick
    local service = {}
    local attempts = {} -- source -> { kind, id, vehicle, pins, started, expires, holder, n }
    local counter = 0

    -- Paso 1: elegir objetivo (vehiculo indicado por el cliente si esta cerrado; si no, la puerta mas
    -- cercana) y devolver el reto.
    function service.begin(source, vehicle)
        if not options.holdings.external() then return nil, 'La ganzua requiere el inventario de personajes (os_inventory).' end
        local holder = options.holdings.holder(source)
        if not holder then return nil, 'Personaje activo no disponible.' end
        if not options.holdings.has({ holder = holder }, config.Item, 1) then return nil, 'No tienes ganzua.' end
        local point = options.world(source)
        if not point then return nil, 'Posicion de servidor no disponible.' end
        local target
        if type(vehicle) == 'table' and vehicle.position and distance(point, vehicle.position) <= config.VehicleReach then
            local car = options.cars.pickTarget(vehicle)
            if car then target = { kind = 'vehicle', id = car.id, tier = car.tier, owner = car.owner, label = 'el vehiculo ' .. car.plate, vehicle = vehicle } end
        end
        if not target then
            local door, err = options.locks.pickTarget(source, config.Reach)
            if not door then return nil, err == 'No hay ninguna puerta con cerradura a tu alcance.' and 'No hay ninguna puerta o vehiculo cerrado a tu alcance.' or err end
            target = { kind = 'door', id = door.id, tier = door.tier, owner = door.owner, label = door.label, position = door.position }
        end
        local level = config.Levels[target.tier] or config.Levels[#config.Levels]
        counter = counter + 1
        attempts[source] = { kind = target.kind, id = target.id, vehicle = target.vehicle, position = target.position or vehicle.position,
            owner = target.owner, label = target.label, pins = level.pins, started = options.now(), expires = options.now() + config.Seconds,
            holder = holder, n = counter }
        return { kind = target.kind, tier = target.tier, pins = level.pins, zone = level.zone, speed = level.speed, seconds = config.Seconds }
    end

    -- Paso 2: resultado del minijuego. Un exito demasiado rapido para los pines se toma como fallo.
    function service.finish(source, success)
        local attempt = attempts[source]
        attempts[source] = nil
        if not attempt then return nil, 'No estas forzando nada.' end
        local now = options.now()
        local point = options.world(source)
        if not point or distance(point, attempt.position) > math.max(config.Reach, config.VehicleReach) + 1.0 then
            return nil, 'Te has alejado.'
        end
        if success == 'cancel' then return { ok = false, message = 'Lo dejas estar.' } end
        local fast = (now - attempt.started) < attempt.pins * config.MinPinSeconds
        if success ~= true or fast or now > attempt.expires then
            if options.random(100) <= config.BreakChance then
                local operation = { id = ('g6pick:%s:%d:%d'):format(attempt.holder, attempt.n, now), holder = attempt.holder, materials = { [config.Item] = 1 } }
                options.holdings.take(operation)
                return { ok = false, broken = true, message = 'La ganzua se ha roto.' }
            end
            return { ok = false, message = 'No lo consigues; la ganzua aguanta.' }
        end
        local opened, err
        if attempt.kind == 'vehicle' then opened, err = options.cars.forceOpen(source, attempt.vehicle)
        else opened, err = options.locks.forceOpen(attempt.id) end
        if not opened then return nil, err end
        if attempt.owner then
            options.notifyOwner(attempt.owner, ('Han forzado %s.'):format(attempt.kind == 'vehicle' and ('tu ' .. attempt.label:gsub('^el ', '')) or ('la puerta de ' .. attempt.label)),
                attempt.position)
        end
        options.audit('lockpick_' .. attempt.kind, source, tostring(attempt.id))
        return { ok = true, message = attempt.kind == 'vehicle' and 'Vehiculo abierto.' or 'Puerta abierta.' }
    end
    function service.drop(source) attempts[source] = nil end
    function service.clear() attempts = {} end
    return service
end
