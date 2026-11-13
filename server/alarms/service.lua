-- Centrales de alarma (tipo alarm_panel) con teclado en la pared, estilo pinpad / lector de chapa.
-- Modos: disarmed (desarmada), armed (total) y partial (parcial: solo salta con personas no autorizadas).
-- Al armar hay retardo de salida; al entrar con la alarma armada hay retardo de entrada para
-- desarmar; si no se desarma, salta: sirena en la zona y aviso al titular y a Gruppe Sechs de servicio.
-- Todo se valida en el servidor; el cliente solo pide acciones junto al teclado o desde la tablet.
OSSecurity.AlarmService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

function OSSecurity.AlarmService.new(options)
    local config = OSSecurity.GameplayConfig.Alarm
    local util = OSSecurity.Util
    local alarms = {}
    local runtime = {}   -- deviceId -> { armedFrom, entry = { deadline, by }, sirenUntil }
    local attempts = {}  -- deviceId..':'..source -> { count, lockedUntil }

    local function record(deviceId)
        return options.inventory.alarm(deviceId) or { mode = 'disarmed', updatedAt = 0, tags = {}, events = {} }
    end
    local function save(deviceId, alarm, kind, by)
        alarm.events = alarm.events or {}
        alarm.events[#alarm.events + 1] = { kind = kind, at = options.now(), by = by }
        while #alarm.events > config.MaxEvents do table.remove(alarm.events, 1) end
        alarm.updatedAt = options.now()
        if alarm.tags and next(alarm.tags) == nil then alarm.tags = nil end
        return options.inventory.apply({ kind = 'alarm', deviceId = deviceId, alarm = alarm })
    end
    local function panelDevice(deviceId)
        if not OSSecurity.DeviceValidation.id(deviceId) then return nil, 'Central no valida.' end
        local device = options.registry.get(0, deviceId)
        if not device or device.type ~= 'alarm_panel' or device.state == 'retired' then return nil, 'Central no disponible.' end
        if device.state ~= 'active' then return nil, 'Central fuera de servicio (' .. device.state .. ').' end
        if not device.position then return nil, 'Central sin instalacion fisica.' end
        return device
    end
    local function near(source, device)
        local point = options.world(source)
        return point ~= nil and distance(point, device.position) <= config.InteractDistance
    end
    -- Dentro de la zona protegida: si el cliente informa de que la central esta en un interior, cuenta
    -- solo quien esta en ese interior (hasta 3 radios); si no hay dato, la esfera alrededor del teclado.
    local function protected(player, deviceId, device)
        local d = distance(player.position, device.position)
        local reported = player.inside and player.inside[deviceId]
        if reported ~= nil then return reported and d <= config.Radius * 3 end
        return d <= config.Radius
    end
    local function stopSiren(deviceId)
        local state = runtime[deviceId]
        if state and state.sirenUntil then options.siren(deviceId, nil) end
        if state and state.entry then options.entryStop(deviceId) end
        runtime[deviceId] = nil
    end
    local function label(device)
        local site = options.site and options.site(device.id)
        return site or (OSSecurity.Brand.DevicePrefix .. ' · ' .. device.id)
    end

    local function setMode(device, mode, by)
        local alarm = record(device.id)
        if alarm.mode == mode then return true, alarm end
        alarm.mode = mode
        local saved, err = save(device.id, alarm, mode, by)
        if not saved then return nil, err end
        stopSiren(device.id)
        if mode ~= 'disarmed' then runtime[device.id] = { armedFrom = options.now() + config.ExitDelay } end
        return true, alarm
    end
    local MESSAGES = { armed = 'Alarma armada (total). Retardo de salida: %d s.', partial = 'Alarma armada (parcial). Retardo de salida: %d s.', disarmed = 'Alarma desarmada.' }
    local ACTIONS = { arm = 'armed', partial = 'partial', disarm = 'disarmed' }

    -- Informacion para el teclado (cualquiera junto al teclado puede verlo, como en la realidad).
    function alarms.panel(source, deviceId)
        local device, err = panelDevice(deviceId)
        if not device then return nil, err end
        if not near(source, device) then return nil, 'Acercate al teclado.' end
        local alarm = record(device.id)
        local lock = attempts[device.id .. ':' .. source]
        local state = runtime[device.id]
        return { deviceId = device.id, label = label(device), mode = alarm.mode, hasPin = alarm.pin ~= nil, tags = options.tagsSupported(),
            locked = lock and lock.lockedUntil and math.max(0, lock.lockedUntil - options.now()) or 0,
            entry = state and state.entry and math.max(0, state.entry.deadline - options.now()) or nil,
            triggered = state and state.sirenUntil ~= nil or false }
    end

    -- Teclado: armar total, parcial o desarmar con el codigo.
    function alarms.keypad(source, deviceId, action, pin)
        local device, err = panelDevice(deviceId)
        if not device then return nil, err end
        if not near(source, device) then return nil, 'Acercate al teclado.' end
        local mode = ACTIONS[action]
        if not mode then return nil, 'Accion no valida.' end
        local key = device.id .. ':' .. source
        local lock = attempts[key]
        if lock and lock.lockedUntil and options.now() < lock.lockedUntil then
            return nil, ('Teclado bloqueado %d s por intentos fallidos.'):format(lock.lockedUntil - options.now())
        end
        local alarm = record(device.id)
        if not alarm.pin then return nil, 'Codigo no configurado: el titular debe crearlo desde la tablet.' end
        if type(pin) ~= 'string' or not pin:match('^%d+$') or #pin < config.PinMin or #pin > config.PinMax or not options.verify(pin, alarm.pin) then
            lock = lock or { count = 0 }
            lock.count = lock.count + 1
            attempts[key] = lock
            if lock.count >= config.MaxPinAttempts then
                lock.count, lock.lockedUntil = 0, options.now() + config.LockoutSeconds
                save(device.id, alarm, 'lockout', options.who(source))
                options.alert(device, ('Manipulacion del teclado en %s: bloqueado por intentos fallidos.'):format(label(device)), 'warning', 'tamper')
                return nil, ('Codigo incorrecto. Teclado bloqueado %d s.'):format(config.LockoutSeconds)
            end
            save(device.id, alarm, 'wrong_pin', options.who(source))
            return nil, ('Codigo incorrecto (%d/%d).'):format(lock.count, config.MaxPinAttempts)
        end
        attempts[key] = nil
        local ok, result = setMode(device, mode, options.who(source))
        if not ok then return nil, result end
        return { mode = mode, message = MESSAGES[mode]:format(config.ExitDelay) }
    end

    -- Lector de chapa: una chapa programada para esta central desarma si esta armada y arma (total) si no.
    function alarms.tag(source, deviceId)
        local device, err = panelDevice(deviceId)
        if not device then return nil, err end
        if not near(source, device) then return nil, 'Acercate al lector.' end
        local alarm = record(device.id)
        local serials = options.heldTags(source, device.id)
        local valid = false
        for _, serial in ipairs(serials or {}) do if alarm.tags and alarm.tags[serial] then valid = true end end
        if not valid then
            save(device.id, alarm, 'wrong_pin', options.who(source))
            return nil, 'Chapa no reconocida.'
        end
        local mode = alarm.mode == 'disarmed' and 'armed' or 'disarmed'
        local ok, result = setMode(device, mode, options.who(source))
        if not ok then return nil, result end
        return { mode = mode, message = MESSAGES[mode]:format(config.ExitDelay) }
    end

    -- Chapa usada desde el inventario: actua sobre el teclado mas cercano a alcance.
    function alarms.tagNearest(source)
        local snapshot = options.inventory.snapshot()
        local point = options.world(source)
        if not snapshot or not point then return nil, 'Alarma no disponible.' end
        local best, bestDistance
        for deviceId in pairs(snapshot.alarms or {}) do
            local device = options.registry.get(0, deviceId)
            if device and device.type == 'alarm_panel' and device.position then
                local d = distance(point, device.position)
                if d <= config.InteractDistance and (not bestDistance or d < bestDistance) then best, bestDistance = deviceId, d end
            end
        end
        if not best then return nil, 'Acerca la chapa a un teclado de alarma.' end
        return alarms.tag(source, best)
    end

    -- Desde la tablet Client (titular o acceso concedido): sin codigo, como la app del fabricante.
    function alarms.remote(actor, device, action)
        if device.type ~= 'alarm_panel' then return nil, 'No es una central de alarma.' end
        if not options.authorized(actor, device) then return nil, 'Sin acceso a esta alarma.' end
        if device.state ~= 'active' then return nil, 'Central fuera de servicio.' end
        local mode = ACTIONS[action]
        if not mode then return nil, 'Accion no valida.' end
        local ok, result = setMode(device, mode, actor.principal and options.whoPrincipal(actor.principal) or 'tablet')
        if not ok then return nil, result end
        return { mode = mode, message = MESSAGES[mode]:format(config.ExitDelay) }
    end
    function alarms.setPin(actor, device, pin)
        if device.type ~= 'alarm_panel' or not options.authorized(actor, device) then return nil, 'Sin acceso a esta alarma.' end
        if type(pin) ~= 'string' or not pin:match('^%d+$') or #pin < config.PinMin or #pin > config.PinMax then
            return nil, ('El codigo debe tener entre %d y %d cifras.'):format(config.PinMin, config.PinMax)
        end
        local alarm = record(device.id)
        alarm.pin = options.hash(pin)
        local saved, err = save(device.id, alarm, 'pin_set', options.whoPrincipal(actor.principal))
        if not saved then return nil, err end
        return { message = 'Codigo de la alarma actualizado.' }
    end
    function alarms.programTag(actor, device)
        if device.type ~= 'alarm_panel' or not options.authorized(actor, device) then return nil, 'Sin acceso a esta alarma.' end
        if not options.tagsSupported() then return nil, 'Las chapas requieren el inventario de personajes.' end
        local alarm = record(device.id)
        local count = 0; for _ in pairs(alarm.tags or {}) do count = count + 1 end
        if count >= config.MaxTags then return nil, 'Limite de chapas alcanzado; revoca las anteriores.' end
        local serial = options.serial()
        local ok, err = options.makeTag(actor, device, serial)
        if not ok then return nil, err end
        alarm.tags = alarm.tags or {}; alarm.tags[serial] = true
        local saved, saveError = save(device.id, alarm, 'tag_added', options.whoPrincipal(actor.principal))
        if not saved then return nil, saveError end
        return { message = 'Chapa programada (' .. serial .. ').' }
    end
    function alarms.revokeTags(actor, device)
        if device.type ~= 'alarm_panel' or not options.authorized(actor, device) then return nil, 'Sin acceso a esta alarma.' end
        local alarm = record(device.id)
        alarm.tags = nil
        local saved, err = save(device.id, alarm, 'tags_revoked', options.whoPrincipal(actor.principal))
        if not saved then return nil, err end
        return { message = 'Todas las chapas de esta alarma han sido revocadas.' }
    end
    function alarms.summary(device)
        local alarm = record(device.id)
        local state = runtime[device.id]
        local count = 0; for _ in pairs(alarm.tags or {}) do count = count + 1 end
        local events = {}
        for index = #(alarm.events or {}), math.max(1, #(alarm.events or {}) - 7), -1 do events[#events + 1] = util.copy(alarm.events[index]) end
        return { mode = alarm.mode, hasPin = alarm.pin ~= nil, tags = count, triggered = state and state.sirenUntil ~= nil or false, events = events }
    end

    -- Vigilancia periodica (1 s): entradas en zona armada, retardo de entrada y salto.
    function alarms.tick()
        local snapshot = options.inventory.snapshot()
        if not snapshot or not snapshot.alarms then return end
        local now = options.now()
        local players
        for deviceId, alarm in pairs(snapshot.alarms) do
            local state = runtime[deviceId]
            if alarm.mode == 'disarmed' then
                if state then stopSiren(deviceId) end
            else
                local device = options.registry.get(0, deviceId)
                if device and device.state == 'active' and device.position then
                    state = state or { armedFrom = now }
                    runtime[deviceId] = state
                    if state.sirenUntil and now >= state.sirenUntil then
                        options.siren(deviceId, nil); state.sirenUntil = nil; state.entry = nil; state.armedFrom = now + config.ExitDelay
                    elseif not state.sirenUntil and now >= state.armedFrom then
                        players = players or options.players()
                        local intruders = {}
                        for _, player in ipairs(players) do
                            if player.bucket == (device.bucket or 0) and protected(player, deviceId, device)
                                and not (alarm.mode == 'partial' and options.authorized(options.actorOf(player.source), device)) then
                                intruders[#intruders + 1] = player.source
                            end
                        end
                        if #intruders > 0 and not state.entry then
                            state.entry = { deadline = now + config.EntryDelay }
                            for _, source in ipairs(intruders) do options.entry(source, device, config.EntryDelay) end
                        elseif state.entry and now >= state.entry.deadline then
                            state.entry, state.sirenUntil = nil, now + config.SirenSeconds
                            options.entryStop(deviceId)
                            local current = options.inventory.alarm(deviceId)
                            if current then save(deviceId, current, 'triggered') end
                            options.siren(deviceId, device)
                            options.alert(device, ('¡Salto de alarma en %s!'):format(label(device)), 'error', 'alarm')
                        end
                    end
                end
            end
        end
    end
    function alarms.forgetDevice(deviceId) stopSiren(deviceId) end
    function alarms.clear() for deviceId in pairs(runtime) do stopSiren(deviceId) end; runtime, attempts = {}, {} end
    function alarms.forget(source)
        for key in pairs(attempts) do if key:match(':' .. source .. '$') then attempts[key] = nil end end
    end
    return alarms
end
