-- Logica pura. Parametros persistidos por pieza: no dependen de FPS ni de
-- cambios posteriores del catalogo. Vida util nominal en condiciones optimas.
local wear = {}
OSSecurity.ComponentWear = wear

-- dkjson usa 14 cifras significativas. Canonizar los escalares nuevos a 12
-- antes de persistir permite una ida/vuelta exacta sin relajar la integridad.
function wear.number(value)
    if not OSSecurity.Util.finite(value) then return value end
    return tonumber(('%.12g'):format(value))
end

function wear.state(health)
    if health <= 0 then return 'failed' end
    if health < 30 then return 'critical' end
    if health < 60 then return 'degraded' end
    if health < 80 then return 'worn' end
    return 'healthy'
end

function wear.rate(component)
    local params = component.wear
    return (100 / component.expectedLifetimeHours) * params.intensity * params.environment
        * (2 - params.installationQuality / 100) * (2 - component.quality / 100)
end

function wear.causes(component)
    if component.wear.operatingHours == 0 then return {} end
    local causes = { 'operating_time' }
    if component.wear.intensity > 1 then causes[#causes + 1] = 'high_intensity' end
    if component.wear.environment > 1 then causes[#causes + 1] = 'environment' end
    if component.wear.installationQuality < 100 then causes[#causes + 1] = 'installation_quality' end
    if component.quality < 100 then causes[#causes + 1] = 'component_quality' end
    if component.health == 0 then causes[#causes + 1] = 'end_of_service_life' end
    return causes
end

function wear.hours(component, hours)
    component.health = wear.number(math.max(0, math.min(100, component.health - hours * wear.rate(component))))
    component.wear.operatingHours = wear.number(component.wear.operatingHours + hours)
    component.state = wear.state(component.health)
end

function wear.settle(device, at, force)
    for _, component in pairs(device.condition.components) do
        local params = component.wear
        local elapsed = math.max(0, at - params.lastEvaluatedAt)
        if device.state == 'active' then
            local seconds = force and elapsed or math.floor(elapsed / params.intervalSeconds) * params.intervalSeconds
            if seconds > 0 then
                local applied = math.min(seconds, params.maxElapsedHours * 3600)
                wear.hours(component, applied / 3600)
                params.discardedHours = wear.number(params.discardedHours + (seconds - applied) / 3600)
                -- Descartar el exceso una sola vez; las consultas no lo recuperan.
                params.lastEvaluatedAt = seconds > applied and at or params.lastEvaluatedAt + seconds
            end
        end
        if force then params.lastEvaluatedAt = math.max(params.lastEvaluatedAt, at) end
    end
    return device
end
