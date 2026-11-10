-- Seguridad de vehiculos de os_devtools: cierre centralizado (mando) y alarma.
-- Se instalan sentado al volante con el motor parado, con un minijuego propio (embellecedor bajo el
-- volante, cables con multimetro y prueba del mando). El dueno (personaje activo), un tecnico G6 de
-- servicio o un administrador instalan; solo el personaje dueno abre, cierra y arranca. Con la alarma y el
-- vehiculo cerrado, intentar entrar la hace sonar y avisa al dueno. Logica pura: los natives (bloqueo de
-- puertas, efectos, avisos) los aplica server/main.lua a traves de options.effects.
OSSecurity.CarService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

-- Matricula de os_devtools: OS + ID con seis cifras (OS000012). Devuelve el ID o nil.
function OSSecurity.CarService.plateId(plate)
    if type(plate) ~= 'string' then return nil end
    local digits = plate:gsub('%s+', ''):match('^OS(%d+)$')
    local id = digits and tonumber(digits)
    return id and id >= 1 and id <= 2147483646 and math.tointeger(id) or nil
end

function OSSecurity.CarService.new(options)
    local config = OSSecurity.GameplayConfig.Cars
    local util = OSSecurity.Util
    local cars = {}
    local installs, sounding, lastAlarm = {}, {}, {}
    local hotwires, hotwired = {}, {} -- source -> intento en curso; carId -> source que le hizo el puente
    local LABELS = { lock = 'cierre centralizado', alarm = 'alarma' }

    local function records() return options.inventory.cars() or {} end
    local function trim(plate) return type(plate) == 'string' and (plate:gsub('%s+', '')) or nil end
    -- Vehiculo de os_devtools por matricula, comprobado contra su registro.
    local function asset(plate)
        local id = OSSecurity.CarService.plateId(plate)
        if not id then return nil end
        local record = options.vehicles.asset(id)
        if type(record) ~= 'table' or trim(record.plate) ~= trim(plate) then return nil end
        return { id = id, plate = trim(plate), owner = type(record.owner) == 'string' and record.owner or nil }
    end
    -- La llave es del personaje dueno (tambien para los administradores: no abren coches de otros personajes).
    local function owns(source, car)
        local alias = options.vehicles.alias(source)
        return car.owner ~= nil and alias ~= nil and alias == car.owner
    end
    local function save(record)
        record.updatedAt = options.now()
        return options.inventory.apply({ kind = 'car', carId = tostring(record.id), car = record })
    end
    local function blank(car) return { id = car.id, plate = car.plate, lock = false, alarm = false, locked = false, changes = 0, updatedAt = options.now() } end

    -- Instalacion, paso 1: al volante, motor parado, permiso, kit y herramientas. Reserva hasta el minijuego.
    function cars.installBegin(source, item)
        local kind = config.Kits[item]
        if not kind then return nil, 'Ese objeto no se instala en vehiculos.' end
        if not options.holdings.external() then return nil, 'La instalacion en vehiculos requiere el inventario de personajes (os_inventory).' end
        local holder = options.holdings.holder(source)
        if not holder then return nil, 'Personaje activo no disponible.' end
        local driving = options.vehicles.driving(source)
        if not driving then return nil, 'Sientate al volante del vehiculo para instalarlo.' end
        if driving.engine or driving.speed > 1.0 then return nil, 'Para el vehiculo y apaga el motor.' end
        local car = asset(driving.plate)
        if not car then return nil, 'Solo se instala en vehiculos registrados (matricula OS).' end
        local staff = options.employment and options.employment(source, holder) == 'technician'
        if not owns(source, car) and not staff and not options.isAdmin(source) then return nil, 'Solo el dueno o un tecnico G6 de servicio puede instalarlo.' end
        local record = records()[tostring(car.id)] or blank(car)
        if record[kind] then return nil, ('Este vehiculo ya tiene %s.'):format(LABELS[kind]) end
        if kind == 'alarm' and not record.lock then return nil, 'Instala antes el cierre centralizado: la alarma se arma al cerrar.' end
        local actor = { holder = holder }
        if not options.holdings.has(actor, item, 1) then return nil, 'No tienes ese kit.' end
        for _, tool in ipairs(config.Tools) do
            if not options.holdings.has(actor, tool, 1) then return nil, 'Necesitas un destornillador.' end
        end
        installs[source] = { carId = car.id, plate = car.plate, item = item, kind = kind, holder = holder, changes = record.changes,
            expires = options.now() + config.InstallSeconds }
        return { kind = kind, label = LABELS[kind], plate = car.plate }
    end
    -- Paso 2: resultado del minijuego. Cobra el kit y guarda el equipo del vehiculo.
    function cars.installFinish(source, success)
        local context = installs[source]
        installs[source] = nil
        if not context then return nil, 'No hay ninguna instalacion en curso.' end
        if success ~= true then return nil, 'Instalacion cancelada: no se ha gastado nada.' end
        if options.now() > context.expires then return nil, 'La instalacion ha caducado.' end
        local driving = options.vehicles.driving(source)
        if not driving or trim(driving.plate) ~= context.plate then return nil, 'Has salido del vehiculo; no se ha gastado nada.' end
        if options.holdings.holder(source) ~= context.holder then return nil, 'El personaje activo cambio; no se ha gastado nada.' end
        local car = asset(driving.plate)
        local record = car and (records()[tostring(car.id)] or blank(car))
        if not record or record.changes ~= context.changes or record[context.kind] then return nil, 'El vehiculo ha cambiado; no se ha gastado nada.' end
        local operation = { id = ('g6car:%d:%d'):format(record.id, record.changes + 1), holder = context.holder, materials = { [context.item] = 1 } }
        local taken, takeError = options.holdings.take(operation)
        if not taken then options.holdings.refund(operation); return nil, takeError or 'No tienes ese kit.' end
        record[context.kind], record.changes = true, record.changes + 1
        local saved, saveError = save(record)
        if not saved then options.holdings.refund(operation); return nil, saveError end
        options.audit('car_' .. context.kind, source, tostring(record.id))
        return { kind = context.kind, plate = record.plate,
            message = context.kind == 'lock' and 'Cierre centralizado instalado: abre y cierra con el mando (L).'
                or 'Alarma instalada: se arma al cerrar con el mando.' }
    end

    -- Llave: abrir o cerrar un vehiculo propio. Sin kit, con la llave en la cerradura (ManualDistance o
    -- dentro); con cierre centralizado, con el mando a KeyDistance (destellos y pitido).
    function cars.toggle(source, vehicle)
        if type(vehicle) ~= 'table' then return nil, 'Vehiculo no disponible.' end
        local car = asset(vehicle.plate)
        if not car then return nil, 'Ese vehiculo no tiene dueno registrado (matricula OS).' end
        local record = records()[tostring(car.id)] or blank(car)
        local point = options.world(source)
        local reach = record.lock and config.KeyDistance or config.ManualDistance
        if not point or distance(point, vehicle.position) > reach then
            return nil, record.lock and 'Acercate al vehiculo.' or 'Acercate a la puerta: sin cierre centralizado se cierra con la llave.'
        end
        if not owns(source, car) then return nil, 'No tienes la llave de este vehiculo.' end
        record.locked = not record.locked
        if record.locked then hotwired[record.id] = nil end -- el dueno lo recupera: el puente deja de valer
        local saved, err = save(record)
        if not saved then return nil, err end
        if not record.locked and sounding[record.id] then
            sounding[record.id] = nil
            options.effects.alarm(vehicle, 0)
        end
        options.effects.locked(vehicle, record.locked, record.alarm, record.lock)
        return { locked = record.locked, alarm = record.alarm,
            message = record.locked and (record.alarm and 'Vehiculo cerrado y alarma armada.' or 'Vehiculo cerrado.') or 'Vehiculo abierto.' }
    end
    -- Intento de entrar en un vehiculo cerrado (informado por el cliente de quien lo intenta).
    function cars.tamper(source, vehicle)
        if type(vehicle) ~= 'table' then return nil end
        local car = asset(vehicle.plate)
        local record = car and records()[tostring(car.id)]
        if not record or not record.locked then return nil end
        local point = options.world(source)
        if not point or distance(point, vehicle.position) > config.TamperDistance then return nil end
        if owns(source, car) then return nil, 'Esta cerrado: abrelo con el mando (L).' end
        if not record.alarm then return nil, 'Esta cerrado.' end
        local now = options.now()
        if sounding[record.id] and sounding[record.id] > now then return true end
        if lastAlarm[record.id] and now - lastAlarm[record.id] < config.AlarmCooldown then return nil end
        lastAlarm[record.id], sounding[record.id] = now, now + config.AlarmSeconds
        options.effects.alarm(vehicle, config.AlarmSeconds)
        if car.owner then options.effects.notifyOwner(car.owner, ('Salta la alarma de tu vehiculo %s.'):format(record.plate), vehicle.position) end
        options.audit('car_alarm', source, tostring(record.id))
        return true
    end
    -- Ganzua: vehiculo cerrado (cualquiera puede intentarlo) y apertura forzada.
    function cars.pickTarget(vehicle)
        if type(vehicle) ~= 'table' then return nil, 'Vehiculo no disponible.' end
        local car = asset(vehicle.plate)
        local record = car and records()[tostring(car.id)]
        if not record or not record.locked then return nil, 'Ese vehiculo no esta cerrado.' end
        return { id = record.id, tier = record.lock and 2 or 1, owner = car.owner, plate = record.plate, alarm = record.alarm }
    end
    function cars.forceOpen(source, vehicle)
        local car = vehicle and asset(vehicle.plate)
        local record = car and records()[tostring(car.id)]
        if not record or not record.locked then return nil, 'El vehiculo ya no esta cerrado.' end
        record.locked = false
        local saved, err = save(record)
        if not saved then return nil, err end
        options.effects.locked(vehicle, false, record.alarm, false)
        if record.alarm then
            local now = options.now()
            lastAlarm[record.id], sounding[record.id] = now, now + config.AlarmSeconds
            options.effects.alarm(vehicle, config.AlarmSeconds)
        end
        options.audit('car_forced', source, tostring(record.id))
        return { alarm = record.alarm }
    end
    -- Arrancar o apagar: solo quien conduce un vehiculo propio (o le ha hecho un puente). Los vehiculos que no
    -- son de os_devtools quedan libres, como en GTA.
    function cars.engine(source)
        local driving = options.vehicles.driving(source)
        if not driving then return nil, 'Sientate al volante.' end
        local car = asset(driving.plate)
        if not car then return { free = true } end
        if owns(source, car) then return { owned = true } end
        if hotwired[car.id] == source then return { hotwired = true } end
        local holder = options.holdings.external() and options.holdings.holder(source)
        local tool = holder and options.holdings.has({ holder = holder }, config.Hotwire.Tool, 1)
        return nil, tool and 'No tienes la llave. Pulsa otra vez para hacer un puente.' or 'No tienes la llave de este vehiculo.', tool == true
    end
    -- Puente, paso 1: al volante, motor apagado, sin la llave y con destornillador.
    function cars.hotwireBegin(source)
        local driving = options.vehicles.driving(source)
        if not driving then return nil, 'Sientate al volante.' end
        if driving.engine then return nil, 'El motor ya esta en marcha.' end
        local car = asset(driving.plate)
        if not car then return nil, 'Este vehiculo no necesita llave.' end
        if owns(source, car) or hotwired[car.id] == source then return nil, 'Ya puedes arrancarlo con la llave.' end
        if not options.holdings.external() then return nil, 'El puente requiere el inventario de personajes (os_inventory).' end
        local holder = options.holdings.holder(source)
        if not holder or not options.holdings.has({ holder = holder }, config.Hotwire.Tool, 1) then return nil, 'Necesitas un destornillador.' end
        local record = records()[tostring(car.id)]
        local tier = record and record.alarm and 3 or (record and record.lock and 2) or 1
        hotwires[source] = { carId = car.id, plate = car.plate, started = options.now(), expires = options.now() + config.Hotwire.Seconds }
        if record and record.alarm and options.vehicles.entity then
            local vehicle = options.vehicles.entity(source)
            if vehicle then
                local now = options.now()
                lastAlarm[record.id], sounding[record.id] = now, now + config.AlarmSeconds
                options.effects.alarm(vehicle, config.AlarmSeconds)
            end
        end
        if car.owner and record and record.alarm then
            options.effects.notifyOwner(car.owner, ('Estan intentando arrancar tu vehiculo %s.'):format(car.plate), nil)
        end
        local level = config.Hotwire.Levels[tier]
        return { tier = tier, decoys = level.decoys, band = level.band, plate = car.plate, seconds = config.Hotwire.Seconds }
    end
    -- Paso 2: resultado del minijuego. Con exito, este jugador puede arrancar y apagar ese vehiculo.
    function cars.hotwireFinish(source, success)
        local attempt = hotwires[source]
        hotwires[source] = nil
        if not attempt then return nil, 'No estas haciendo ningun puente.' end
        if success ~= true then return nil, 'El puente no ha salido.' end
        local now = options.now()
        if now > attempt.expires or now - attempt.started < config.Hotwire.MinSeconds then return nil, 'El puente no ha salido.' end
        local driving = options.vehicles.driving(source)
        if not driving or trim(driving.plate) ~= attempt.plate then return nil, 'Has salido del vehiculo.' end
        hotwired[attempt.carId] = source
        local car = asset(driving.plate)
        if car and car.owner then options.effects.notifyOwner(car.owner, ('Han hecho un puente a tu vehiculo %s.'):format(attempt.plate), nil) end
        options.audit('car_hotwired', source, tostring(attempt.carId))
        return { message = 'Puente hecho: el motor arranca. Y para arrancar o apagar.' }
    end
    -- Estado que deben tener las entidades de ese vehiculo (sincronizacion periodica).
    function cars.desired(plate)
        local id = OSSecurity.CarService.plateId(plate)
        local record = id and records()[tostring(id)]
        if not record or (not record.lock and not record.locked) then return nil end
        return { locked = record.locked, alarm = record.alarm }
    end
    function cars.describe()
        local lines, ids = {}, {}
        local list = records()
        for id in pairs(list) do ids[#ids + 1] = tonumber(id) end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local record = list[tostring(id)]
            lines[#lines + 1] = ('%s | cierre: %s | alarma: %s | %s'):format(record.plate, record.lock and 'si' or 'no', record.alarm and 'si' or 'no',
                record.locked and 'cerrado' or 'abierto')
        end
        return lines
    end
    function cars.tick()
        local now = options.now()
        for id, untilAt in pairs(sounding) do if untilAt <= now then sounding[id] = nil end end
    end
    function cars.drop(source)
        installs[source], hotwires[source] = nil, nil
        for id, player in pairs(hotwired) do if player == source then hotwired[id] = nil end end
    end
    function cars.clear() installs, sounding, lastAlarm, hotwires, hotwired = {}, {}, {}, {}, {} end
    return cars
end
