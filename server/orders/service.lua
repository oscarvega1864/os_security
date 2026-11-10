-- Ordenes de trabajo Gruppe Sechs.
-- Cliente (G6 Client > Solicitudes de mantenimiento): pide una instalacion, reparacion, cambio de bombin...
-- donde esta o en una de sus propiedades; puede cancelarla mientras no este facturada y paga desde la tablet.
-- Tecnico (G6 Operations > Ordenes de trabajo): ve las abiertas, acepta una (queda a su nombre), la marca en
-- el GPS, hace el trabajo con las herramientas que ya existen y la factura con un precio. Al pagar el
-- cliente, el tecnico cobra TechShare del precio (al momento o la proxima vez que abra la tablet).
-- Todo se valida aqui; la identidad, el dinero y la posicion llegan por 'options'.
local util = OSSecurity.Util
OSSecurity.OrderService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

function OSSecurity.OrderService.new(options)
    local config = OSSecurity.GameplayConfig.Orders
    local service = {}
    local lastCreate = {}

    local function all() return options.inventory.orders() or {} end
    local function save(order)
        order.updatedAt = options.now()
        return options.inventory.apply({ kind = 'order', orderId = order.id, order = order })
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
        return ('ot_%06d'):format(highest + 1)
    end
    -- Jugador conectado con esa identidad (para avisar o pagar).
    local function sourceOf(principal)
        for _, player in ipairs(options.players and options.players() or {}) do
            if options.identity.resolve(player) == principal then return player end
        end
    end
    local function notify(source, text, kind, position) if source and options.notify then options.notify(source, text, kind or 'info', position) end end
    local function kindLabel(kind) return OSSecurity.Brand.Text.orders.kinds[kind] or kind end
    -- Limpieza: ordenes cerradas mas antiguas que KeepDays.
    local function prune(list)
        local limit = options.now() - config.KeepDays * 86400
        for id, order in pairs(list) do
            if (order.status == 'paid' and order.payout ~= 'pending' or order.status == 'cancelled') and order.updatedAt < limit then
                if options.inventory.apply({ kind = 'order', orderId = id }) then list[id] = nil end
            end
        end
    end
    local function public(order, viewer)
        return { id = order.id, kind = order.kind, status = order.status, clientName = order.clientName, techName = order.techName,
            note = order.note, place = order.place, price = order.price, createdAt = order.createdAt, updatedAt = order.updatedAt,
            position = util.copy(order.position), mine = viewer ~= nil and order.technician == viewer or nil,
            payout = order.technician == viewer and order.payout or nil,
            share = order.price and math.floor(order.price * config.TechShare) or nil }
    end
    local function sorted(list, accept, viewer)
        local result = {}
        for _, order in pairs(list) do if accept(order) then result[#result + 1] = public(order, viewer) end end
        table.sort(result, function(a, b) if a.createdAt ~= b.createdAt then return a.createdAt > b.createdAt end; return a.id > b.id end)
        return result
    end
    -- Propiedades y negocios del personaje activo del cliente (lugares para la solicitud).
    local function ownedSites(source)
        local alias = options.alias and options.alias(source)
        local result = {}
        if not alias or not options.sites or not options.sites.owned then return result end
        for _, site in ipairs(options.sites.owned()) do
            if site.owner == alias then
                result[#result + 1] = { value = ('site:%s:%d'):format(site.kind, site.id), label = options.sites.label({ kind = site.kind, id = site.id }),
                    site = { kind = site.kind, id = site.id }, position = util.copy(site.position) }
            end
        end
        return result
    end
    -- Pago pendiente al tecnico: se liquida en cuanto esta conectado.
    local function settle(order, source)
        if order.status ~= 'paid' or order.payout ~= 'pending' then return end
        source = source or sourceOf(order.technician)
        if not source then return end
        local share = math.floor(order.price * config.TechShare)
        if share > 0 and options.money.refund(source, share, config.PayAccount, order.id) ~= true then return end
        order.payout = 'done'
        if save(order) then notify(source, OSSecurity.Brand.Text.orders.paidTech:format(share, order.id), 'success') end
    end

    -- Cliente ----------------------------------------------------------------------------------------
    function service.clientList(actor)
        local list = all()
        local places = { { value = 'here', label = OSSecurity.Brand.Text.orders.here } }
        for _, site in ipairs(ownedSites(actor.source)) do places[#places + 1] = { value = site.value, label = site.label } end
        local kinds = {}
        for kind in pairs(OSSecurity.InventoryState.OrderKinds) do kinds[#kinds + 1] = { value = kind, label = kindLabel(kind) } end
        table.sort(kinds, function(a, b) return a.label < b.label end)
        return { items = sorted(list, function(order) return order.client == actor.principal end), places = places, kinds = kinds,
            maxOpen = config.MaxOpenPerClient, noteLength = config.NoteLength, account = config.PayAccount }
    end
    function service.create(actor, args)
        if not util.object(args, { kind = true, note = true, place = true }) or not OSSecurity.InventoryState.OrderKinds[args.kind] then
            return nil, 'Elige el tipo de trabajo.'
        end
        local now = options.now()
        if lastCreate[actor.principal] and now - lastCreate[actor.principal] < 10 then return nil, 'Espera un momento antes de otra solicitud.' end
        local note = clean(args.note, config.NoteLength)
        if not note then return nil, 'Describe brevemente lo que necesitas.' end
        local list = all()
        local open = 0
        for _, order in pairs(list) do
            if order.client == actor.principal and (order.status == 'open' or order.status == 'accepted' or order.status == 'billed') then open = open + 1 end
        end
        if open >= config.MaxOpenPerClient then return nil, ('Ya tienes %d solicitudes en curso.'):format(open) end
        local position, place, site
        if args.place == 'here' then
            local here = options.world(actor.source)
            if not here then return nil, 'Posicion no disponible.' end
            position, place = here, OSSecurity.Brand.Text.orders.clientPlace
        else
            for _, owned in ipairs(ownedSites(actor.source)) do
                if owned.value == args.place then position, place, site = owned.position, owned.label, owned.site end
            end
            if not position then return nil, 'Ese lugar no es tuyo.' end
        end
        prune(list)
        local order = { id = nextId(list), kind = args.kind, status = 'open', client = actor.principal, clientName = name(actor.source),
            note = note, place = clean(place, 80), position = { x = util.round(position.x, 2), y = util.round(position.y, 2), z = util.round(position.z, 2) },
            site = site, createdAt = now, updatedAt = now }
        local saved, err = save(order)
        if not saved then return nil, err end
        lastCreate[actor.principal] = now
        for _, player in ipairs(options.players and options.players() or {}) do
            if player ~= actor.source and options.isStaff(player) then
                notify(player, OSSecurity.Brand.Text.orders.newOrder:format(kindLabel(order.kind), order.place), 'info', order.position)
            end
        end
        options.audit('order_created', actor.source)
        return { message = OSSecurity.Brand.Text.orders.created:format(order.id), id = order.id }
    end
    local function getOrder(id)
        if not OSSecurity.InventoryState.orderId(id) then return nil end
        return all()[id]
    end
    local function ownOrder(actor, id)
        local order = getOrder(id)
        if not order or order.client ~= actor.principal then return nil, 'Solicitud no encontrada.' end
        return order
    end
    function service.cancel(actor, args)
        if not util.object(args, { orderId = true }) then return nil, 'Solicitud no valida.' end
        local order, err = ownOrder(actor, args.orderId)
        if not order then return nil, err end
        if order.status ~= 'open' and order.status ~= 'accepted' then return nil, 'Esta solicitud ya no se puede cancelar.' end
        local technician = order.technician
        order.status = 'cancelled'
        local saved, saveError = save(order)
        if not saved then return nil, saveError end
        if technician then notify(sourceOf(technician), OSSecurity.Brand.Text.orders.cancelledTech:format(order.id), 'warning') end
        return { message = OSSecurity.Brand.Text.orders.cancelled }
    end
    function service.pay(actor, args)
        if not util.object(args, { orderId = true }) then return nil, 'Solicitud no valida.' end
        local order, err = ownOrder(actor, args.orderId)
        if not order then return nil, err end
        if order.status ~= 'billed' then return nil, 'No hay nada que pagar en esta solicitud.' end
        if not options.money.available() then return nil, 'Pago no disponible en este servidor.' end
        local charged, why = options.money.charge(actor.source, order.price, config.PayAccount, order.id)
        if not charged then return nil, why == 'insufficient_funds' and 'Saldo insuficiente en el banco.' or 'Pago rechazado.' end
        order.status, order.payout = 'paid', 'pending'
        local saved, saveError = save(order)
        if not saved then
            options.money.refund(actor.source, order.price, config.PayAccount, order.id)
            return nil, saveError
        end
        settle(order)
        options.audit('order_paid', actor.source)
        return { message = OSSecurity.Brand.Text.orders.paid:format(order.price) }
    end

    -- Tecnico ----------------------------------------------------------------------------------------
    local function canWork(actor) return actor.kind == 'operations' and OSSecurity.GameplayConfig.Profiles[actor.role] and OSSecurity.GameplayConfig.Profiles[actor.role].install == true end
    function service.staffList(actor)
        local list = all()
        for _, order in pairs(list) do if order.technician == actor.principal then settle(order, actor.source) end end
        list = all()
        local here = options.world(actor.source)
        local items = sorted(list, function(order)
            return order.status == 'open' or (order.technician == actor.principal and order.status ~= 'cancelled')
                or (actor.role == 'admin' and (order.status == 'accepted' or order.status == 'billed'))
        end, actor.principal)
        for _, item in ipairs(items) do item.distance = here and util.round(distance(here, item.position), 0) or nil end
        return { items = items, canWork = canWork(actor) == true, share = config.TechShare, maxPrice = config.MaxPrice }
    end
    local function workable(actor, args, extra)
        if not canWork(actor) then return nil, 'Tu perfil no puede atender ordenes de trabajo.' end
        local fields = { orderId = true }
        for key in pairs(extra or {}) do fields[key] = true end
        if not util.object(args, fields) then return nil, 'Orden no valida.' end
        local order = getOrder(args.orderId)
        if not order then return nil, 'Orden no encontrada.' end
        return order
    end
    function service.accept(actor, args)
        local order, err = workable(actor, args)
        if not order then return nil, err end
        if order.status ~= 'open' then return nil, 'Otro tecnico ya ha aceptado esta orden.' end
        if order.client == actor.principal then return nil, 'No puedes atender tu propia solicitud.' end
        order.status, order.technician, order.techName = 'accepted', actor.principal, name(actor.source)
        local saved, saveError = save(order)
        if not saved then return nil, saveError end
        notify(sourceOf(order.client), OSSecurity.Brand.Text.orders.acceptedClient:format(order.id, order.techName), 'success')
        options.audit('order_accepted', actor.source)
        return { message = OSSecurity.Brand.Text.orders.accepted:format(order.id), position = util.copy(order.position) }
    end
    function service.release(actor, args)
        local order, err = workable(actor, args)
        if not order then return nil, err end
        if order.status ~= 'accepted' or order.technician ~= actor.principal then return nil, 'Esta orden no es tuya.' end
        order.status, order.technician, order.techName = 'open', nil, nil
        local saved, saveError = save(order)
        if not saved then return nil, saveError end
        return { message = OSSecurity.Brand.Text.orders.released }
    end
    function service.bill(actor, args)
        local order, err = workable(actor, args, { price = true })
        if not order then return nil, err end
        if order.status ~= 'accepted' or order.technician ~= actor.principal then return nil, 'Esta orden no es tuya.' end
        if not util.integer(args.price, 1, config.MaxPrice) then return nil, ('El precio debe estar entre 1 y %d.'):format(config.MaxPrice) end
        order.status, order.price = 'billed', args.price
        local saved, saveError = save(order)
        if not saved then return nil, saveError end
        notify(sourceOf(order.client), OSSecurity.Brand.Text.orders.billedClient:format(order.id, order.price), 'info')
        options.audit('order_billed', actor.source)
        return { message = OSSecurity.Brand.Text.orders.billed:format(order.id, math.floor(order.price * config.TechShare)) }
    end
    function service.drop(source) end
    return service
end
