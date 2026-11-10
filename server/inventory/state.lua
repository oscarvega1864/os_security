local util, identity = OSSecurity.Util, OSSecurity.Identity
local state = { SchemaVersion = 1 }
OSSecurity.InventoryState = state

function state.initial()
    return { schemaVersion = 1, revision = 0, nextInstallation = 1, accounts = {}, anchors = {}, installations = {} }
end

local function label(value)
    return util.text(value, 40) and value:match('^[%w_%-]+$') ~= nil
end

function state.vector(value, maximum)
    if not util.object(value, { x = true, y = true, z = true }) then return false end
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if not util.finite(value[axis]) or math.abs(value[axis]) > maximum then return false end
    end
    return true
end

-- Texto corto opcional de una zona (lugar o cliente), solo para mostrar en la tablet.
local function note(value) return value == nil or (util.text(value, 64) and not value:find('[%c<>]')) end

function state.anchor(anchor)
    if not util.object(anchor, { id = true, owner = true, installer = true, position = true, normal = true, radius = true, bucket = true, site = true,
        place = true, client = true, createdAt = true })
        or (anchor.site ~= nil and not state.site(anchor.site))
        or not note(anchor.place) or not note(anchor.client)
        or (anchor.createdAt ~= nil and not util.integer(anchor.createdAt, 0, 253402300799))
        or not label(anchor.id) or not identity.valid(anchor.owner) or not identity.valid(anchor.installer)
        or not state.vector(anchor.position, 1000000) or not state.vector(anchor.normal, 1)
        or not util.finite(anchor.radius) or anchor.radius < 0.25 or anchor.radius > 2
        or not util.integer(anchor.bucket, 0, 2147483647) then return false end
    local n = anchor.normal
    return math.abs(n.x * n.x + n.y * n.y + n.z * n.z - 1) < 0.00000001
end

function state.installationId(id)
    return type(id) == 'string' and id:match('^g6i_%d%d%d%d%d%d%d%d%d%d$') ~= nil and tonumber(id:sub(5)) > 0
end

-- Titular externo de los materiales (personaje del proveedor de objetos). Sin titular: objetos locales.
function state.holder(value)
    return util.text(value, 64) and value:match('^[%w_:%-]+$') ~= nil
end

-- Vinculo de un dispositivo con una propiedad o negocio del proveedor de activos (os_devtools).
state.SiteKinds = { property = true, business = true }
function state.site(value)
    return util.object(value, { kind = true, id = true }) and state.SiteKinds[value.kind] == true
        and util.integer(value.id, 1, 2147483646)
end

-- Alarma de una central: modo, codigo (hash), chapas autorizadas y ultimos eventos.
state.AlarmModes = { disarmed = true, armed = true, partial = true }
state.AlarmEvents = { armed = true, partial = true, disarmed = true, triggered = true, wrong_pin = true, lockout = true, pin_set = true, tag_added = true, tags_revoked = true, entry = true }
function state.alarm(value)
    local limits = OSSecurity.GameplayConfig.Alarm
    if not util.object(value, { mode = true, pin = true, tags = true, events = true, updatedAt = true }) or not state.AlarmModes[value.mode]
        or (value.pin ~= nil and not util.text(value.pin, 200)) or not util.integer(value.updatedAt, 0, 253402300799)
        or (value.tags ~= nil and not util.object(value.tags)) or (value.events ~= nil and not util.array(value.events, limits.MaxEvents)) then
        return false
    end
    local tags = 0
    for serial, enabled in pairs(value.tags or {}) do
        tags = tags + 1
        if tags > limits.MaxTags or type(serial) ~= 'string' or not serial:match('^[%w%-]+$') or #serial > 32 or enabled ~= true then return false end
    end
    for _, event in ipairs(value.events or {}) do
        if not util.object(event, { kind = true, at = true, by = true }) or not state.AlarmEvents[event.kind]
            or not util.integer(event.at, 0, 253402300799) or (event.by ~= nil and not util.text(event.by, 64)) then return false end
    end
    return true
end

-- Puerta con cerradura: puerta real del mapa (modelo y posicion) vinculada a una propiedad o negocio.
-- tier: nivel del bombin (1 = de serie); cylinder: kit instalado (sin el, el de serie); changes: numero de
-- cambios de bombin (identificador de operacion idempotente con el proveedor de objetos); ignored: dada
-- de baja por un administrador (no se vuelve a detectar ni tiene cerradura).
function state.doorId(id)
    return type(id) == 'string' and id:match('^[pn]%d+_%d+$') ~= nil and #id <= 24
end
function state.door(value)
    local limits = OSSecurity.GameplayConfig.Locks
    if not util.object(value, { id = true, site = true, model = true, position = true, bucket = true, tier = true, cylinder = true,
        locked = true, changes = true, updatedAt = true, ignored = true }) or not state.doorId(value.id) or not state.site(value.site)
        or not util.integer(value.model, -2147483648, 4294967295) or not state.vector(value.position, 1000000)
        or not util.integer(value.bucket, 0, 2147483647) or not util.integer(value.tier, 1, #limits.Tiers)
        or type(value.locked) ~= 'boolean' or not util.integer(value.changes, 0, 2147483647)
        or not util.integer(value.updatedAt, 0, 253402300799) or (value.ignored ~= nil and value.ignored ~= true) then return false end
    if value.cylinder == nil then return value.tier == 1 end
    return limits.Cylinders[value.cylinder] == value.tier
end

-- Equipo de seguridad de un vehiculo de os_devtools (por su ID): cierre centralizado y alarma.
-- locked: cerrado con el mando (solo con cierre); changes: instalaciones hechas (operaciones idempotentes).
function state.carId(id)
    return type(id) == 'string' and id:match('^%d+$') ~= nil and #id <= 10 and tonumber(id) >= 1
end
function state.car(value)
    if not util.object(value, { id = true, plate = true, lock = true, alarm = true, locked = true, changes = true, updatedAt = true })
        or not util.integer(value.id, 1, 2147483646) or not util.text(value.plate, 8) or not value.plate:match('^[%w]+$')
        or type(value.lock) ~= 'boolean' or type(value.alarm) ~= 'boolean' or type(value.locked) ~= 'boolean'
        or not util.integer(value.changes, 0, 2147483647) or not util.integer(value.updatedAt, 0, 253402300799) then return false end
    if value.alarm and not value.lock then return false end -- la alarma va sobre el cierre
    return true
end

-- Orden de trabajo: solicitud de un cliente que atiende un tecnico G6 (ver server/orders/service.lua).
state.OrderKinds = { cctv = true, alarm = true, repair = true, lock = true, car = true, other = true }
state.OrderStatus = { open = true, accepted = true, billed = true, paid = true, cancelled = true }
function state.orderId(id)
    return type(id) == 'string' and id:match('^ot_%d%d%d%d%d%d$') ~= nil
end
local function shortText(value, size) return value == nil or (util.text(value, size) and not value:find('[%c<>]')) end
function state.order(value)
    local limits = OSSecurity.GameplayConfig.Orders
    if not util.object(value, { id = true, kind = true, status = true, client = true, clientName = true, technician = true, techName = true,
        note = true, place = true, position = true, site = true, price = true, payout = true, createdAt = true, updatedAt = true })
        or not state.orderId(value.id) or not state.OrderKinds[value.kind] or not state.OrderStatus[value.status]
        or not identity.valid(value.client) or (value.technician ~= nil and not identity.valid(value.technician))
        or not shortText(value.clientName, 64) or not shortText(value.techName, 64) or not shortText(value.note, limits.NoteLength)
        or not shortText(value.place, 80) or not state.vector(value.position, 1000000) or (value.site ~= nil and not state.site(value.site))
        or (value.price ~= nil and not util.integer(value.price, 1, limits.MaxPrice))
        or (value.payout ~= nil and value.payout ~= 'pending' and value.payout ~= 'done')
        or not util.integer(value.createdAt, 0, 253402300799) or not util.integer(value.updatedAt, 0, 253402300799) then return false end
    -- Coherencia del estado: aceptada o facturada exige tecnico; facturada o pagada exige precio.
    if (value.status == 'accepted' or value.status == 'billed') and not value.technician then return false end
    if (value.status == 'billed' or value.status == 'paid') and not value.price then return false end
    if value.payout ~= nil and value.status ~= 'paid' then return false end
    return true
end

local function placement(value)
    return util.object(value, { id = true, anchorId = true, owner = true, installer = true, position = true,
        rotation = true, bucket = true, model = true, status = true, createdAt = true, updatedAt = true, deviceId = true, reason = true,
        materials = true, tools = true, holder = true })
        and (value.holder == nil or state.holder(value.holder))
        and state.installationId(value.id) and label(value.anchorId) and identity.valid(value.owner) and identity.valid(value.installer)
        and state.vector(value.position, 1000000) and state.vector(value.rotation, 360)
        and math.abs(value.rotation.x) <= 90 and math.abs(value.rotation.y) <= 180
        and util.integer(value.bucket, 0, 2147483647) and type(value.model) == 'string' and OSSecurity.GameplayConfig.Models[value.model] == true
        and util.integer(value.createdAt, 0, 253402300799) and util.integer(value.updatedAt, value.createdAt, 253402300799)
        and ((value.status == 'pending' and value.deviceId == nil and value.reason == nil)
            or (value.status == 'committed' and OSSecurity.DeviceValidation.id(value.deviceId) and value.reason == nil)
            or (value.status == 'removed' and OSSecurity.DeviceValidation.id(value.deviceId) and value.reason == nil)
            or (value.status == 'cancelled' and value.deviceId == nil
                and ({ creation_rejected = true, recovery_cancelled = true, retired = true })[value.reason] == true))
end

local function materials(value, limits)
    if not util.object(value.materials) or not util.array(value.tools, 8) then return false end
    -- Al menos un kit (el que define el producto instalado).
    local kits = 0
    for item, amount in pairs(value.materials) do
        if OSSecurity.ItemCatalog[item] and OSSecurity.ItemCatalog[item].category == 'kit' and util.integer(amount, 1, limits.MaxItemQuantity) then kits = kits + 1 end
    end
    if kits == 0 then return false end
    local count = 0
    for item, amount in pairs(value.materials) do
        count = count + 1
        local definition = OSSecurity.ItemCatalog[item]
        if count > 8 or not definition or (definition.category ~= 'kit' and definition.category ~= 'material')
            or not util.integer(amount, 1, limits.MaxItemQuantity) then return false end
    end
    for _, item in ipairs(value.tools) do
        if type(item) ~= 'string' or not OSSecurity.ItemCatalog[item] or OSSecurity.ItemCatalog[item].category ~= 'tool' then return false end
    end
    return true
end

local function operation(op, limits)
    if not util.object(op, { kind = true, at = true, principal = true, item = true, amount = true,
        deviceId = true, role = true, anchor = true, installation = true, installationId = true, reason = true, site = true, alarm = true,
        doorId = true, door = true, carId = true, car = true, anchorId = true, orderId = true, order = true, target = true })
        or not util.integer(op.at, 0, 253402300799) then return false end
    local fields = { kind = true, at = true }
    if op.kind == 'grant' or op.kind == 'migrate' then
        fields.principal, fields.item, fields.amount = true, true, true
        if not identity.valid(op.principal) or type(op.item) ~= 'string' or not OSSecurity.ItemCatalog[op.item]
            or not util.integer(op.amount, 1, limits.MaxItemQuantity) then return false end
    elseif op.kind == 'access' then
        fields.principal, fields.deviceId, fields.role = true, true, true
        if not identity.valid(op.principal) or not OSSecurity.DeviceValidation.id(op.deviceId)
            or type(op.role) ~= 'string' or not ({ client = true, technician = true, supervisor = true, none = true })[op.role] then return false end
    elseif op.kind == 'site' then
        -- Sin 'site' se retira el vinculo.
        fields.deviceId, fields.site = true, true
        if not OSSecurity.DeviceValidation.id(op.deviceId) or (op.site ~= nil and not state.site(op.site)) then return false end
    elseif op.kind == 'alarm' then
        fields.deviceId, fields.alarm = true, true
        if not OSSecurity.DeviceValidation.id(op.deviceId) or not state.alarm(op.alarm) then return false end
    elseif op.kind == 'car' then
        fields.carId, fields.car = true, true
        if not state.carId(op.carId) or not state.car(op.car) or tostring(op.car.id) ~= op.carId then return false end
    elseif op.kind == 'door' then
        -- Sin 'door' se da de baja la puerta.
        fields.doorId, fields.door = true, true
        if not state.doorId(op.doorId) or (op.door ~= nil and (not state.door(op.door) or op.door.id ~= op.doorId)) then return false end
    elseif op.kind == 'anchor' then
        fields.anchor = true
        if not state.anchor(op.anchor) then return false end
    elseif op.kind == 'order' then
        -- Sin 'order' se borra (limpieza de ordenes cerradas antiguas).
        fields.orderId, fields.order = true, true
        if not state.orderId(op.orderId) or (op.order ~= nil and (not state.order(op.order) or op.order.id ~= op.orderId)) then return false end
    elseif op.kind == 'rehome' then
        -- Paso de datos de una cuenta (license) al personaje que los creo (char:...).
        fields.principal, fields.target = true, true
        if not identity.account(op.principal) or not identity.character(op.target) then return false end
    elseif op.kind == 'unanchor' then
        -- Borrar una zona que nunca se ha usado (sin instalaciones que la referencien).
        fields.anchorId = true
        if not label(op.anchorId) then return false end
    elseif op.kind == 'reserve' then
        fields.installation = true
        if not placement(op.installation) or not materials(op.installation, limits)
            or op.installation.status ~= 'pending' or op.installation.createdAt ~= op.at then return false end
    elseif op.kind == 'finish' then
        fields.installationId, fields.deviceId = true, true
        if not state.installationId(op.installationId) or not OSSecurity.DeviceValidation.id(op.deviceId) then return false end
    elseif op.kind == 'remove' then
        -- Desmontaje: la instalacion queda 'removed' y libera el montaje. Con objetos locales, el kit
        -- recuperado se abona a 'principal'; con proveedor externo lo entrega el proveedor.
        fields.installationId, fields.principal, fields.item = true, true, true
        if not state.installationId(op.installationId) or (op.principal ~= nil and not identity.valid(op.principal))
            or (op.item ~= nil and (not OSSecurity.ItemCatalog[op.item] or OSSecurity.ItemCatalog[op.item].category ~= 'kit'))
            or ((op.principal == nil) ~= (op.item == nil)) then return false end
    elseif op.kind == 'cancel' then
        fields.installationId, fields.reason = true, true
        if not state.installationId(op.installationId) or type(op.reason) ~= 'string'
            or not ({ creation_rejected = true, recovery_cancelled = true, retired = true })[op.reason] then return false end
    else return false end
    return util.object(op, fields)
end

function state.held(snapshot, principal, item)
    local count = 0
    for _, installation in pairs(snapshot.installations) do
        if installation.status == 'pending' and installation.installer == principal and installation.holder == nil then
            count = count + (installation.materials[item] or 0)
        end
    end
    return count
end

function state.snapshot(snapshot, limits)
    if not util.object(snapshot, { schemaVersion = true, revision = true, nextInstallation = true,
        accounts = true, anchors = true, installations = true, lastOperation = true, sites = true, alarms = true, doors = true, cars = true, orders = true,
        owners = true })
        or snapshot.schemaVersion ~= 1 or not util.integer(snapshot.revision, 0, 9007199254740000)
        or not util.integer(snapshot.nextInstallation, 1, limits.MaxInstallations + 1)
        or not util.object(snapshot.accounts) or not util.object(snapshot.anchors) or not util.object(snapshot.installations)
        or (snapshot.sites ~= nil and not util.object(snapshot.sites)) or (snapshot.alarms ~= nil and not util.object(snapshot.alarms))
        or (snapshot.doors ~= nil and not util.object(snapshot.doors)) or (snapshot.cars ~= nil and not util.object(snapshot.cars))
        or (snapshot.orders ~= nil and not util.object(snapshot.orders)) or (snapshot.owners ~= nil and not util.object(snapshot.owners))
        or (snapshot.revision == 0 and snapshot.lastOperation ~= nil)
        or (snapshot.revision > 0 and not operation(snapshot.lastOperation, limits)) then return nil, 'Formato de inventario incompatible.' end
    local count, deviceIds = 0, {}
    for id, installation in pairs(snapshot.installations) do
        count = count + 1
        if count > limits.MaxInstallations or not placement(installation) or installation.id ~= id
            or tonumber(id:sub(5)) >= snapshot.nextInstallation then return nil, 'Instalacion de inventario invalida.' end
        if not materials(installation, limits) then return nil, 'Contrato de materiales invalido.' end
        local anchor = snapshot.anchors[installation.anchorId]
        if not state.anchor(anchor) or not snapshot.accounts[installation.installer]
            or (installation.status == 'pending' and (anchor.owner ~= installation.owner
                or anchor.installer ~= installation.installer or anchor.bucket ~= installation.bucket)) then
            return nil, 'Reserva sin cuenta o montaje consistente.'
        end
        if installation.deviceId then
            if deviceIds[installation.deviceId] then return nil, 'Dispositivo vinculado dos veces.' end
            deviceIds[installation.deviceId] = true
        end
    end
    if snapshot.nextInstallation ~= count + 1 or snapshot.revision < count then return nil, 'Secuencia de instalaciones inconsistente.' end
    count = 0
    for principal, account in pairs(snapshot.accounts) do
        count = count + 1
        if count > limits.MaxAccounts or not identity.valid(principal) or not util.object(account, { items = true, grants = true, migrated = true })
            or not util.object(account.items) or not util.object(account.grants)
            or (account.migrated ~= nil and not util.object(account.migrated)) then return nil, 'Cuenta de inventario invalida.' end
        for item, amount in pairs(account.migrated or {}) do
            if not OSSecurity.ItemCatalog[item] or not util.integer(amount, 1, 2147483647) then return nil, 'Registro de migracion invalido.' end
        end
        local total, grants = 0, 0
        for item, definition in pairs(OSSecurity.ItemCatalog) do
            local entry = account.items[item]
            local held = state.held(snapshot, principal, item)
            if entry ~= nil and (not util.object(entry, { count = true, metadata = true })
                or not util.integer(entry.count, 1, limits.MaxItemQuantity) or not util.object(entry.metadata, {})) then
                return nil, 'Cantidad o metadatos de item invalidos.'
            end
            local amount = (entry and entry.count or 0) + held
            if amount > limits.MaxItemQuantity then return nil, 'Limite de items reservados excedido.' end
            total = total + amount
        end
        for item in pairs(account.items) do if not OSSecurity.ItemCatalog[item] then return nil, 'Item desconocido.' end end
        if total > limits.MaxTotalItems then return nil, 'Limite de inventario excedido.' end
        for id, role in pairs(account.grants) do
            grants = grants + 1
            if grants > limits.MaxGrantsPerAccount or not OSSecurity.DeviceValidation.id(id)
                or not ({ client = true, technician = true, supervisor = true })[role] then return nil, 'Concesion de acceso invalida.' end
        end
    end
    count = 0
    for id, anchor in pairs(snapshot.anchors) do
        count = count + 1
        if count > limits.MaxAnchors or not state.anchor(anchor) or id ~= anchor.id then return nil, 'Montaje autorizado invalido.' end
    end
    count = 0
    for deviceId, site in pairs(snapshot.sites or {}) do
        count = count + 1
        if count > limits.MaxInstallations or not OSSecurity.DeviceValidation.id(deviceId) or not state.site(site) then
            return nil, 'Vinculo de propiedad o negocio invalido.'
        end
    end
    for deviceId, alarm in pairs(snapshot.alarms or {}) do
        if not OSSecurity.DeviceValidation.id(deviceId) or not state.alarm(alarm) then return nil, 'Alarma invalida.' end
    end
    count = 0
    for carId, car in pairs(snapshot.cars or {}) do
        if not state.carId(carId) or not state.car(car) or tostring(car.id) ~= carId then return nil, 'Vehiculo con equipo de seguridad invalido.' end
    end
    count = 0
    for deviceId, owner in pairs(snapshot.owners or {}) do
        count = count + 1
        if count > limits.MaxInstallations or not OSSecurity.DeviceValidation.id(deviceId) or not identity.valid(owner) then
            return nil, 'Titular de dispositivo invalido.'
        end
    end
    local orders = 0
    for orderId, order in pairs(snapshot.orders or {}) do
        orders = orders + 1
        if orders > OSSecurity.GameplayConfig.Orders.MaxOrders or not state.order(order) or order.id ~= orderId then return nil, 'Orden de trabajo invalida.' end
    end
    for doorId, door in pairs(snapshot.doors or {}) do
        count = count + 1
        if count > OSSecurity.GameplayConfig.Locks.MaxDoors or not state.door(door) or door.id ~= doorId then return nil, 'Puerta con cerradura invalida.' end
    end
    if snapshot.revision == 0 and (next(snapshot.accounts) or next(snapshot.anchors) or next(snapshot.installations)) then
        return nil, 'Inventario inicial no vacio.'
    end
    return true
end

function state.apply(snapshot, op, limits)
    if not operation(op, limits) or (snapshot.lastOperation and op.at < snapshot.lastOperation.at) then
        return nil, 'Operacion de inventario invalida.'
    end
    local nextState = util.copy(snapshot)
    local function account(principal)
        nextState.accounts[principal] = nextState.accounts[principal] or { items = {}, grants = {} }
        return nextState.accounts[principal]
    end
    if op.kind == 'grant' then
        local target = account(op.principal)
        local entry = target.items[op.item] or { count = 0, metadata = {} }
        entry.count = entry.count + op.amount; target.items[op.item] = entry
    elseif op.kind == 'migrate' then
        -- Retira objetos locales ya entregados al proveedor externo; el total migrado hace idempotente la entrega.
        local target = account(op.principal)
        local entry = target.items[op.item]
        if not entry or entry.count < op.amount then return nil, 'Cantidad local insuficiente para migrar.' end
        entry.count = entry.count - op.amount
        if entry.count == 0 then target.items[op.item] = nil end
        target.migrated = target.migrated or {}
        target.migrated[op.item] = (target.migrated[op.item] or 0) + op.amount
    elseif op.kind == 'access' then
        account(op.principal).grants[op.deviceId] = op.role ~= 'none' and op.role or nil
    elseif op.kind == 'alarm' then
        nextState.alarms = nextState.alarms or {}
        nextState.alarms[op.deviceId] = util.copy(op.alarm)
    elseif op.kind == 'car' then
        nextState.cars = nextState.cars or {}
        nextState.cars[op.carId] = util.copy(op.car)
    elseif op.kind == 'order' then
        nextState.orders = nextState.orders or {}
        if op.order and not nextState.orders[op.orderId] then
            local count = 0
            for _ in pairs(nextState.orders) do count = count + 1 end
            if count >= OSSecurity.GameplayConfig.Orders.MaxOrders then return nil, 'Limite de ordenes de trabajo alcanzado.' end
        end
        nextState.orders[op.orderId] = op.order and util.copy(op.order) or nil
        if next(nextState.orders) == nil then nextState.orders = nil end
    elseif op.kind == 'rehome' then
        -- Todo lo de la cuenta pasa al personaje: objetos locales, concesiones, zonas, instalaciones y
        -- solicitudes. Los dispositivos del registro no cambian (es historico); su titular nuevo queda en 'owners'.
        local from, to = op.principal, op.target
        local origin = nextState.accounts[from]
        if not origin then return nil, 'Cuenta de origen inexistente.' end
        local target = account(to)
        for item, entry in pairs(origin.items) do
            local current = target.items[item] or { count = 0, metadata = {} }
            current.count = current.count + entry.count; target.items[item] = current
        end
        for deviceId, role in pairs(origin.grants) do target.grants[deviceId] = target.grants[deviceId] or role end
        for item, amount in pairs(origin.migrated or {}) do
            target.migrated = target.migrated or {}
            target.migrated[item] = (target.migrated[item] or 0) + amount
        end
        nextState.accounts[from] = nil
        for _, anchor in pairs(nextState.anchors) do
            if anchor.owner == from then anchor.owner = to end
            if anchor.installer == from then anchor.installer = to end
        end
        for _, installation in pairs(nextState.installations) do
            if installation.owner == from then
                installation.owner = to
                if installation.deviceId then
                    nextState.owners = nextState.owners or {}
                    nextState.owners[installation.deviceId] = to
                end
            end
            if installation.installer == from then installation.installer = to end
        end
        for _, order in pairs(nextState.orders or {}) do
            if order.client == from then order.client = to end
            if order.technician == from then order.technician = to end
        end
    elseif op.kind == 'door' then
        nextState.doors = nextState.doors or {}
        nextState.doors[op.doorId] = op.door and util.copy(op.door) or nil
        if next(nextState.doors) == nil then nextState.doors = nil end
    elseif op.kind == 'site' then
        nextState.sites = nextState.sites or {}
        nextState.sites[op.deviceId] = op.site and util.copy(op.site) or nil
        if next(nextState.sites) == nil then nextState.sites = nil end
    elseif op.kind == 'anchor' then
        for _, installation in pairs(snapshot.installations) do
            if installation.anchorId == op.anchor.id and installation.status == 'pending' then return nil, 'Montaje con operacion pendiente.' end
        end
        nextState.anchors[op.anchor.id] = util.copy(op.anchor)
    elseif op.kind == 'unanchor' then
        if not snapshot.anchors[op.anchorId] then return nil, 'Zona inexistente.' end
        for _, installation in pairs(snapshot.installations) do
            if installation.anchorId == op.anchorId then return nil, 'La zona tiene instalaciones registradas; no se puede borrar.' end
        end
        nextState.anchors[op.anchorId] = nil
    elseif op.kind == 'reserve' then
        local proposed = op.installation
        local anchor = snapshot.anchors[proposed.anchorId]
        if proposed.id ~= ('g6i_%010d'):format(snapshot.nextInstallation) or not anchor
            or anchor.owner ~= proposed.owner or anchor.installer ~= proposed.installer or anchor.bucket ~= proposed.bucket then
            return nil, 'Reserva de instalacion no autorizada.'
        end
        for _, existing in pairs(snapshot.installations) do
            if existing.anchorId == proposed.anchorId and existing.status ~= 'cancelled' and existing.status ~= 'removed' then return nil, 'Montaje ocupado o pendiente.' end
        end
        local target = account(proposed.installer)
        if not util.object(proposed.materials) or not util.array(proposed.tools, 8) then return nil, 'Contrato de materiales invalido.' end
        -- Con titular externo, el proveedor cobra y devuelve los materiales; aqui solo se registra la reserva.
        if proposed.holder == nil then
            for _, item in ipairs(proposed.tools) do
                if not target.items[item] or target.items[item].count < 1 then return nil, 'Faltan herramientas.' end
            end
            for item, amount in pairs(proposed.materials) do
                local entry = target.items[item]
                if not entry or entry.count < amount then return nil, 'Faltan materiales.' end
                entry.count = entry.count - amount
                if entry.count == 0 then target.items[item] = nil end
            end
        end
        nextState.installations[proposed.id] = util.copy(proposed)
        nextState.nextInstallation = snapshot.nextInstallation + 1
    elseif op.kind == 'remove' then
        local installation = nextState.installations[op.installationId]
        if not installation or installation.status ~= 'committed' then return nil, 'Instalacion no montada.' end
        installation.status, installation.updatedAt = 'removed', op.at
        if op.principal then
            local target = account(op.principal)
            local entry = target.items[op.item] or { count = 0, metadata = {} }
            entry.count = entry.count + 1; target.items[op.item] = entry
        end
    else
        local installation = nextState.installations[op.installationId]
        if not installation or installation.status ~= 'pending' then return nil, 'Reserva no pendiente o ya confirmada.' end
        installation.updatedAt = op.at
        if op.kind == 'finish' then
            installation.status, installation.deviceId = 'committed', op.deviceId
            account(installation.installer).grants[op.deviceId] = 'technician'
        else
            installation.status, installation.reason = 'cancelled', op.reason
            if installation.holder == nil then
                local target = account(installation.installer)
                for item, amount in pairs(installation.materials) do
                    local entry = target.items[item] or { count = 0, metadata = {} }
                    entry.count = entry.count + amount; target.items[item] = entry
                end
            end
        end
    end
    nextState.revision, nextState.lastOperation = snapshot.revision + 1, util.copy(op)
    local ok, err = state.snapshot(nextState, limits)
    if not ok then return nil, err end
    return nextState
end

function state.successor(previous, current, limits)
    if current.revision ~= previous.revision + 1 then return nil, 'Revision de inventario no consecutiva.' end
    local expected, err = state.apply(previous, current.lastOperation, limits)
    if not expected or not util.equal(expected, current) then return nil, err or 'Cambio de inventario no reproducible.' end
    return true
end
