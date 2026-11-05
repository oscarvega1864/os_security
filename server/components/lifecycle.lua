local util, wear, catalog = OSSecurity.Util, OSSecurity.ComponentWear, OSSecurity.ComponentCatalog
local lifecycle = {}
OSSecurity.ComponentLifecycle = lifecycle

function lifecycle.newComponent(deviceId, slot, generation, spec, at)
    return {
        id = ('%s:%s:%d'):format(deviceId, slot, generation), generation = generation,
        type = spec.type, model = spec.model, quality = spec.quality,
        health = 100, state = 'healthy', installedAt = at,
        expectedLifetimeHours = spec.lifeHours, history = {},
        wear = { intensity = spec.intensity, environment = spec.environment,
            installationQuality = spec.installationQuality, intervalSeconds = spec.intervalSeconds,
            maxElapsedHours = spec.maxElapsedHours, lastEvaluatedAt = at,
            operatingHours = 0, discardedHours = 0 }
    }
end

function lifecycle.initialize(device, kit, at)
    device.schemaVersion = 2
    device.condition = { components = {} }
    device.maintenance = { sequence = 0, events = {}, legacy = { components = {}, events = {} } }
    for slot, spec in pairs(kit) do
        device.condition.components[slot] = lifecycle.newComponent(device.id, slot, 1, spec, at)
    end
end

function lifecycle.operation(device, kind, args, at)
    local config = OSSecurity.ComponentConfig
    local allowed = {
        inspect = {}, provision = {}, simulate = { hours = true },
        repair = { slot = true }, replace = { slot = true, model = true }
    }
    if type(kind) ~= 'string' or not allowed[kind] or not util.object(args, allowed[kind]) then
        return nil, 'Operacion o argumentos de mantenimiento invalidos.'
    end
    local op = { kind = kind, at = at }
    if kind == 'provision' then
        if device.schemaVersion ~= 1 then return nil, 'El dispositivo ya esta equipado.' end
        local kit, err = catalog.kit(device)
        if not kit then return nil, err end
        op.kit = kit
    elseif kind == 'simulate' then
        if not util.finite(config.MaxSimulationHours) or config.MaxSimulationHours <= 0 then
            return nil, 'Limite de simulacion configurado invalido.'
        end
        if not util.finite(args.hours) or args.hours <= 0 or args.hours > math.min(72, config.MaxSimulationHours) then
            return nil, 'Horas fuera del limite de simulacion configurado.'
        end
        op.hours = wear.number(args.hours)
    elseif kind == 'repair' or kind == 'replace' then
        if not util.text(args.slot, 40) then return nil, 'Slot de componente invalido.' end
        op.slot = args.slot
        if kind == 'repair' then
            op.gain, op.ceiling, op.allowFailed = wear.number(config.RepairGain), wear.number(config.RepairCeiling), config.AllowFailedRepair
        else
            local spec, err = catalog.spec(device, args.slot, args.model)
            if not spec then return nil, err end
            op.spec = spec
        end
    end
    return op
end

local function summary(component)
    return { id = component.id, type = component.type, model = component.model,
        state = component.state, health = component.health, installedAt = component.installedAt,
        operatingHours = component.wear.operatingHours }
end

function lifecycle.apply(device, op, limits)
    local valid, err = OSSecurity.ComponentValidation.operation(device, op)
    if not valid then return nil, err end
    if op.at < device.updatedAt then return nil, 'Marca temporal de servicio anterior al dispositivo.' end
    if op.kind == 'provision' and device.schemaVersion ~= 1 then return nil, 'El dispositivo ya esta equipado.' end
    if device.state == 'retired' and op.kind ~= 'inspect' then return nil, 'Un dispositivo retirado no admite intervenciones.' end
    if op.kind == 'provision' and not ({ registered = true, installed = true, maintenance = true })[device.state] then
        return nil, 'Equipar requiere registered, installed o maintenance.'
    end
    if op.kind ~= 'provision' and device.schemaVersion ~= 2 then return nil, 'Esquema antiguo: ejecutar osmaint provision <id>.' end
    if (op.kind == 'repair' or op.kind == 'replace') and device.state ~= 'maintenance' then
        return nil, 'Reparar o sustituir requiere el estado administrativo maintenance.'
    end
    if op.kind == 'simulate' and device.state ~= 'active' then return nil, 'La simulacion requiere un dispositivo active.' end

    local updated = util.copy(device)
    if op.kind == 'provision' then
        updated = assert(OSSecurity.ComponentMigration.promote(device))
        for slot, spec in pairs(op.kit) do
            updated.condition.components[slot] = lifecycle.newComponent(device.id, slot, 1, spec, op.at)
        end
    else
        wear.settle(updated, op.at, op.kind == 'repair' or op.kind == 'replace')
    end
    local components = updated.condition.components
    local event = { kind = op.kind, at = op.at, sequence = updated.maintenance.sequence + 1,
        operation = util.copy(op), changes = {} }
    if op.kind == 'simulate' then
        for _, component in pairs(components) do wear.hours(component, op.hours) end
    elseif op.kind == 'repair' then
        local component = components[op.slot]
        if not component then return nil, 'Componente no encontrado.' end
        if component.health == 0 and not op.allowFailed then return nil, 'Pieza failed: requiere sustitucion.' end
        local health = wear.number(math.min(op.ceiling, component.health + op.gain))
        if health <= component.health then return nil, 'La reparacion no mejoraria la salud dentro del limite.' end
        component.health, component.state = health, wear.state(health)
        component.lastMaintenanceAt = op.at
    elseif op.kind == 'replace' then
        local previous = components[op.slot]
        if not previous then return nil, 'Componente no encontrado.' end
        components[op.slot] = lifecycle.newComponent(device.id, op.slot, previous.generation + 1, op.spec, op.at)
        components[op.slot].lastMaintenanceAt = op.at
    end
    if op.kind == 'inspect' and util.equal(device, updated) then return updated end
    if op.kind ~= 'inspect' then
        if #updated.maintenance.events >= limits.MaxMaintenanceEvents then return nil, 'Historial de intervenciones completo; no se truncara.' end
        local index = #updated.maintenance.events + 1
        for slot, component in pairs(components) do
            if op.slot == nil or op.slot == slot then
                local previous = device.schemaVersion == 2 and device.condition.components[slot] or nil
                event.changes[slot] = { before = previous and summary(previous) or nil, after = summary(component) }
                component.history[#component.history + 1] = index
            end
        end
        updated.maintenance.events[index] = event
    end
    updated.updatedAt = op.at
    updated.maintenance.sequence = updated.maintenance.sequence + 1
    updated.maintenance.lastOperation = util.copy(op)
    return updated
end

function lifecycle.onStateChange(device, at)
    local updated = util.copy(device)
    if device.schemaVersion == 2 then wear.settle(updated, at, true) end
    return updated
end

function lifecycle.diagnose(device)
    local report = { health = nil, state = nil, components = {} }
    if device.schemaVersion ~= 2 then return report end
    for slot, component in pairs(device.condition.components) do
        report.health = math.min(report.health or 100, component.health)
        report.components[slot] = { id = component.id, health = component.health, state = component.state,
            operatingHours = component.wear.operatingHours, ratePerHour = wear.rate(component),
            causes = wear.causes(component), discardedHours = component.wear.discardedHours }
    end
    report.state = report.health and wear.state(report.health) or nil
    return report
end
