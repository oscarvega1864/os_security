local test, coreFixture, create, equal = StorageTest.test, StorageTest.fixture, StorageTest.create, StorageTest.equal
local util, config, codec = OSSecurity.Util, OSSecurity.GameplayConfig, OSSecurity.JsonCodec
local bootNumber = 0

local function fixture(files)
    bootNumber = bootNumber + 1
    local core = coreFixture(files)
    local c = { core = core, players = {}, aces = {}, commands = {}, audit = {}, replies = {}, invWrites = 0, timers = {} }
    local prefix = 'boot-' .. bootNumber
    for id = 1, 5 do
        c.players[id] = { principal = 'license:' .. string.rep(string.char(96 + id), 40), alive = true, connected = true,
            point = { x = 0, y = 0, z = 1 }, bucket = 0, visibleName = 'Same display name' }
        c.aces[id] = {}
    end
    c.aces[1][config.Ace.operations], c.aces[1][config.Ace.technician] = true, true
    c.aces[2][config.Ace.client] = true
    c.aces[3][config.Ace.operations], c.aces[3][config.Ace.supervisor] = true, true
    c.aces[4][config.Ace.operations], c.aces[4][config.Ace.admin] = true, true
    c.game = OSSecurity.Gameplay.new({
        registry = core.registry, permissions = { isAdmin = function(source) return source == 0 or source == 4 end },
        files = {
            read = function(path) return core.files[path] end,
            write = function(path, content)
                c.invWrites = c.invWrites + 1
                if c.failInvAt == c.invWrites or c.failInventory then
                    if c.partial then core.files[path] = '{partial' end
                    if c.completeInventoryWriteBeforeError then core.files[path] = content end
                    return false
                end
                core.files[path] = content; return true
            end
        },
        now = function() return core.time end,
        connected = function(source) return c.players[source] and c.players[source].connected end,
        identifier = function(source) return c.players[source] and c.players[source].principal end,
        alive = function(source) return c.players[source] and c.players[source].alive and c.players[source].connected end,
        ace = function(source, ace) return c.aces[source] and c.aces[source][ace] == true end,
        world = function(source)
            local player = c.players[source]
            if not player or not player.connected or player.noWorld then return nil, nil end
            return util.copy(player.point), player.bucket
        end,
        token = function(source, counter) return prefix .. ':' .. source .. ':' .. counter end,
        employeeId = function() return 'G6-E-TEST' end,
        register = function(name, callback, restricted) assert(name == 'osg6' and restricted == false); c.commands[name] = callback end,
        reply = function(source, message) c.replies[#c.replies + 1] = { source, message } end,
        audit = function(action, source, device) c.audit[#c.audit + 1] = { action, source, device } end,
        log = function(message) c.replies[#c.replies + 1] = { 0, message } end,
        schedule = function(callback) c.timers[#c.timers + 1] = callback end
    })
    c.loaded, c.loadError = c.game.load()
    return c
end

local function grant(c, source, item, amount)
    local result, err = c.game.inventory.apply({ kind = 'grant', principal = c.players[source].principal, item = item, amount = amount or 1 })
    assert(result, err)
end
local function kit(c)
    grant(c, 1, 'g6_operations_tablet'); grant(c, 1, 'os_cctv_kit', 2); grant(c, 1, 'os_battery', 2)
    grant(c, 1, 'os_drill'); grant(c, 1, 'os_screwdriver')
end
local function anchor(c, id, source)
    local result, err = c.game.inventory.apply({ kind = 'anchor', anchor = {
        id = id or 'mount_1', owner = c.players[2].principal, installer = c.players[source or 1].principal,
        position = { x = 1, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0 }, radius = 0.75, bucket = 0
    } })
    assert(result, err)
end
local nextRequest = 0
local function open(c, source, kind)
    nextRequest = nextRequest + 1
    local response = c.game.handle(source, { id = nextRequest, action = 'open', args = { kind = kind } })
    assert(response.ok, response.error)
    return response.session
end
local function call(c, source, session, action, args)
    nextRequest = nextRequest + 1; session.sequence = session.sequence + 1
    return c.game.handle(source, { id = nextRequest, action = action, token = session.token, sequence = session.sequence, args = args or {} })
end
local function proposal(id)
    return { anchorId = id or 'mount_1', position = { x = 1, y = 0, z = 1 }, rotation = { x = 0, y = 0, z = 90 } }
end
local function count(c, source, item)
    local account = assert(c.game.inventory.get(c.players[source].principal))
    return account.items[item] and account.items[item].count or 0
end
local function grantAccess(c, source, deviceId, role)
    assert(c.game.inventory.apply({ kind = 'access', principal = c.players[source].principal, deviceId = deviceId, role = role }))
end

test('Inventory persists separately; distinct tablets are not interchangeable and metadata is bounded', function()
    local c = fixture(); assert(c.loaded and c.invWrites == 0)
    grant(c, 2, 'g6_client_tablet')
    assert(count(c, 2, 'g6_client_tablet') == 1 and count(c, 2, 'g6_operations_tablet') == 0)
    assert(not c.game.inventory.apply({ kind = 'grant', principal = c.players[2].principal, item = 'unknown', amount = 1 }))
    assert(not c.game.inventory.apply({ kind = 'grant', principal = c.players[2].principal, item = 'os_battery', amount = 101 }))
    assert(not c.game.inventory.apply({ kind = 'grant', principal = c.players[2].principal, item = 'os_battery', amount = 1, role = 'admin' }))
    assert(coreFixture(c.core.files).loaded) -- los archivos de inventario no interfieren con Device Core
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
    assert(count(restarted, 2, 'g6_client_tablet') == 1)
end)

test('Server identity uses validated license identifiers and never display names', function()
    local c = fixture(); local p1 = assert(c.game.identity.resolve(1)); local p2 = assert(c.game.identity.resolve(2))
    assert(c.players[1].visibleName == c.players[2].visibleName and p1 ~= p2)
    c.players[1].principal = 'Same display name'; assert(not c.game.identity.resolve(1))
    assert(not c.game.identity.resolve(0) and not c.game.identity.resolve('2'))
    c.players[2].connected = false; assert(not c.game.identity.resolve(2))
end)

test('Opening tablets requires the matching item, explicit ACE and verified professional profile', function()
    local c = fixture()
    local function denied(source, kind)
        nextRequest = nextRequest + 1
        assert(not c.game.handle(source, { id = nextRequest, action = 'open', args = { kind = kind } }).ok)
    end
    denied(2, 'client'); grant(c, 2, 'g6_client_tablet'); open(c, 2, 'client'); denied(2, 'operations')
    grant(c, 5, 'g6_operations_tablet'); c.aces[5][config.Ace.operations] = true; denied(5, 'operations')
    c.aces[5][config.Ace.technician] = true; open(c, 5, 'operations')
    c.core.time = c.core.time + 10
    grant(c, 1, 'g6_client_tablet'); denied(1, 'client')
end)

test('Sessions bind source, sequence, expiry and live permissions; switching tablet invalidates the previous one', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet')
    local session = open(c, 2, 'client')
    assert(not call(c, 1, session, 'devices', { offset = 0 }).ok)
    session.sequence = 0
    assert(call(c, 2, session, 'devices', { offset = 0 }).ok)
    nextRequest = nextRequest + 1
    assert(not c.game.handle(2, { id = nextRequest, action = 'devices', token = session.token, sequence = 1, args = { offset = 0 } }).ok)
    local old = util.copy(session)
    c.core.time = c.core.time + 10
    local current = open(c, 2, 'inventory')
    assert(not call(c, 2, old, 'devices', {}).ok)
    assert(call(c, 2, current, 'inventory').ok)
    c.core.time = c.core.time + config.SessionSeconds + 1
    assert(not call(c, 2, current, 'inventory').ok)
    c.core.time = c.core.time + 10
    session = open(c, 2, 'client'); c.aces[2][config.Ace.client] = false
    assert(not call(c, 2, session, 'devices', {}).ok)
end)

test('Client tablets receive only owned/granted devices, never global records or private principals', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet')
    local own = create(c.core, 'cctv_camera', { owner = c.players[2].principal })
    local hidden = create(c.core, 'bodycam', { owner = c.players[5].principal })
    local session = open(c, 2, 'client')
    local response = call(c, 2, session, 'devices', { offset = 0 })
    assert(response.ok and response.data.total == 1 and response.data.items[1].id == own.id)
    assert(not codec.encode(response):find('license:', 1, true))
    assert(response.data.items[1].remoteVideo == false)
    assert(not call(c, 2, session, 'device', { deviceId = hidden.id }).ok)
    assert(not call(c, 2, session, 'maintain', { deviceId = own.id, action = 'inspect' }).ok)
    grantAccess(c, 2, hidden.id, 'client')
    assert(call(c, 2, session, 'devices', { offset = 0 }).data.total == 2)
    grantAccess(c, 2, hidden.id, 'none'); assert(not call(c, 2, session, 'device', { deviceId = hidden.id }).ok)
end)

test('Technician and supervisor permissions intersect their assigned device scope', function()
    local c = fixture(); grant(c, 1, 'g6_operations_tablet'); grant(c, 3, 'g6_operations_tablet')
    local device = create(c.core, 'cctv_camera')
    local tech, supervisor = open(c, 1, 'operations'), open(c, 3, 'operations')
    assert(call(c, 1, tech, 'devices', {}).data.total == 0)
    grantAccess(c, 1, device.id, 'technician'); grantAccess(c, 3, device.id, 'supervisor')
    assert(call(c, 1, tech, 'maintain', { deviceId = device.id, action = 'inspect' }).ok)
    assert(not call(c, 1, tech, 'maintain', { deviceId = device.id, action = 'beginMaintenance' }).ok)
    assert(not call(c, 3, supervisor, 'maintain', { deviceId = device.id, action = 'repair', slot = 'power' }).ok)
    local leaked = call(c, 1, tech, 'device', { deviceId = device.id, role = 'admin' })
    assert(not leaked.ok)
end)

test('Administrative grants target connected identities, reject public use and validate anchors', function()
    local c = fixture()
    c.commands.osg6(5, { 'give', '2', 'g6_client_tablet', '1' }); assert(count(c, 2, 'g6_client_tablet') == 0)
    c.commands.osg6(0, { 'give', '2', 'g6_client_tablet', '1' }); assert(count(c, 2, 'g6_client_tablet') == 1)
    c.commands.osg6(0, { 'give', '99', 'g6_operations_tablet', '1' })
    c.commands.osg6(0, { 'anchor', 'a', '2', '1', '1', '0', '1', '-1', '0', '0', '.75' })
    assert(c.game.inventory.snapshot().anchors.a)
    c.commands.osg6(0, { 'anchor', 'bad', '2', '1', '1', '0', '1', '0', '0', '0' })
    assert(not c.game.inventory.snapshot().anchors.bad)
    assert(not codec.encode(c.replies):find('license:', 1, true))
end)

test('Valid placement reserves once, creates real core state/components and consumes only materials', function()
    local c = fixture(); kit(c); anchor(c)
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local response = call(c, 1, session, 'place_confirm', proposal())
    assert(response.ok, response.error)
    assert(count(c, 1, 'os_cctv_kit') == 1 and count(c, 1, 'os_battery') == 1)
    assert(count(c, 1, 'os_drill') == 1 and count(c, 1, 'os_screwdriver') == 1)
    assert(count(c, 1, 'g6_operations_tablet') == 1)
    local device = assert(c.core.registry.get(0, response.data.id))
    assert(device.type == 'cctv_camera' and device.state == 'active' and device.schemaVersion == 2)
    assert(device.owner == c.players[2].principal and device.position.x == .98 and device.metadata.installationId == response.data.installationId)
    assert(device.condition.components.power and device.condition.components.optics)
    assert(call(c, 1, session, 'devices', {}).data.total == 1)
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(c.core.registry.list(0).total == 1 and count(c, 1, 'os_cctv_kit') == 1)
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
    assert(restarted.core.registry.list(0).total == 1 and count(restarted, 1, 'os_cctv_kit') == 1)
end)

test('Placement rejects missing tools, foreign mounts, out-of-plane coordinates, distance and bucket changes', function()
    local c = fixture(); grant(c, 1, 'g6_operations_tablet'); grant(c, 1, 'os_cctv_kit'); anchor(c)
    local session = open(c, 1, 'operations'); assert(not call(c, 1, session, 'place_begin').ok)
    for _, item in ipairs({ 'os_drill', 'os_screwdriver', 'os_battery' }) do grant(c, 1, item) end
    local cases = {
        function(p) p.anchorId = 'foreign' end,
        function(p) p.position.x = .5 end,
        function(p) p.position.z = math.huge end,
        function(p) p.rotation.x = 100 end,
        function() c.players[1].bucket = 1 end,
        function() c.players[1].point.x = -20 end
    }
    for _, change in ipairs(cases) do
        c.players[1].bucket = 0; c.players[1].point = { x = 0, y = 0, z = 1 }
        assert(call(c, 1, session, 'place_begin').ok)
        local p = proposal(); change(p)
        assert(not call(c, 1, session, 'place_confirm', p).ok)
    end
    assert(count(c, 1, 'os_cctv_kit') == 1 and c.core.registry.list(0).total == 0)
end)

test('Cancellation, death, timeout and disconnect invalidate placement without consuming materials', function()
    local c = fixture(); kit(c); anchor(c)
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    assert(call(c, 1, session, 'place_cancel').ok)
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(call(c, 1, session, 'place_begin').ok)
    c.players[1].alive = false
    local timer = table.remove(c.timers, 1); timer()
    c.players[1].alive = true
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    c.core.time = c.core.time + 10; session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.game.drop(1)
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    c.core.time = c.core.time + 10; session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok); c.core.time = c.core.time + config.PlacementSeconds + 1
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(count(c, 1, 'os_cctv_kit') == 2)
end)

test('Inventory reserve failure never creates a device or confirms consumption', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.failInventory = true
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(c.core.registry.list(0).total == 0 and not c.game.inventory.status())
    local restarted = fixture(c.core.files); assert(restarted.loaded)
    assert(count(restarted, 1, 'os_cctv_kit') == 2)
end)

test('Definite core creation rejection compensates the persisted reservation', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local original = c.core.registry.create
    c.core.registry.create = function() return nil, 'Injected validation rejection' end
    local response = call(c, 1, session, 'place_confirm', proposal())
    c.core.registry.create = original
    assert(not response.ok and count(c, 1, 'os_cctv_kit') == 2)
    assert(c.game.inventory.snapshot().installations.g6i_0000000001.status == 'cancelled')
end)

test('Ambiguous core write failure keeps materials held until recovery instead of duplicating them', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.core.writeFailure, c.core.completeWriteBeforeError = true, true
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(count(c, 1, 'os_cctv_kit') == 1 and not c.core.registry.status())
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
    assert(restarted.core.registry.list(0).total == 1 and count(restarted, 1, 'os_cctv_kit') == 1)
    assert(restarted.game.inventory.snapshot().installations.g6i_0000000001.status == 'committed')
end)

test('Final inventory save failure recovers the correlated device exactly once', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.failInvAt = c.invWrites + 2 -- reserva correcta, confirmacion final rechazada
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(c.core.registry.list(0).total == 1)
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
    assert(restarted.core.registry.list(0).total == 1 and count(restarted, 1, 'os_cctv_kit') == 1)
    assert(fixture(restarted.core.files).core.registry.list(0).total == 1)
end)

test('Orphan reservation with no core write is refunded once on restart', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.core.writeFailure = true -- no bytes written by fixture
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    local restarted = fixture(c.core.files); assert(restarted.loaded)
    assert(count(restarted, 1, 'os_cctv_kit') == 2 and restarted.core.registry.list(0).total == 0)
    local twice = fixture(restarted.core.files); assert(count(twice, 1, 'os_cctv_kit') == 2)
end)

test('Corrupt inventory blocks gameplay and preserves the last bytes without touching core snapshots', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet')
    local coreBefore = util.copy(c.core.files)
    c.core.files['data/inventory.a.json'] = '{corrupt'
    local restarted = fixture(c.core.files)
    assert(not restarted.loaded and restarted.core.registry.status())
    assert(restarted.core.files['data/inventory.a.json'] == '{corrupt')
    assert(restarted.core.files['data/devices.a.json'] == coreBefore['data/devices.a.json'])
    assert(not restarted.game.handle(2, { id = 1, action = 'open', args = { kind = 'client' } }).ok)
end)

test('Malformed mounting data in a pending snapshot blocks recovery without exceptions or writes', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.core.writeFailure = true
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    local invalid = assert(c.game.inventory.snapshot())
    invalid.anchors.mount_1 = true
    local encoded = codec.encode(invalid)
    local files = { ['data/inventory.a.json'] = encoded }
    local restarted = fixture(files)
    assert(not restarted.loaded and restarted.invWrites == 0)
    assert(files['data/inventory.a.json'] == encoded and not files['data/inventory.b.json'])
end)

test('Physical props are streamed only by server proximity/bucket with no private device data', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok); assert(call(c, 1, session, 'place_confirm', proposal()).ok)
    local list = assert(c.game.placement.stream(5)); assert(#list == 1)
    local raw = codec.encode(list); assert(not raw:find('license:', 1, true) and not raw:find('health', 1, true))
    c.players[5].point.x = 1000; assert(#c.game.placement.stream(5) == 0)
    c.players[5].point.x = 0; c.players[5].bucket = 1; assert(#c.game.placement.stream(5) == 0)
    assert(c.core.registry.retire(0, list[1].id)); assert(#c.game.placement.stream(1) == 0)
end)

test('Server rejects forged roles, arbitrary account substitution and reordered/replayed mutations', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    assert(not call(c, 2, session, 'devices', { offset = 0, role = 'admin' }).ok)
    assert(not call(c, 2, session, 'grant', { principal = c.players[1].principal, item = 'g6_operations_tablet', amount = 100 }).ok)
    assert(not call(c, 2, session, 'use', { item = 'g6_operations_tablet' }).ok)
    local snapshot = assert(c.game.inventory.snapshot())
    local forged = util.copy(snapshot); forged.revision = forged.revision + 1
    forged.accounts[c.players[2].principal].items.g6_operations_tablet = { count = 1, metadata = {} }
    assert(not OSSecurity.InventoryState.successor(snapshot, forged, config))
end)

test('A live session is revoked when identity or item possession changes', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    c.players[2].principal = c.players[5].principal
    assert(not call(c, 2, session, 'inventory').ok)
    c.players[2].principal = 'license:' .. string.rep('b', 40); c.core.time = c.core.time + 10
    session = open(c, 2, 'client')
    local original = c.game.inventory.has
    c.game.inventory.has = function() return false end
    assert(not call(c, 2, session, 'devices', {}).ok)
    c.game.inventory.has = original
end)

test('Rate limits and explicit page bounds reject excessive requests without exposing global data', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    assert(not call(c, 2, session, 'devices', { offset = false }).ok)
    local denied = false
    for _ = 1, config.RequestsPerWindow + 2 do if not call(c, 2, session, 'inventory').ok then denied = true end end
    assert(denied)
    c.core.time = c.core.time + config.RequestWindow
    session = open(c, 2, 'client'); assert(call(c, 2, session, 'inventory').ok)
    c.players[2].noWorld = true
    assert(not c.game.placement.stream(2))
end)

test('Ambiguous inventory writes recover reservations and final commits without granting extra items', function()
    for _, offset in ipairs({ 1, 2 }) do
        local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
        assert(call(c, 1, session, 'place_begin').ok)
        c.failInvAt = c.invWrites + offset; c.completeInventoryWriteBeforeError = true
        assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
        local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
        assert(count(restarted, 1, 'os_cctv_kit') == (offset == 1 and 2 or 1))
        assert(restarted.core.registry.list(0).total == (offset == 1 and 0 or 1))
    end
end)

test('Recovery resumes an interrupted installation state transition on the same core ID', function()
    local c = fixture(); kit(c); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local original = c.core.registry.setState
    c.core.registry.setState = function(source, id, state)
        if state == 'installed' then return nil, 'Injected state failure' end
        return original(source, id, state)
    end
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    c.core.registry.setState = original
    assert(c.core.registry.list(0).total == 1)
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
    assert(restarted.core.registry.get(0, 'osd_0000000001').state == 'active')
    assert(restarted.core.registry.list(0).total == 1 and count(restarted, 1, 'os_cctv_kit') == 1)
end)

test('Native server wiring keeps replies private, normalizes ACE and creates unique sessions without repeated password hashing', function()
    local originalPrint, originalOpen, originalSource = print, io.open, source
    local replaced = {}
    local function stub(name, callback) replaced[name] = { _G[name] }; _G[name] = callback end
    local handlers, commands, files, replies, hashes = {}, {}, {}, {}, 0
    local ok, err = pcall(function()
        stub('RegisterNetEvent', function(name, callback) assert(name == 'os_security:g6:request'); handlers.request = callback end)
        stub('RegisterCommand', function(name, callback) commands[name] = callback end)
        stub('AddEventHandler', function(name, callback) handlers[name] = callback end)
        stub('GetCurrentResourceName', function() return 'os_security' end)
        stub('GetPlayerName', function(player) return player == 7 and 'Untrusted display name' or nil end)
        stub('GetPlayerIdentifierByType', function(player, kind) assert(player == 7 and kind == 'license'); return 'license:' .. string.rep('a', 40) end)
        stub('IsPlayerAceAllowed', function(player) return player == 7 and 1 or 0 end)
        stub('GetPlayerPed', function(player) assert(player == 7); return 123 end)
        stub('GetEntityHealth', function(ped) assert(ped == 123); return 200 end)
        stub('GetHashKey', function() return -1 end)
        stub('GetPasswordHash', function() hashes = hashes + 1; return '$test$random-salt' end)
        stub('LoadResourceFile', function(resource, file) assert(resource == 'os_security'); return files[file] end)
        stub('SaveResourceFile', function(resource, file, content, bytes) assert(resource == 'os_security' and bytes == #content); files[file] = content; return 1 end)
        stub('TriggerClientEvent', function(name, player, id, response)
            assert(player == 7, 'Response broadcast or sent to another player')
            if name == 'os_security:g6:response' then replies[#replies + 1] = { id = id, response = response } end
        end)
        io.open = function() return nil, 'missing', 2 end
        print = function() end
        dofile('/repo/server/main.lua'); handlers.onResourceStart('os_security')
        commands.osg6(7, { 'give', '7', 'g6_operations_tablet', '1' }) -- BOOL nativo igual a 1.
        source = 7
        handlers.request({ id = 1, action = 'open', args = { kind = 'operations' } })
        local first = replies[#replies].response
        assert(first.ok and first.session.kind == 'operations' and first.session.profile == OSSecurity.Brand.Profiles.admin)
        assert(first.session.employeeId == OSSecurity.Brand.EmployeePrefix .. '-FFFFFFFF')
        handlers.request({ id = 2, action = 'open', args = { kind = 'inventory' } })
        local second = replies[#replies].response
        assert(second.ok and second.session.token ~= first.session.token and hashes == 1)
        assert(not codec.encode(second):find('license:', 1, true))
        handlers.request({ id = 3, action = 'devices', token = first.session.token, sequence = 1, args = {} })
        assert(not replies[#replies].response.ok)
        handlers.onResourceStop('os_security')
    end)
    print, io.open, source = originalPrint, originalOpen, originalSource
    for name, previous in pairs(replaced) do _G[name] = previous[1] end
    assert(ok, err)
end)
