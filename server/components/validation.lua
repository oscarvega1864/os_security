local util, catalog, wear = OSSecurity.Util, OSSecurity.ComponentCatalog, OSSecurity.ComponentWear
local validation = {}
OSSecurity.ComponentValidation = validation

local function number(value, minimum, maximum)
    return util.finite(value) and value >= minimum and value <= maximum
end

local function slotId(slot)
    return util.text(slot, 40) and slot:match('^[%w_%-]+$') ~= nil
end

local function spec(device, slot, value)
    return util.object(value, { type = true, model = true, quality = true, lifeHours = true,
        intensity = true, environment = true, installationQuality = true, intervalSeconds = true, maxElapsedHours = true })
        and catalog.compatible(device.type, slot, value.type, value.model)
        and number(value.quality, 0, 100) and number(value.lifeHours, 1, 1000000)
        and number(value.intensity, 0, 5) and number(value.environment, 0, 5)
        and number(value.installationQuality, 0, 100)
        and util.integer(value.intervalSeconds, 1, 3600) and number(value.maxElapsedHours, 1, 168)
end

local function componentId(device, slot, id)
    if not util.text(id, 96) then return false end
    local prefix = device.id .. ':' .. slot .. ':'
    if id:sub(1, #prefix) ~= prefix then return false end
    local generation = id:sub(#prefix + 1)
    return generation:match('^%d+$') ~= nil and util.integer(tonumber(generation), 1, 999999999)
        and generation == ('%d'):format(tonumber(generation))
end

function validation.operation(device, op)
    if not util.object(op, { kind = true, at = true, slot = true, hours = true,
        kit = true, spec = true, gain = true, ceiling = true, allowFailed = true })
        or not util.integer(op.at, device.createdAt, 253402300799) then return nil, 'Contrato de operacion invalido.' end
    local fields = { kind = true, at = true }
    if op.kind == 'provision' then
        fields.kit = true
        if not util.object(op.kit) then return nil, 'Kit invalido.' end
        local count = 0
        for slot, item in pairs(op.kit) do
            count = count + 1
            if not slotId(slot) or not spec(device, slot, item) then return nil, 'Componente de kit incompatible o invalido.' end
        end
        if count < 1 or count > 32 then return nil, 'Kit fuera de limites.' end
    elseif op.kind == 'simulate' then
        fields.hours = true
        if not number(op.hours, 0.000001, 72) then return nil, 'Simulacion fuera de limites.' end
    elseif op.kind == 'repair' then
        fields.slot, fields.gain, fields.ceiling, fields.allowFailed = true, true, true, true
        if not slotId(op.slot) or not number(op.gain, 0.000001, 100)
            or not number(op.ceiling, 0, 100) or type(op.allowFailed) ~= 'boolean' then return nil, 'Politica de reparacion invalida.' end
    elseif op.kind == 'replace' then
        fields.slot, fields.spec = true, true
        if not slotId(op.slot) or not spec(device, op.slot, op.spec) then return nil, 'Sustitucion incompatible.' end
    elseif op.kind ~= 'inspect' then
        return nil, 'Operacion de mantenimiento desconocida.'
    end
    if not util.object(op, fields) then return nil, 'Campos de operacion no admitidos.' end
    return true
end

local function summary(device, slot, value, at)
    return util.object(value, { id = true, type = true, model = true, state = true,
        health = true, installedAt = true, operatingHours = true })
        and componentId(device, slot, value.id)
        and catalog.compatible(device.type, slot, value.type, value.model)
        and number(value.health, 0, 100) and value.state == wear.state(value.health)
        and util.integer(value.installedAt, device.createdAt, at)
        and number(value.operatingHours, 0, 1000000000000)
end

function validation.device(device, limits, legacyCondition, legacyMaintenance)
    local maintenance = device.maintenance
    if not util.object(device.condition, { components = true }) or not util.object(device.condition.components)
        or not util.object(maintenance, { sequence = true, events = true, legacy = true, lastOperation = true })
        or not util.integer(maintenance.sequence, 0, 9007199254740000)
        or not util.array(maintenance.events, limits.MaxMaintenanceEvents)
        or not util.object(maintenance.legacy, { components = true, events = true })
        or not legacyCondition({ components = maintenance.legacy.components })
        or not legacyMaintenance({ events = maintenance.legacy.events }, device, limits) then
        return nil, 'Contrato de componentes/mantenimiento invalido.'
    end
    if maintenance.sequence == 0 then
        if maintenance.lastOperation ~= nil or #maintenance.events ~= 0 then return nil, 'Secuencia inicial de servicio invalida.' end
    else
        local ok = validation.operation(device, maintenance.lastOperation)
        if not ok or maintenance.lastOperation.at > device.updatedAt then return nil, 'Ultima operacion de servicio invalida.' end
    end
    local sequence, timestamp = 0, device.createdAt
    local eventKinds = { provision = true, simulate = true, repair = true, replace = true }
    for _, event in ipairs(maintenance.events) do
        if not util.object(event, { kind = true, at = true, sequence = true, changes = true, operation = true })
            or type(event.kind) ~= 'string' or not eventKinds[event.kind]
            or not util.integer(event.sequence, sequence + 1, maintenance.sequence)
            or not util.integer(event.at, timestamp, device.updatedAt)
            or not util.object(event.changes) or not validation.operation(device, event.operation)
            or event.operation.kind ~= event.kind or event.operation.at ~= event.at then return nil, 'Intervencion invalida.' end
        local count = 0
        for slot, change in pairs(event.changes) do
            count = count + 1
            if not slotId(slot) or not util.object(change, { before = true, after = true })
                or not summary(device, slot, change.after, event.at)
                or (change.before ~= nil and not summary(device, slot, change.before, event.at)) then
                return nil, 'Resultado de intervencion invalido.'
            end
        end
        if count < 1 or count > 32 then return nil, 'Intervencion sin resultados o fuera de limite.' end
        sequence, timestamp = event.sequence, event.at
    end
    local count = 0
    for slot, component in pairs(device.condition.components) do
        count = count + 1
        if count > 32 or not slotId(slot) or not util.object(component, { id = true, generation = true,
            type = true, model = true, quality = true, health = true, state = true, installedAt = true,
            lastMaintenanceAt = true, expectedLifetimeHours = true, history = true, wear = true })
            or not util.integer(component.generation, 1, 999999999)
            or component.id ~= ('%s:%s:%d'):format(device.id, slot, component.generation)
            or not catalog.compatible(device.type, slot, component.type, component.model)
            or not number(component.quality, 0, 100) or not number(component.health, 0, 100)
            or component.state ~= wear.state(component.health)
            or not number(component.expectedLifetimeHours, 1, 1000000)
            or not util.integer(component.installedAt, device.createdAt, device.updatedAt)
            or (component.lastMaintenanceAt ~= nil and not util.integer(component.lastMaintenanceAt, component.installedAt, device.updatedAt))
            or not util.array(component.history, limits.MaxMaintenanceEvents)
            or not util.object(component.wear, { intensity = true, environment = true, installationQuality = true,
                intervalSeconds = true, maxElapsedHours = true, lastEvaluatedAt = true,
                operatingHours = true, discardedHours = true }) then return nil, 'Componente invalido: ' .. tostring(slot) end
        local params = component.wear
        if not number(params.intensity, 0, 5) or not number(params.environment, 0, 5)
            or not number(params.installationQuality, 0, 100) or not util.integer(params.intervalSeconds, 1, 3600)
            or not number(params.maxElapsedHours, 1, 168)
            or not util.integer(params.lastEvaluatedAt, component.installedAt, device.updatedAt)
            or not number(params.operatingHours, 0, 1000000000000)
            or not number(params.discardedHours, 0, 1000000000000) then return nil, 'Parametros de desgaste invalidos.' end
        local previous = 0
        for _, index in ipairs(component.history) do
            if not util.integer(index, previous + 1, #maintenance.events) then return nil, 'Referencia de historial invalida.' end
            local change = maintenance.events[index].changes[slot]
            if not change or (change.after.id ~= component.id and (not change.before or change.before.id ~= component.id)) then
                return nil, 'Intervencion ajena al componente.'
            end
            previous = index
        end
    end
    -- Migrados se equipan explicitamente; los kits nuevos no pueden estar vacios.
    if count < 1 then return nil, 'Dispositivo v2 sin componentes.' end
    return true
end
