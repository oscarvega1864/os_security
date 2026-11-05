local util = OSSecurity.Util
local catalog = OSSecurity.DeviceCatalog
local states = OSSecurity.DeviceStates
local validation = { SchemaVersion = 1, DeviceSchemaVersion = 2, MaxSequence = 9999999999 }
OSSecurity.DeviceValidation = validation

local inputFields = {
    type = true, model = true, owner = true, propertyId = true, vehicleId = true,
    position = true, rotation = true, metadata = true
}
local deviceFields = util.copy(inputFields)
for _, field in ipairs({ 'id', 'state', 'createdAt', 'updatedAt', 'schemaVersion',
    'installation', 'condition', 'maintenance', 'history' }) do deviceFields[field] = true end

function validation.id(id)
    return type(id) == 'string' and id:match('^osd_%d%d%d%d%d%d%d%d%d%d$') ~= nil
        and tonumber(id:sub(5)) > 0
end

local function vector(value, maximum)
    if not util.object(value, { x = true, y = true, z = true }) then return false end
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if not util.finite(value[axis]) or math.abs(value[axis]) > maximum then return false end
    end
    return true
end

function validation.metadata(value, schema)
    if not util.object(value) then return nil, 'Metadatos: se requiere un objeto plano.' end
    local count = 0
    for key, item in pairs(value) do
        count = count + 1
        local rule = schema[key]
        if count > 32 or not rule then return nil, 'Metadatos: propiedad no admitida.' end
        if rule.type == 'string' then
            if not util.text(item, math.min(rule.maxLength or 256, 256)) then
                return nil, 'Metadatos: texto invalido o demasiado largo.'
            end
        elseif rule.type == 'number' then
            if not util.finite(item) or item < (rule.min or -1000000)
                or item > (rule.max or 1000000) then
                return nil, 'Metadatos: numero fuera de limites.'
            end
        elseif rule.type == 'boolean' then
            if type(item) ~= 'boolean' then return nil, 'Metadatos: booleano requerido.' end
        else
            return nil, 'Metadatos: descriptor no admitido.'
        end
    end
    for key, rule in pairs(schema) do
        if rule.required and value[key] == nil then return nil, 'Metadatos: falta ' .. key end
    end
    return true
end

local function common(value)
    local definition = catalog.get(value.type)
    if not definition then return nil, 'Tipo de dispositivo inexistente.' end
    if not util.text(value.model, 64) or not value.model:match('^[%w_.%-]+$') then
        return nil, 'Modelo logico invalido (maximo 64 caracteres).'
    end
    for _, field in ipairs({ 'owner', 'propertyId', 'vehicleId' }) do
        if value[field] ~= nil and not util.text(value[field], 128) then
            return nil, 'Identificador opcional invalido: ' .. field
        end
    end
    if value.propertyId and value.vehicleId then return nil, 'Usar propiedad o vehiculo, no ambos.' end
    if value.position ~= nil and not vector(value.position, 1000000) then
        return nil, 'Posicion invalida: coordenadas finitas dentro de +/-1000000.'
    end
    if value.rotation ~= nil and not vector(value.rotation, 360) then
        return nil, 'Rotacion invalida: grados finitos dentro de +/-360.'
    end
    return validation.metadata(value.metadata, definition.metadataSchema)
end

function validation.create(input)
    if not util.object(input, inputFields) then return nil, 'Campos de creacion invalidos.' end
    local definition = catalog.get(input.type)
    if not definition then return nil, 'Tipo de dispositivo inexistente.' end
    -- No copiar entrada sin validar: podria contener ciclos o funciones.
    local normalized = {}
    for key, item in pairs(input) do normalized[key] = item end
    if normalized.model == nil then normalized.model = definition.defaultModel end
    if normalized.metadata == nil then normalized.metadata = {} end
    local ok, err = common(normalized)
    if not ok then return nil, err end
    return util.copy(normalized)
end

local function condition(value)
    if not util.object(value, { components = true }) or not util.object(value.components) then return false end
    local count = 0
    for id, component in pairs(value.components) do
        count = count + 1
        if count > 32 or not util.text(id, 40) or not id:match('^[%w_%-]+$')
            or not util.object(component, { health = true, wear = true,
                expectedLifetimeHours = true, faults = true }) then return false end
        for _, field in ipairs({ 'health', 'wear', 'expectedLifetimeHours' }) do
            local maximum = field == 'expectedLifetimeHours' and 1000000 or 100
            if component[field] ~= nil and (not util.finite(component[field])
                or component[field] < 0 or component[field] > maximum) then return false end
        end
        if component.faults ~= nil then
            if not util.array(component.faults, 16) then return false end
            for _, fault in ipairs(component.faults) do
                if not util.text(fault, 64) then return false end
            end
        end
    end
    return true
end

-- Contrato reservado para modulos futuros. El nucleo no genera ni modifica
-- reparaciones, averias ni sustituciones; no hay simulacion ni temporizadores.
local function maintenance(value, device, limits)
    if not util.object(value, { events = true })
        or not util.array(value.events, limits.MaxMaintenanceEvents) then return false end
    local previous = device.createdAt
    local kinds = { fault = true, repair = true, replacement = true }
    for _, event in ipairs(value.events) do
        if not util.object(event, { kind = true, componentId = true, at = true,
            notes = true, replacementId = true })
            or type(event.kind) ~= 'string' or not kinds[event.kind]
            or not util.text(event.componentId, 40) or not event.componentId:match('^[%w_%-]+$')
            or not util.integer(event.at, previous, device.updatedAt)
            or (event.notes ~= nil and not util.text(event.notes, 256))
            or (event.replacementId ~= nil and (event.kind ~= 'replacement'
                or not util.text(event.replacementId, 64))) then return false end
        previous = event.at
    end
    return true
end

function validation.device(value, limits)
    if not util.object(value, deviceFields) or not validation.id(value.id)
        or (value.schemaVersion ~= 1 and value.schemaVersion ~= validation.DeviceSchemaVersion) or not states.exists(value.state)
        or not util.integer(value.createdAt, 0, 253402300799)
        or not util.integer(value.updatedAt, value.createdAt, 253402300799) then
        return nil, 'Contrato de dispositivo invalido.'
    end
    local ok, err = common(value)
    if not ok then return nil, err end
    if not util.object(value.installation, { quality = true }) then return nil, 'Instalacion invalida.' end
    local quality = value.installation.quality
    if quality ~= nil and (not util.finite(quality) or quality < 0 or quality > 100) then
        return nil, 'Calidad de instalacion invalida.'
    end
    if value.schemaVersion == 1 then
        if not condition(value.condition) then return nil, 'Contrato de salud de componentes invalido.' end
        if not maintenance(value.maintenance, value, limits) then return nil, 'Contrato de mantenimiento invalido.' end
    else
        local valid, reason = OSSecurity.ComponentValidation.device(value, limits, condition, maintenance)
        if not valid then return nil, reason end
    end
    if not util.array(value.history, limits.MaxHistory) or #value.history < 1 then
        return nil, 'Historial invalido o fuera del limite.'
    end
    local previous, timestamp = nil, value.createdAt
    for index, event in ipairs(value.history) do
        if not util.object(event, { from = true, to = true, at = true })
            or not util.integer(event.at, timestamp, value.updatedAt) then return nil, 'Evento de historial invalido.' end
        if index == 1 then
            if event.from ~= nil or event.to ~= 'registered' or event.at ~= value.createdAt then
                return nil, 'Registro inicial invalido.'
            end
        elseif event.from ~= previous or not states.canTransition(event.from, event.to) then
            return nil, 'Transicion de historial invalida.'
        end
        previous, timestamp = event.to, event.at
    end
    if previous ~= value.state or (value.schemaVersion == 1 and timestamp ~= value.updatedAt) then
        return nil, 'Historial inconsistente.'
    end
    return true
end

function validation.snapshot(snapshot, limits)
    if not util.object(snapshot, { schemaVersion = true, revision = true, nextId = true, devices = true })
        or snapshot.schemaVersion ~= validation.SchemaVersion
        or not util.integer(snapshot.revision, 0, 9007199254740990)
        or not util.integer(snapshot.nextId, 1, validation.MaxSequence + 1)
        or not util.object(snapshot.devices) then return nil, 'Formato o version de almacenamiento incompatible.' end
    local count, largest, events = 0, 0, 0
    for id, device in pairs(snapshot.devices) do
        count = count + 1
        if count > limits.MaxDevices or not validation.id(id) or type(device) ~= 'table' or device.id ~= id then
            return nil, 'Indice de dispositivos invalido o limite excedido.'
        end
        local ok, err = validation.device(device, limits)
        if not ok then return nil, id .. ': ' .. err end
        events = events + #device.history
        if device.schemaVersion == 2 then events = events + device.maintenance.sequence end
        largest = math.max(largest, tonumber(id:sub(5)))
    end
    if snapshot.nextId <= largest or snapshot.revision ~= events then
        return nil, 'Secuencia de identificadores o revision inconsistente.'
    end
    return true
end

-- Cada revision es una creacion, transicion o servicio reproducible, nunca una
-- sustitucion libre de objetos. La misma comprobacion se aplica al recuperar.
function validation.successor(older, newer, limits)
    limits = limits or OSSecurity.ServerConfig
    if newer.revision ~= older.revision + 1 then return nil, 'Salto de revision.' end
    local changes, created = 0, false
    for id, previous in pairs(older.devices) do
        local current = newer.devices[id]
        if not current then return nil, 'Eliminacion permanente no permitida.' end
        if not util.equal(previous, current) then
            changes = changes + 1
            local expected
            if #current.history == #previous.history + 1 and current.schemaVersion == previous.schemaVersion then
                expected = OSSecurity.ComponentLifecycle.onStateChange(previous, current.updatedAt)
                expected.history[#expected.history + 1] = { from = previous.state, to = current.state, at = current.updatedAt }
                expected.state, expected.updatedAt = current.state, current.updatedAt
            elseif current.schemaVersion == 2 then
                local reason
                expected, reason = OSSecurity.ComponentLifecycle.apply(previous, current.maintenance.lastOperation, limits)
                if not expected then return nil, 'Servicio no reproducible: ' .. tostring(reason) end
            end
            if not expected or not util.equal(expected, current) then return nil, 'Cambio no reproducible o historial alterado.' end
        end
    end
    for id, current in pairs(newer.devices) do
        if not older.devices[id] then
            changes, created = changes + 1, true
            if id ~= ('osd_%010d'):format(older.nextId) or current.state ~= 'registered' or #current.history ~= 1 then
                return nil, 'Creacion o secuencia de ID invalida.'
            end
            if current.schemaVersion == 2 then
                if current.maintenance.sequence ~= 0 or not util.equal(current.maintenance.legacy, { components = {}, events = {} }) then
                    return nil, 'Creacion con historial de servicio previo.'
                end
                for _, component in pairs(current.condition.components) do
                    if component.health ~= 100 or component.generation ~= 1 or component.installedAt ~= current.createdAt
                        or component.lastMaintenanceAt ~= nil or component.wear.lastEvaluatedAt ~= current.createdAt
                        or component.wear.operatingHours ~= 0 or component.wear.discardedHours ~= 0 or #component.history ~= 0 then
                        return nil, 'Componente nuevo con datos de uso previos.'
                    end
                end
            end
        end
    end
    if changes ~= 1 or newer.nextId ~= older.nextId + (created and 1 or 0) then
        return nil, 'Una revision debe contener exactamente una operacion.'
    end
    return true
end
