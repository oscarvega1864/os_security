local util = OSSecurity.Util
-- Pantalla de inicio de las tablets: resumen con lo urgente, buscador y puntos del mapa.
-- Solo reutiliza listados que ya filtran por perfil (dispositivos accesibles, ordenes y avisos del actor),
-- asi que no da acceso a nada que la tablet no mostrase ya en su seccion.
OSSecurity.TabletHome = {}

local GOOD = { active = true, installed = true }
local BAD = { fault = true, maintenance = true }
local ORDER_ACTIVE = { open = true, accepted = true, billed = true }
local CALL_ACTIVE = { open = true, assigned = true }
local LIMITS = { attention = 8, points = 200, results = 25 }

function OSSecurity.TabletHome.new(options)
    local home = {}
    local function point(position)
        if type(position) ~= 'table' or type(position.x) ~= 'number' or type(position.y) ~= 'number' then return nil end
        return { x = util.round(position.x, 1), y = util.round(position.y, 1) }
    end
    local function devices(actor)
        local snapshot = options.inventory.snapshot()
        local list, err = options.service.accessible(actor, function(device) return device.state ~= 'retired' end)
        if not list then return nil, err end
        table.sort(list, function(a, b) return a.id < b.id end)
        local briefs = {}
        for _, device in ipairs(list) do briefs[#briefs + 1] = options.service.brief(device, snapshot) end
        return briefs
    end
    local function orders(actor)
        if not options.orders then return {} end
        local data = actor.kind == 'client' and options.orders.clientList(actor) or options.orders.staffList(actor)
        return data and data.items or {}
    end
    local function calls(actor)
        if not options.dispatch then return {} end
        local data = actor.kind == 'client' and options.dispatch.clientList(actor) or options.dispatch.staffList(actor)
        return data and data.items or {}
    end
    local function deviceReason(device)
        if device.triggered then return 'triggered' end
        if BAD[device.state] then return device.state end
        if type(device.health) == 'number' and device.health < 50 then return 'worn' end
        return nil
    end

    function home.summary(actor)
        local list, err = devices(actor)
        if not list then return nil, err end
        local counts = { devices = #list, ok = 0, attention = 0, live = 0, armed = 0, triggered = 0,
            orders = 0, ordersMine = 0, ordersOpen = 0, calls = 0, callsMine = 0, cars = 0, carsAlarm = 0 }
        local attention, points = {}, {}
        local function add(entry) if #points < LIMITS.points and entry.x then points[#points + 1] = entry end end
        for _, device in ipairs(list) do
            if GOOD[device.state] then counts.ok = counts.ok + 1 end
            if device.live then counts.live = counts.live + 1 end
            if device.alarmMode == 'armed' or device.alarmMode == 'partial' then counts.armed = counts.armed + 1 end
            if device.triggered then counts.triggered = counts.triggered + 1 end
            local reason = deviceReason(device)
            if reason then
                counts.attention = counts.attention + 1
                if #attention < LIMITS.attention then
                    attention[#attention + 1] = { kind = 'device', id = device.id, title = device.displayId, subtitle = device.site, reason = reason,
                        type = device.type, state = device.state }
                end
            end
            local at = point(device.position)
            if at then add({ kind = 'device', id = device.id, x = at.x, y = at.y, label = device.displayId, subtitle = device.site,
                type = device.type, state = reason or device.state }) end
        end
        for _, order in ipairs(orders(actor)) do
            if ORDER_ACTIVE[order.status] then
                counts.orders = counts.orders + 1
                if order.status == 'open' then counts.ordersOpen = counts.ordersOpen + 1 end
                if order.mine then counts.ordersMine = counts.ordersMine + 1 end
                local at = point(order.position)
                if at then add({ kind = 'order', id = order.id, x = at.x, y = at.y, label = order.id, subtitle = order.place, state = order.status }) end
            end
        end
        for _, call in ipairs(calls(actor)) do
            if CALL_ACTIVE[call.status] then
                counts.calls = counts.calls + 1
                if call.mine then counts.callsMine = counts.callsMine + 1 end
                if #attention < LIMITS.attention then
                    attention[#attention + 1] = { kind = 'call', id = call.id, title = call.id, subtitle = call.place, reason = call.kind, state = call.status }
                end
                local at = point(call.position)
                if at then add({ kind = 'call', id = call.id, x = at.x, y = at.y, label = call.id, subtitle = call.place, state = call.kind }) end
            end
        end
        for _, car in ipairs(options.service.cars(actor)) do
            counts.cars = counts.cars + 1
            if car.sounding then
                counts.carsAlarm = counts.carsAlarm + 1
                if #attention < LIMITS.attention then
                    attention[#attention + 1] = { kind = 'car', id = car.plate, title = car.plate, reason = 'sounding', state = 'sounding' }
                end
            end
            local at = point(car.position)
            if at then add({ kind = 'car', id = car.plate, x = at.x, y = at.y, label = car.plate, state = car.sounding and 'sounding' or 'parked' }) end
        end
        return { counts = counts, attention = attention, points = points }
    end

    local function matches(query, ...)
        for index = 1, select('#', ...) do
            local value = select(index, ...)
            if type(value) == 'string' and value:lower():find(query, 1, true) then return true end
        end
        return false
    end
    function home.search(actor, args)
        if not util.object(args, { query = true }) or type(args.query) ~= 'string' then return nil, 'Busqueda no valida.' end
        local query = args.query:lower():gsub('^%s+', ''):gsub('%s+$', '')
        if #query < 2 or #query > 40 then return nil, 'Escribe entre 2 y 40 caracteres.' end
        local list, err = devices(actor)
        if not list then return nil, err end
        local Text = OSSecurity.Brand.Text
        local results = {}
        local function push(entry) if #results < LIMITS.results then results[#results + 1] = entry end end
        for _, device in ipairs(list) do
            local typeLabel = Text.deviceTypes[device.type] or device.type
            if matches(query, device.id, device.displayId, device.model, device.site, typeLabel) then
                push({ kind = 'device', id = device.id, title = device.displayId, subtitle = device.site, type = device.type,
                    state = device.state, position = point(device.position) })
            end
        end
        local orderKinds = Text.orders and Text.orders.kinds or {}
        for _, order in ipairs(orders(actor)) do
            if matches(query, order.id, order.place, order.clientName, order.techName, order.note, orderKinds[order.kind]) then
                push({ kind = 'order', id = order.id, title = order.id, subtitle = order.place, state = order.status, position = point(order.position) })
            end
        end
        local callKinds = Text.dispatch and Text.dispatch.kinds or {}
        for _, call in ipairs(calls(actor)) do
            if matches(query, call.id, call.place, call.clientName, call.techName, call.note, callKinds[call.kind]) then
                push({ kind = 'call', id = call.id, title = call.id, subtitle = call.place, state = call.status, position = point(call.position) })
            end
        end
        for _, car in ipairs(options.service.cars(actor)) do
            if matches(query, car.plate) then push({ kind = 'car', id = car.plate, title = car.plate, state = car.sounding and 'sounding' or 'parked', position = point(car.position) }) end
        end
        return { query = query, items = results }
    end
    return home
end
