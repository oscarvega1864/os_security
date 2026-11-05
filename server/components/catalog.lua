local util = OSSecurity.Util
local catalog = {}
OSSecurity.ComponentCatalog = catalog

function catalog.compatible(deviceType, slot, componentType, model)
    local config = OSSecurity.ComponentConfig
    local slots = config.Compatibility[deviceType]
    local definition = type(componentType) == 'string' and config.Definitions[componentType]
    return util.text(componentType, 40) and componentType:match('^[%w_%-]+$') ~= nil
        and util.text(model, 64) and model:match('^[%w_.%-]+$') ~= nil
        and type(slot) == 'string' and slots ~= nil and slots[slot] == componentType
        and definition ~= nil and type(model) == 'string' and definition.models[model] ~= nil
end

function catalog.spec(device, slot, model)
    local config = OSSecurity.ComponentConfig
    local slots = config.Compatibility[device.type]
    local componentType = slots and slots[slot]
    local definition = componentType and config.Definitions[componentType]
    if not definition then return nil, 'Slot incompatible con el tipo de dispositivo.' end
    model = model or definition.defaultModel
    if not catalog.compatible(device.type, slot, componentType, model) then return nil, 'Modelo de componente incompatible.' end
    local spec = definition.models[model]
    local result = {
        type = componentType, model = model, quality = spec.quality, lifeHours = spec.lifeHours,
        intensity = config.UsageIntensity, environment = config.EnvironmentFactor,
        installationQuality = device.installation.quality or config.InstallationQuality,
        intervalSeconds = config.IntervalSeconds, maxElapsedHours = config.MaxElapsedHours
    }
    for key, value in pairs(result) do
        if type(value) == 'number' then result[key] = OSSecurity.ComponentWear.number(value) end
    end
    return result
end

function catalog.kit(device)
    local result = {}
    for slot in pairs(OSSecurity.ComponentConfig.Compatibility[device.type] or {}) do
        local spec, err = catalog.spec(device, slot)
        if not spec then return nil, err end
        result[slot] = spec
    end
    return util.copy(result)
end
