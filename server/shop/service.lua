-- Tienda Gruppe Sechs: catalogo y compra validados en el servidor.
-- Compra: junto al mostrador, productos del catalogo (los 'staff' solo para personal G6), cantidades
-- acotadas y total calculado aqui. Se cobra primero; despues se entrega cada producto con un
-- identificador de operacion propio. Lo que no se pueda entregar (inventario lleno, proveedor caido)
-- se devuelve al personaje. Logica pura: dinero, objetos y posicion llegan por 'options'.
local util = OSSecurity.Util
OSSecurity.ShopService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

function OSSecurity.ShopService.new(options)
    local config = options.config or OSSecurity.ShopConfig
    local shop = {}
    local orders, lastBuy = 0, {}
    local products = {}
    for _, product in ipairs(config.Products) do products[product.item] = product end
    local accounts = {}
    for _, account in ipairs(config.Accounts) do accounts[account] = true end

    -- Mostrador cercano (mismo bucket del mundo abierto).
    local function counter(source)
        local point, bucket = options.world(source)
        if not point or bucket ~= 0 then return nil end
        for _, location in ipairs(config.Locations) do
            if distance(point, location) <= config.Distance then return location end
        end
        return nil
    end
    local function price(product) return math.floor(product.price) end

    function shop.catalog(source)
        local location = counter(source)
        if not location then return nil, 'Acercate al mostrador de Gruppe Sechs.' end
        if not options.money.available() then return nil, 'Pago no disponible en este servidor.' end
        local staff = options.isStaff(source) == true
        local list = {}
        for _, product in ipairs(config.Products) do
            local definition = OSSecurity.ItemCatalog[product.item]
            if definition then
                list[#list + 1] = { item = product.item, name = definition.name, category = definition.category, price = price(product),
                    staff = product.audience == 'staff', allowed = product.audience ~= 'staff' or staff }
            end
        end
        return { location = location.label, products = list, staff = staff, balance = options.money.balance(source),
            accounts = util.copy(config.Accounts), maxQuantity = config.MaxQuantity }
    end

    -- cart: { { item = 'os_lock_kit', amount = 2 }, ... }; account: 'bank' | 'cash'.
    function shop.buy(source, cart, account)
        local now = options.now()
        if lastBuy[source] and now - lastBuy[source] < 2 then return nil, 'Espera un momento antes de otra compra.' end
        if not counter(source) then return nil, 'Acercate al mostrador de Gruppe Sechs.' end
        if not options.money.available() then return nil, 'Pago no disponible en este servidor.' end
        if type(account) ~= 'string' or not accounts[account] then return nil, 'Forma de pago no valida.' end
        if type(cart) ~= 'table' or #cart == 0 or #cart > config.MaxLines then return nil, 'Carrito no valido.' end
        local staff = options.isStaff(source) == true
        local lines, seen, total = {}, {}, 0
        for _, entry in ipairs(cart) do
            if not util.object(entry, { item = true, amount = true }) then return nil, 'Carrito no valido.' end
            local product = type(entry.item) == 'string' and products[entry.item]
            if not product or not OSSecurity.ItemCatalog[entry.item] or seen[entry.item] then return nil, 'Producto no disponible.' end
            if not util.integer(entry.amount, 1, config.MaxQuantity) then return nil, ('Maximo %d unidades por producto.'):format(config.MaxQuantity) end
            if product.audience == 'staff' and not staff then return nil, 'Ese producto es solo para personal de Gruppe Sechs de servicio.' end
            seen[entry.item] = true
            lines[#lines + 1] = { item = entry.item, amount = entry.amount, cost = price(product) * entry.amount }
            total = total + price(product) * entry.amount
        end
        -- Destino de los objetos: personaje activo (proveedor externo) o cuenta (registro local).
        local principal = options.identity.resolve(source)
        if not principal then return nil, 'Identidad no disponible.' end
        local holder
        if options.holdings.external() then
            local resolved, err = options.holdings.holder(source)
            if not resolved then return nil, err end
            holder = resolved
        end
        lastBuy[source] = now
        orders = orders + 1
        local orderId = ('g6shop_%d_%d_%d'):format(now, source, orders)
        local charged, chargeError = options.money.charge(source, total, account, orderId)
        if not charged then
            return nil, chargeError == 'insufficient_funds' and 'Saldo insuficiente.' or ('Pago rechazado (%s).'):format(tostring(chargeError or 'error'))
        end
        local delivered, refund, missing = {}, 0, {}
        for _, line in ipairs(lines) do
            local ok, err
            if holder then ok, err = options.holdings.grant(holder, line.item, line.amount, orderId .. ':' .. line.item)
            else ok, err = options.inventory.apply({ kind = 'grant', principal = principal, item = line.item, amount = line.amount }) end
            if ok then delivered[#delivered + 1] = { item = line.item, amount = line.amount }
            else
                refund = refund + line.cost
                missing[#missing + 1] = OSSecurity.ItemCatalog[line.item].name
                if options.log then options.log(('Tienda G6 %s: %s x%d no entregado (%s).'):format(orderId, line.item, line.amount, tostring(err))) end
            end
        end
        local refunded = true
        if refund > 0 then
            refunded = options.money.refund(source, refund, account, orderId) == true
            if not refunded and options.log then options.log(('Tienda G6 %s: devolucion de $%d PENDIENTE; revisar a mano.'):format(orderId, refund)) end
        end
        options.audit('shop_purchase', source)
        local message
        if #missing == 0 then message = ('Compra realizada: $%d.'):format(total)
        elseif #delivered == 0 then message = refunded and 'No se pudo entregar nada (inventario lleno o no disponible). Se te ha devuelto el dinero.'
            or 'No se pudo entregar nada y la devolucion ha fallado: avisa a un administrador.'
        else message = ('Compra parcial: no caben %s.%s'):format(table.concat(missing, ', '),
            refunded and (' Devueltos $%d.'):format(refund) or ' La devolucion ha fallado: avisa a un administrador.') end
        return { order = orderId, total = total - (refunded and refund or 0), delivered = delivered, message = message,
            balance = options.money.balance(source), partial = #missing > 0 }
    end

    function shop.drop(source) lastBuy[source] = nil end
    return shop
end
