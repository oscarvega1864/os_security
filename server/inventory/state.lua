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

function state.anchor(anchor)
    if not util.object(anchor, { id = true, owner = true, installer = true, position = true, normal = true, radius = true, bucket = true })
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

local function placement(value)
    return util.object(value, { id = true, anchorId = true, owner = true, installer = true, position = true,
        rotation = true, bucket = true, model = true, status = true, createdAt = true, updatedAt = true, deviceId = true, reason = true,
        materials = true, tools = true, holder = true })
        and (value.holder == nil or state.holder(value.holder))
        and state.installationId(value.id) and label(value.anchorId) and identity.valid(value.owner) and identity.valid(value.installer)
        and state.vector(value.position, 1000000) and state.vector(value.rotation, 360)
        and math.abs(value.rotation.x) <= 45 and math.abs(value.rotation.y) <= 5
        and util.integer(value.bucket, 0, 2147483647) and type(value.model) == 'string' and OSSecurity.GameplayConfig.Models[value.model] == true
        and util.integer(value.createdAt, 0, 253402300799) and util.integer(value.updatedAt, value.createdAt, 253402300799)
        and ((value.status == 'pending' and value.deviceId == nil and value.reason == nil)
            or (value.status == 'committed' and OSSecurity.DeviceValidation.id(value.deviceId) and value.reason == nil)
            or (value.status == 'cancelled' and value.deviceId == nil
                and ({ creation_rejected = true, recovery_cancelled = true, retired = true })[value.reason] == true))
end

local function materials(value, limits)
    if not util.object(value.materials) or not util.array(value.tools, 8)
        or not util.integer(value.materials.os_cctv_kit, 1, limits.MaxItemQuantity) then return false end
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
        deviceId = true, role = true, anchor = true, installation = true, installationId = true, reason = true, site = true })
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
    elseif op.kind == 'anchor' then
        fields.anchor = true
        if not state.anchor(op.anchor) then return false end
    elseif op.kind == 'reserve' then
        fields.installation = true
        if not placement(op.installation) or not materials(op.installation, limits)
            or op.installation.status ~= 'pending' or op.installation.createdAt ~= op.at then return false end
    elseif op.kind == 'finish' then
        fields.installationId, fields.deviceId = true, true
        if not state.installationId(op.installationId) or not OSSecurity.DeviceValidation.id(op.deviceId) then return false end
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
        accounts = true, anchors = true, installations = true, lastOperation = true, sites = true })
        or snapshot.schemaVersion ~= 1 or not util.integer(snapshot.revision, 0, 9007199254740000)
        or not util.integer(snapshot.nextInstallation, 1, limits.MaxInstallations + 1)
        or not util.object(snapshot.accounts) or not util.object(snapshot.anchors) or not util.object(snapshot.installations)
        or (snapshot.sites ~= nil and not util.object(snapshot.sites))
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
    elseif op.kind == 'site' then
        nextState.sites = nextState.sites or {}
        nextState.sites[op.deviceId] = op.site and util.copy(op.site) or nil
        if next(nextState.sites) == nil then nextState.sites = nil end
    elseif op.kind == 'anchor' then
        for _, installation in pairs(snapshot.installations) do
            if installation.anchorId == op.anchor.id and installation.status == 'pending' then return nil, 'Montaje con operacion pendiente.' end
        end
        nextState.anchors[op.anchor.id] = util.copy(op.anchor)
    elseif op.kind == 'reserve' then
        local proposed = op.installation
        local anchor = snapshot.anchors[proposed.anchorId]
        if proposed.id ~= ('g6i_%010d'):format(snapshot.nextInstallation) or not anchor
            or anchor.owner ~= proposed.owner or anchor.installer ~= proposed.installer or anchor.bucket ~= proposed.bucket then
            return nil, 'Reserva de instalacion no autorizada.'
        end
        for _, existing in pairs(snapshot.installations) do
            if existing.anchorId == proposed.anchorId and existing.status ~= 'cancelled' then return nil, 'Montaje ocupado o pendiente.' end
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
