-- Pruebas de componentes y mantenimiento; fixtures unicamente en memoria.
local test, fixture, create, transition = StorageTest.test, StorageTest.fixture, StorageTest.create, StorageTest.transition
local equal, util, codec = StorageTest.equal, OSSecurity.Util, OSSecurity.JsonCodec
local validation, lifecycle, wear = OSSecurity.DeviceValidation, OSSecurity.ComponentLifecycle, OSSecurity.ComponentWear

local function close(left, right) assert(math.abs(left - right) < 0.00000001, ('%.12f ~= %.12f'):format(left, right)) end

local function service(c, id, kind, args)
    local result, err = c.registry.service(0, id, kind, args or {})
    assert(result, err)
    return result
end

local function active(c, device)
    for _, state in ipairs({ 'installing', 'installed', 'active' }) do device = transition(c, device.id, state) end
    return device
end

local function configured(change, run)
    local original = OSSecurity.ComponentConfig
    OSSecurity.ComponentConfig = util.copy(original)
    change(OSSecurity.ComponentConfig)
    local ok, err = pcall(run)
    OSSecurity.ComponentConfig = original
    assert(ok, err)
end

local function fast(run)
    configured(function(config) config.Definitions.power_supply.models.power_standard.lifeHours = 100 end, run)
end

local function legacyFiles(files, withData)
    local legacy = {}
    for path, raw in pairs(files) do
        local data = codec.decode(raw)
        data.revision = 0
        for _, d in pairs(data.devices) do
            d.schemaVersion = 1
            d.condition = { components = withData and { old_part = { health = 47, wear = 53, faults = { 'legacy_fault' } } } or {} }
            d.maintenance = { events = withData and { { kind = 'repair', componentId = 'old_part', at = d.createdAt, notes = 'preserve' } } or {} }
            data.revision = data.revision + #d.history
        end
        legacy[path] = codec.encode(data)
    end
    return legacy
end

test('Catalog equips all seven device types with compatible independent components', function()
    local c = fixture()
    for _, deviceType in ipairs(OSSecurity.DeviceCatalog.list()) do
        local d = create(c, deviceType)
        assert(d.schemaVersion == 2)
        local count = 0
        for slot, component in pairs(d.condition.components) do
            count = count + 1
            assert(OSSecurity.ComponentCatalog.compatible(deviceType, slot, component.type, component.model))
            assert(component.health == 100 and component.state == 'healthy' and component.generation == 1)
            assert(component.installedAt == d.createdAt and component.lastMaintenanceAt == nil)
        end
        assert(count >= 2 and validation.device(d, c.limits))
    end
    assert(not OSSecurity.ComponentCatalog.compatible('smart_lock', 'actuator', 'optical_module', 'optics_standard'))
    assert(not OSSecurity.ComponentCatalog.spec(create(c), 'unknown'))
end)

test('Health bounds, derived fault states and incompatible persisted components are validated', function()
    local c = fixture(); local d = create(c)
    for _, health in ipairs({ -1, 101, math.huge, 0 / 0 }) do
        local modified = util.copy(d); modified.condition.components.power.health = health
        assert(not validation.device(modified, c.limits))
    end
    for health, state in pairs({ [100] = 'healthy', [80] = 'healthy', [79] = 'worn', [60] = 'worn',
        [59] = 'degraded', [30] = 'degraded', [29] = 'critical', [0] = 'failed' }) do
        assert(wear.state(health) == state)
    end
    d.condition.components.optics.type = 'lock_actuator'
    assert(not validation.device(d, c.limits))
end)

test('Wear follows active operating time and complete intervals, independent of query frequency', function()
    local c = fixture(); local d = active(c, create(c))
    local writes = c.writes
    c.time = c.time + 59
    service(c, d.id, 'inspect')
    assert(c.writes == writes)
    c.time = c.time + 1
    local inspected = service(c, d.id, 'inspect')
    close(inspected.condition.components.power.wear.operatingHours, 1 / 60)
    close(inspected.condition.components.power.health, 100 - 0.03 / 60)
    service(c, d.id, 'inspect'); assert(c.writes == writes + 1)
    c.time = c.time + 3540
    inspected = service(c, d.id, 'inspect')
    close(inspected.condition.components.power.health, 99.97)
    close(inspected.condition.components.power.wear.operatingHours, 1)
end)

test('Deterministic formula includes intensity, both quality factors and environment', function()
    local c = fixture(); local component = create(c).condition.components.power
    component.quality, component.wear.installationQuality = 100, 100
    component.wear.intensity, component.wear.environment = 1, 1
    local base = wear.rate(component)
    component.quality = 0; close(wear.rate(component), base * 2)
    component.quality = 100; component.wear.installationQuality = 0; close(wear.rate(component), base * 2)
    component.wear.installationQuality = 100; component.wear.intensity = 2; close(wear.rate(component), base * 2)
    component.wear.intensity = 1; component.wear.environment = 3; close(wear.rate(component), base * 3)
    local a, b = util.copy(component), util.copy(component)
    wear.hours(a, 24); wear.hours(b, 12); wear.hours(b, 12)
    close(a.health, b.health)
end)

test('Inactive time is excluded and lifecycle transitions settle partial active intervals', function()
    local c = fixture(); local d = create(c)
    c.time = c.time + 100 * 3600
    assert(service(c, d.id, 'inspect').condition.components.power.health == 100)
    d = active(c, d)
    assert(d.condition.components.power.health == 100)
    c.time = c.time + 30
    d = transition(c, d.id, 'maintenance')
    close(d.condition.components.power.wear.operatingHours, 30 / 3600)
    local health = d.condition.components.power.health
    c.time = c.time + 10 * 3600
    close(service(c, d.id, 'inspect').condition.components.power.health, health)
    transition(c, d.id, 'active'); c.time = c.time + 60
    close(service(c, d.id, 'inspect').condition.components.power.health, health - 0.03 / 60)
end)

test('Long offline time is capped once, discarded time is recorded and clock rollback does not reapply wear', function()
    local c = fixture(); local d = active(c, create(c))
    c.time = c.time + 100000 * 3600
    d = service(c, d.id, 'inspect')
    close(d.condition.components.power.wear.operatingHours, 72)
    close(d.condition.components.power.wear.discardedHours, 100000 - 72)
    local writes = c.writes
    equal(d, service(c, d.id, 'inspect')); assert(c.writes == writes)
    local restarted = fixture(c.files)
    assert(restarted.loaded, restarted.loadError)
    equal(d, service(restarted, d.id, 'inspect'))
    restarted.time = c.time + 3600
    close(service(restarted, d.id, 'inspect').condition.components.power.wear.operatingHours, 73)
end)

test('Existing pieces retain their persisted wear parameters after configuration changes', function()
    local c = fixture(); local d = active(c, create(c))
    configured(function(config) config.UsageIntensity = 5; config.EnvironmentFactor = 5; config.IntervalSeconds = 1 end, function()
        c.time = c.time + 3600
        d = service(c, d.id, 'inspect')
        close(d.condition.components.power.health, 99.97)
        assert(d.condition.components.power.wear.intervalSeconds == 60)
    end)
end)

test('Fractional wear, quality and simulation inputs roundtrip exactly without weakening integrity', function()
    configured(function(config)
        config.Definitions.power_supply.models.power_standard.quality = 80 + 1 / 3
        config.Definitions.power_supply.models.power_standard.lifeHours = 123.456789012345
        config.EnvironmentFactor = 1 + 1 / 7
        config.RepairGain = 25 + 1 / 3
    end, function()
        local c = fixture(); local d = active(c, create(c))
        c.time = c.time + 1
        d = transition(c, d.id, 'maintenance')
        transition(c, d.id, 'active')
        d = service(c, d.id, 'simulate', { hours = 1 / 3 })
        assert(d.maintenance.lastOperation.hours == wear.number(1 / 3))
        local restarted = fixture(c.files); assert(restarted.loaded, restarted.loadError)
        equal(d, restarted.registry.get(0, d.id))
    end)
end)

test('Diagnosis exposes environmental and intensity causes and returns detached data', function()
    configured(function(config) config.UsageIntensity = 2; config.EnvironmentFactor = 3 end, function()
        local c = fixture(); local d = active(c, create(c))
        d = service(c, d.id, 'simulate', { hours = 1 })
        local diagnosis = lifecycle.diagnose(d)
        local causes = table.concat(diagnosis.components.power.causes, ',')
        assert(causes:find('high_intensity', 1, true) and causes:find('environment', 1, true))
        diagnosis.components.power.health = 0
        d.condition.components.power.history[1] = 999
        local stored = c.registry.get(0, d.id)
        assert(stored.condition.components.power.health > 0 and stored.condition.components.power.history[1] == 1)
    end)
end)

test('Controlled simulation validates hours and administrative state without advancing wall-clock anchors', function()
    local c = fixture(); local d = create(c)
    assert(not c.registry.service(0, d.id, 'simulate', { hours = 1 }))
    d = active(c, d)
    for _, hours in ipairs({ 0, -1, 25, math.huge, '1', {} }) do
        assert(not c.registry.service(0, d.id, 'simulate', { hours = hours }))
    end
    d = service(c, d.id, 'simulate', { hours = 24 })
    close(d.condition.components.power.wear.operatingHours, 24)
    assert(d.condition.components.power.wear.lastEvaluatedAt == c.time)
    assert(d.maintenance.events[1].operation.hours == 24)
end)

test('Repair respects gain and ceiling, records results and never changes administrative state', function()
    fast(function()
        local c = fixture(); local d = active(c, create(c))
        d = service(c, d.id, 'simulate', { hours = 24 }); close(d.condition.components.power.health, 64)
        assert(not c.registry.service(0, d.id, 'repair', { slot = 'power' }))
        transition(c, d.id, 'maintenance'); c.time = c.time + 60
        d = service(c, d.id, 'repair', { slot = 'power' }); close(d.condition.components.power.health, 89)
        assert(d.state == 'maintenance' and d.condition.components.power.lastMaintenanceAt == c.time)
        c.time = c.time + 60
        d = service(c, d.id, 'repair', { slot = 'power' }); close(d.condition.components.power.health, 90)
        local writes = c.writes
        assert(not c.registry.service(0, d.id, 'repair', { slot = 'power' }) and c.writes == writes)
        local event = d.maintenance.events[2]
        close(event.changes.power.before.health, 64); close(event.changes.power.after.health, 89)
        assert(event.operation.gain == 25)
        assert(fixture(c.files).loaded)
    end)
end)

test('Failures have deterministic causes and require explicit replacement by default', function()
    configured(function(config) config.Definitions.power_supply.models.power_standard.lifeHours = 1 end, function()
        local c = fixture(); local d = active(c, create(c))
        d = service(c, d.id, 'simulate', { hours = 24 })
        local previousId = d.condition.components.power.id
        assert(d.state == 'active' and d.condition.components.power.state == 'failed')
        local diagnosis = lifecycle.diagnose(d)
        assert(diagnosis.state == 'failed' and table.concat(diagnosis.components.power.causes, ','):find('end_of_service_life', 1, true))
        transition(c, d.id, 'maintenance')
        assert(not c.registry.service(0, d.id, 'repair', { slot = 'power' }))
        assert(not c.registry.service(0, d.id, 'replace', { slot = 'power', model = 'optics_standard' }))
        assert(not c.registry.service(0, d.id, 'replace', { slot = 'unknown' }))
        d = service(c, d.id, 'replace', { slot = 'power' })
        local replaced = d.condition.components.power
        assert(replaced.health == 100 and replaced.generation == 2 and replaced.id ~= previousId)
        assert(replaced.wear.operatingHours == 0 and replaced.lastMaintenanceAt == c.time)
        assert(#replaced.history == 1 and d.maintenance.events[2].changes.power.before.id == previousId)
        assert(d.maintenance.events[1].changes.power.after.id == previousId)
        assert(d.state == 'maintenance')
        assert(fixture(c.files).loaded)
    end)
end)

test('Retirement remains terminal and service never replaces failed pieces automatically', function()
    local c = fixture(); local d = active(c, create(c))
    d = transition(c, d.id, 'retired')
    local writes = c.writes
    for kind, args in pairs({ simulate = { hours = 1 }, repair = { slot = 'power' }, replace = { slot = 'power' }, provision = {} }) do
        assert(not c.registry.service(0, d.id, kind, args))
    end
    equal(d, service(c, d.id, 'inspect')); assert(c.writes == writes)
    assert(not c.registry.setState(0, d.id, 'active'))
end)

test('Service queries and mutations enforce ACE and reject arbitrary objects', function()
    local c = fixture(); local d = active(c, create(c))
    local writes = c.writes
    for _, kind in ipairs({ 'inspect', 'provision', 'simulate', 'repair', 'replace' }) do
        assert(not c.registry.service(9, d.id, kind, {}))
    end
    assert(not c.registry.serviceHistory(9, d.id))
    assert(not c.registry.service(0, d.id, 'repair', { slot = 'power', health = 100 }))
    assert(not c.registry.service(0, d.id, 'simulate', { hours = 1, at = 0 }))
    assert(not c.registry.service(0, d.id, 'unknown', {}))
    assert(not c.registry.service(0, d.id, 'inspect', setmetatable({}, {})))
    assert(c.writes == writes)
    assert(c.registry.service(7, d.id, 'inspect', {}))
end)

test('History is paginated, retains part identities/results and never truncates on capacity', function()
    local limits = util.copy(OSSecurity.ServerConfig); limits.MaxMaintenanceEvents = 2
    local c = fixture(nil, limits); local d = active(c, create(c))
    service(c, d.id, 'simulate', { hours = 1 }); service(c, d.id, 'simulate', { hours = 1 })
    local page = assert(c.registry.serviceHistory(0, d.id, 1, 1))
    assert(page.total == 2 and #page.items == 1 and page.items[1].operation.hours == 1)
    assert(not c.registry.service(0, d.id, 'simulate', { hours = 1 }))
    c.time = c.time + 3600
    assert(service(c, d.id, 'inspect')) -- el desgaste no consume intervenciones
    assert(#c.registry.get(0, d.id).maintenance.events == 2)
    assert(not c.registry.serviceHistory(0, d.id, -1, 1))
    assert(not c.registry.serviceHistory(0, d.id, 0, 101))
    assert(c.registry.retire(0, d.id))
end)

test('Legacy snapshots load without writes and promote explicitly with every legacy field preserved', function()
    local original = fixture(); local d = create(original, 'bodycam', { owner = 'owner', vehicleId = 'vehicle' })
    local files = legacyFiles(original.files, true)
    local c = fixture(files)
    assert(c.loaded and c.writes == 0)
    local before = assert(c.registry.get(0, d.id)); assert(before.schemaVersion == 1)
    assert(not c.registry.service(0, d.id, 'inspect', {}))
    c.time = c.time + 60
    local migrated = service(c, d.id, 'provision')
    assert(migrated.schemaVersion == 2 and migrated.id == before.id and migrated.owner == before.owner)
    assert(migrated.createdAt == before.createdAt and migrated.vehicleId == before.vehicleId)
    equal(migrated.history, before.history)
    equal(migrated.maintenance.legacy.components, before.condition.components)
    equal(migrated.maintenance.legacy.events, before.maintenance.events)
    local history = assert(c.registry.serviceHistory(0, d.id))
    assert(history.total == 2 and history.legacyEvents == 1 and history.items[1].legacy == true)
    assert(history.items[1].notes == 'preserve' and history.items[2].kind == 'provision')
    assert(not c.registry.service(0, d.id, 'provision', {}))
    local restarted = fixture(c.files); assert(restarted.loaded, restarted.loadError)
    equal(migrated, restarted.registry.get(0, d.id))
    assert(create(restarted).id ~= d.id)
end)

test('Both legacy snapshots remain compatible through migration and subsequent lifecycle/service operations', function()
    local base = fixture(); local d = active(base, create(base))
    local c = fixture(legacyFiles(base.files, true))
    assert(c.loaded, c.loadError)
    assert(not c.registry.service(0, d.id, 'provision', {}))
    transition(c, d.id, 'maintenance'); service(c, d.id, 'provision')
    transition(c, d.id, 'active'); service(c, d.id, 'simulate', { hours = 1 })
    local restarted = fixture(c.files); assert(restarted.loaded, restarted.loadError)
    assert(restarted.registry.get(0, d.id).schemaVersion == 2)
end)

test('Failed migration never publishes a new schema or overwrites the confirmed legacy slot', function()
    local base = fixture(); local d = create(base)
    local c = fixture(legacyFiles(base.files, true))
    local before = c.files['data/devices.a.json']
    c.writeFailure = true
    assert(not c.registry.service(0, d.id, 'provision', {}))
    assert(c.files['data/devices.a.json'] == before and not c.registry.status())
    local restarted = fixture(c.files); assert(restarted.loaded)
    assert(restarted.registry.get(0, d.id).schemaVersion == 1)
end)

test('Service write failures preserve the last confirmed health and history after reload', function()
    fast(function()
        for _, kind in ipairs({ 'simulate', 'repair', 'replace', 'inspect' }) do
            local c = fixture(); local d = active(c, create(c))
            d = service(c, d.id, 'simulate', { hours = 24 })
            if kind == 'repair' or kind == 'replace' then d = transition(c, d.id, 'maintenance') end
            local before = util.copy(d)
            c.time = c.time + 3600; c.writeFailure = true
            assert(not c.registry.service(0, d.id, kind, kind == 'simulate' and { hours = 1 }
                or ((kind == 'repair' or kind == 'replace') and { slot = 'power' } or {})))
            assert(not c.registry.status())
            local restarted = fixture(c.files); assert(restarted.loaded, restarted.loadError)
            equal(before, restarted.registry.get(0, d.id))
        end
    end)
end)

test('Storage rejects forged health, receipts, event history and component substitution', function()
    fast(function()
        local c = fixture(); local d = active(c, create(c))
        service(c, d.id, 'simulate', { hours = 24 })
        local latest = codec.decode(c.files['data/devices.a.json'])
        local other = codec.decode(c.files['data/devices.b.json'])
        if other.revision > latest.revision then latest = other end
        local previousWrites = c.writes
        local forged = util.copy(latest)
        forged.revision = forged.revision + 1
        local device = forged.devices[d.id]
        device.maintenance.sequence = device.maintenance.sequence + 1
        device.maintenance.lastOperation = { kind = 'inspect', at = device.updatedAt }
        device.condition.components.power.health = 100
        device.condition.components.power.state = 'healthy'
        assert(validation.snapshot(forged, c.limits))
        assert(not c.store.save(forged) and c.writes == previousWrites)
        local corrupted = util.copy(latest)
        corrupted.devices[d.id].maintenance.events[1].changes.power.after.health = 101
        assert(not validation.snapshot(corrupted, c.limits))
        corrupted = util.copy(latest)
        corrupted.devices[d.id].condition.components.power.history[1] = 999
        assert(not validation.snapshot(corrupted, c.limits))
    end)
end)

test('Maintenance command parsing rejects unauthorized and malformed requests and preserves old commands', function()
    local c = fixture(); local d = active(c, create(c))
    local handler, replies = nil, {}
    OSSecurity.MaintenanceCommands.register({
        registry = c.registry, permissions = c.permissions, defaultPageSize = 20,
        register = function(name, callback, restricted) assert(name == 'osmaint' and restricted == false); handler = callback end,
        reply = function(source, message) replies[#replies + 1] = { source, message } end
    })
    local writes = c.writes
    handler(9, { 'simulate', d.id, '1' }); assert(c.writes == writes)
    handler(0, { 'simulate', d.id, 'bad' }); assert(c.writes == writes)
    handler(0, { 'simulate', d.id, '25' }); assert(c.writes == writes)
    handler(0, { 'list', d.id }); handler(0, { 'inspect', d.id }); handler(0, { 'diagnose', d.id })
    handler(0, { 'simulate', d.id, '1' }); assert(c.writes == writes + 1)
    handler(0, { 'history', d.id, '0', '1' })
    handler(0, { 'history', d.id, 'bad' })
    handler(0, { 'replace', d.id, 'power', 'unknown' }); assert(c.writes == writes + 1)
    handler(0, { 'repair', d.id, 'power', 'extra' }); assert(c.writes == writes + 1)
    handler(7, { 'list', d.id }); assert(replies[#replies][1] == 7)
end)
