-- Central de operaciones Gruppe Sechs y Emergencias.
-- Avisos: salto de alarma, manipulacion de un teclado (bloqueo por codigos fallidos) y boton de panico del
-- cliente (G6 Client > Emergencias). Cada aviso queda guardado y llega al personal G6 de servicio.
-- Operations > Central de operaciones: el tecnico se asigna un aviso (GPS), el supervisor lo asigna a un
-- companero de servicio, y se cierra con una nota de resolucion que le llega al cliente. Un salto repetido de
-- la misma central con su aviso todavia abierto suma al mismo aviso en lugar de crear otro.
-- Todo se valida aqui; identidad, posicion, nombres y avisos llegan por 'options'.
local util = OSSecurity.Util
OSSecurity.DispatchService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
local PRIORITY = { panic = 1, alarm = 2, tamper = 3 }
local ACTIVE = { open = true, assigned = true }

function OSSecurity.DispatchService.new(options)
    local config = OSSecurity.GameplayConfig.Dispatch
    local T = OSSecurity.Brand.Text.dispatch
    local service = {}
    local lastPanic = {}

    local function all() return options.inventory.calls() or {} end
    local function save(call)
        call.updatedAt = options.now()
        return options.inventory.apply({ kind = 'call', callId = call.id, call = call })
    end
    local function clean(text, size)
        if type(text) ~= 'string' then return nil end
        text = text:gsub('[%c<>]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, size)
        return text ~= '' and text or nil
    end
    local function name(source) return clean(options.playerName and options.playerName(source), 64) or ('Jugador ' .. tostring(source)) end
    local function nextId(list)
        local highest = 0
        for id in pairs(list) do highest = math.max(highest, tonumber(id:sub(4)) or 0) end
        return ('av_%06d'):format(highest + 1)
    end
    local function point(position) return { x = util.round(position.x, 2), y = util.round(position.y, 2), z = util.round(position.z, 2) } end
    local function sourceOf(principal)
        if not principal then return nil end
        for _, player in ipairs(options.players and options.players() or {}) do
            if options.identity.resolve(player) == principal then return player end
        end
    end
    local function notify(source, text, kind, position) if source and options.notify then options.notify(source, text, kind or 'info', position) end end
    local function staff(except)
        local list = {}
        for _, player in ipairs(options.players and options.players() or {}) do
            if player ~= except and options.isStaff(player) then list[#list + 1] = player end
        end
        return list
    end
    local function broadcast(call, text, kind)
        for _, player in ipairs(staff()) do notify(player, text, kind, call.position) end
    end
    local function kindLabel(kind) return T.kinds[kind] or kind end
    -- Limpieza: avisos cerrados mas antiguos que KeepDays.
    local function prune(list)
        local limit = options.now() - config.KeepDays * 86400
        for id, call in pairs(list) do
            if not ACTIVE[call.status] and call.updatedAt < limit then
                if options.inventory.apply({ kind = 'call', callId = id }) then list[id] = nil end
            end
        end
    end
    local function create(list, fields)
        prune(list)
        local now = options.now()
        local call = { id = nextId(list), status = 'open', count = 1, createdAt = now, updatedAt = now }
        for key, value in pairs(fields) do call[key] = value end
        local saved, err = save(call)
        if not saved then return nil, err end
        return call
    end
    local function public(call, viewer, here)
        return { id = call.id, kind = call.kind, status = call.status, priority = PRIORITY[call.kind], place = call.place, note = call.note,
            resolution = call.resolution, clientName = call.clientName, techName = call.techName, count = call.count,
            createdAt = call.createdAt, updatedAt = call.updatedAt, position = util.copy(call.position),
            mine = viewer ~= nil and call.technician == viewer or nil,
            distance = here and util.round(distance(here, call.position), 0) or nil }
    end
    local function sorted(list, accept, viewer, here)
        local result = {}
        for _, call in pairs(list) do if accept(call) then result[#result + 1] = public(call, viewer, here) end end
        table.sort(result, function(a, b)
            local activeA, activeB = ACTIVE[a.status] == true, ACTIVE[b.status] == true
            if activeA ~= activeB then return activeA end
            if activeA and a.priority ~= b.priority then return a.priority < b.priority end
            if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
            return a.id > b.id
        end)
        return result
    end
    local function getCall(id)
        if not OSSecurity.InventoryState.callId(id) then return nil end
        return all()[id]
    end

    -- Avisos automaticos (alarmas) ----------------------------------------------------------------------
    -- kind: 'alarm' (salto) o 'tamper' (teclado bloqueado). owner: identidad del titular de la central.
    function service.raise(device, kind, owner, place)
        if not PRIORITY[kind] or kind == 'panic' or not device or not device.position then return nil end
        local list = all()
        for _, call in pairs(list) do
            if call.deviceId == device.id and call.kind == kind and ACTIVE[call.status] then
                call.count = math.min(config.MaxRepeat, call.count + 1)
                if save(call) then broadcast(call, T.repeated:format(kindLabel(kind), call.place or device.id, call.count), 'warning') end
                return call
            end
        end
        local call = create(list, { kind = kind, client = owner, deviceId = device.id, place = clean(place, 80) or device.id, position = point(device.position) })
        if call then
            broadcast(call, T.newCall:format(kindLabel(kind), call.place), kind == 'alarm' and 'error' or 'warning')
            options.audit('call_raised', 0, device.id)
        end
        return call
    end

    -- Cliente: G6 Client > Emergencias ----------------------------------------------------------------
    local function ownedSites(source)
        local alias = options.alias and options.alias(source)
        local result = {}
        if not alias or not options.sites or not options.sites.owned then return result end
        for _, site in ipairs(options.sites.owned()) do
            if site.owner == alias then
                result[#result + 1] = { value = ('site:%s:%d'):format(site.kind, site.id), label = options.sites.label({ kind = site.kind, id = site.id }),
                    position = util.copy(site.position) }
            end
        end
        return result
    end
    local function activePanic(principal)
        for _, call in pairs(all()) do
            if call.kind == 'panic' and call.client == principal and ACTIVE[call.status] then return call end
        end
    end
    function service.clientList(actor)
        local places = { { value = 'here', label = T.here } }
        for _, site in ipairs(ownedSites(actor.source)) do places[#places + 1] = { value = site.value, label = site.label } end
        local wait = lastPanic[actor.principal] and math.max(0, lastPanic[actor.principal] + config.PanicCooldown - options.now()) or 0
        return { items = sorted(all(), function(call) return call.client == actor.principal end), places = places,
            noteLength = config.NoteLength, cooldown = wait, active = activePanic(actor.principal) ~= nil }
    end
    function service.panic(actor, args)
        if not util.object(args, { place = true, note = true }) or type(args.place) ~= 'string' then return nil, 'Elige donde estas.' end
        if activePanic(actor.principal) then return nil, 'Ya tienes un aviso de emergencia en curso.' end
        local now = options.now()
        if lastPanic[actor.principal] and now - lastPanic[actor.principal] < config.PanicCooldown then
            return nil, ('Espera %d s antes de otro aviso.'):format(lastPanic[actor.principal] + config.PanicCooldown - now)
        end
        local position, place
        if args.place == 'here' then
            position = options.world(actor.source)
            if not position then return nil, 'Posicion no disponible.' end
            place = T.clientPlace
        else
            for _, owned in ipairs(ownedSites(actor.source)) do
                if owned.value == args.place then position, place = owned.position, owned.label end
            end
            if not position then return nil, 'Ese lugar no es tuyo.' end
        end
        local call, err = create(all(), { kind = 'panic', client = actor.principal, clientName = name(actor.source), place = clean(place, 80),
            note = clean(args.note, config.NoteLength), position = point(position) })
        if not call then return nil, err end
        lastPanic[actor.principal] = now
        local alerted = #staff(actor.source)
        broadcast(call, T.newPanic:format(call.clientName, call.place), 'error')
        options.audit('panic', actor.source)
        return { message = alerted > 0 and T.panicSent:format(alerted) or T.panicNobody, id = call.id }
    end
    function service.cancel(actor, args)
        if not util.object(args, { callId = true }) then return nil, 'Aviso no valido.' end
        local call = getCall(args.callId)
        if not call or call.client ~= actor.principal or call.kind ~= 'panic' then return nil, 'Aviso no encontrado.' end
        if not ACTIVE[call.status] then return nil, 'Este aviso ya esta cerrado.' end
        local technician = call.technician
        call.status, call.resolution = 'cancelled', T.falseAlarm
        local saved, err = save(call)
        if not saved then return nil, err end
        if technician then notify(sourceOf(technician), T.cancelledTech:format(call.id), 'info') end
        return { message = T.cancelled }
    end

    -- Operations > Central de operaciones -------------------------------------------------------------
    local function profile(actor) return OSSecurity.GameplayConfig.Profiles[actor.role] or {} end
    local function canTake(actor) return actor.kind == 'operations' and profile(actor).install == true end
    local function canAssign(actor) return actor.kind == 'operations' and (actor.role == 'supervisor' or actor.role == 'admin') end
    function service.staffList(actor)
        local here = options.world(actor.source)
        local recent = options.now() - 86400
        local items = sorted(all(), function(call)
            return ACTIVE[call.status] or (call.technician == actor.principal and call.updatedAt >= recent)
                or (canAssign(actor) and call.updatedAt >= recent)
        end, actor.principal, here)
        local crew = {}
        if canAssign(actor) then
            for _, player in ipairs(staff()) do crew[#crew + 1] = { id = player, name = name(player), self = player == actor.source or nil } end
        end
        return { items = items, canTake = canTake(actor), canAssign = canAssign(actor), crew = crew, noteLength = config.NoteLength }
    end
    local function active(args, extra)
        local fields = { callId = true }
        for key in pairs(extra or {}) do fields[key] = true end
        if not util.object(args, fields) then return nil, 'Aviso no valido.' end
        local call = getCall(args.callId)
        if not call then return nil, 'Aviso no encontrado.' end
        if not ACTIVE[call.status] then return nil, 'Este aviso ya esta cerrado.' end
        return call
    end
    local function give(call, principal, techName)
        call.status, call.technician, call.techName = 'assigned', principal, techName
        local saved, err = save(call)
        if not saved then return nil, err end
        notify(sourceOf(call.client), T.onTheWay:format(techName), 'success')
        return true
    end
    function service.take(actor, args)
        if not canTake(actor) then return nil, 'Tu perfil no atiende avisos en la calle.' end
        local call, err = active(args)
        if not call then return nil, err end
        if call.status == 'assigned' and call.technician ~= actor.principal then return nil, 'Ese aviso ya lo atiende ' .. (call.techName or 'otro tecnico') .. '.' end
        if call.client == actor.principal then return nil, 'No puedes atender tu propio aviso.' end
        local ok, saveError = give(call, actor.principal, name(actor.source))
        if not ok then return nil, saveError end
        options.audit('call_taken', actor.source, call.deviceId)
        return { message = T.taken:format(call.id), position = util.copy(call.position) }
    end
    function service.assign(actor, args)
        if not canAssign(actor) then return nil, 'Solo un supervisor asigna avisos.' end
        local call, err = active(args, { target = true })
        if not call then return nil, err end
        local target = args.target
        if not util.integer(target, 1, 2147483647) or not options.isStaff(target) then return nil, 'Ese companero no esta de servicio.' end
        local principal = options.identity.resolve(target)
        if not principal then return nil, 'Ese companero no esta disponible.' end
        if call.client == principal then return nil, 'No se puede asignar el aviso a su propio cliente.' end
        local techName = name(target)
        local ok, saveError = give(call, principal, techName)
        if not ok then return nil, saveError end
        if target ~= actor.source then notify(target, T.assignedYou:format(kindLabel(call.kind), call.place or call.id, name(actor.source)), 'warning', call.position) end
        options.audit('call_assigned', actor.source, call.deviceId)
        return { message = T.assigned:format(call.id, techName), position = util.copy(call.position) }
    end
    function service.release(actor, args)
        local call, err = active(args)
        if not call then return nil, err end
        if call.status ~= 'assigned' or (call.technician ~= actor.principal and not canAssign(actor)) then return nil, 'Este aviso no es tuyo.' end
        call.status, call.technician, call.techName = 'open', nil, nil
        local saved, saveError = save(call)
        if not saved then return nil, saveError end
        return { message = T.released }
    end
    function service.resolve(actor, args)
        local call, err = active(args, { note = true })
        if not call then return nil, err end
        if call.technician ~= actor.principal and not canAssign(actor) then return nil, 'Asignate el aviso antes de cerrarlo.' end
        local note = clean(args.note, config.NoteLength)
        if not note then return nil, 'Escribe que ha pasado para cerrar el aviso.' end
        call.status, call.resolution = 'resolved', note
        if not call.technician then call.technician, call.techName = actor.principal, name(actor.source) end
        local saved, saveError = save(call)
        if not saved then return nil, saveError end
        notify(sourceOf(call.client), T.resolvedClient:format(kindLabel(call.kind), note), 'info')
        options.audit('call_resolved', actor.source, call.deviceId)
        return { message = T.resolved:format(call.id) }
    end
    function service.forget(source) end
    return service
end
