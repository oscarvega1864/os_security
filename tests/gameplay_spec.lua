local test, coreFixture, create, equal = StorageTest.test, StorageTest.fixture, StorageTest.create, StorageTest.equal
local util, config, codec = OSSecurity.Util, OSSecurity.GameplayConfig, OSSecurity.JsonCodec
local bootNumber = 0

local function fixture(files, external)
    bootNumber = bootNumber + 1
    local core = coreFixture(files)
    local c = { core = core, players = {}, aces = {}, jobs = {}, alarmLog = {}, assets = { properties = {}, businesses = {} }, active = {}, commands = {}, audit = {}, replies = {}, invWrites = 0, timers = {} }
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
        schedule = function(callback) c.timers[#c.timers + 1] = callback end,
        items = external and external.items or nil,
        alarmEffects = {
            players = function()
                local list = {}
                for id, player in pairs(c.players) do
                    if player.connected then list[#list + 1] = { source = id, position = util.copy(player.point), bucket = player.bucket } end
                end
                return list
            end,
            entry = function(source, device, seconds) c.alarmLog[#c.alarmLog + 1] = { 'entry', source, device.id, seconds } end,
            siren = function(deviceId, device) c.alarmLog[#c.alarmLog + 1] = { device and 'siren_on' or 'siren_off', deviceId } end,
            notify = function(source, text) c.alarmLog[#c.alarmLog + 1] = { 'alert', source, text } end
        },
        employment = OSSecurity.Employment.new({ settings = config.Employment, read = function(source)
            if c.jobsFail then error('proveedor caido') end
            return c.jobs[source]
        end }),
        sites = OSSecurity.Sites.new({
            asset = function(category, id) if c.sitesFail then error('caido') end; return c.assets[category][id] end,
            active = function(source) return c.active[source] end
        })
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

test('On-duty gruppe6 employment grants technician/supervisor operations profiles, revoked live when off duty', function()
    local c = fixture()
    local function denied(source, kind)
        nextRequest = nextRequest + 1
        return c.game.handle(source, { id = nextRequest, action = 'open', args = { kind = kind } })
    end
    grant(c, 5, 'g6_operations_tablet'); grant(c, 5, 'g6_client_tablet')
    c.jobs[5] = { job = 'gruppe6', rank = 'tecnico', duty = false }
    assert(not denied(5, 'operations').ok) -- fuera de servicio
    c.jobs[5].duty = true
    local session = open(c, 5, 'operations'); assert(session.profile == OSSecurity.Brand.Profiles.technician)
    assert(session.role == 'technician' and table.concat(session.abilities, ',') == 'view,inspect,repair,replace,provision,install')
    assert(call(c, 5, session, 'inventory', {}).ok)
    assert(not denied(5, 'client').ok) -- el empleo no concede la tablet Client
    c.core.time = c.core.time + 10
    session = open(c, 5, 'operations'); c.jobs[5].duty = false
    local revoked = call(c, 5, session, 'inventory', {}); assert(not revoked.ok and revoked.close)
    c.core.time = c.core.time + 10
    c.jobs[5] = { job = 'gruppe6', rank = 'supervisor', duty = true }
    session = open(c, 5, 'operations'); assert(session.profile == OSSecurity.Brand.Profiles.supervisor)
    assert(session.role == 'supervisor' and table.concat(session.abilities, ',') == 'view,inspect,beginMaintenance' and not session.canInstall)
    c.core.time = c.core.time + 10
    for _, job in ipairs({ { job = 'gruppe6', rank = 'vigilante', duty = true }, { job = 'gruppe6', rank = 'admin', duty = true },
        { job = 'police', rank = 'tecnico', duty = true }, 'gruppe6', false }) do
        c.jobs[5] = job; assert(not denied(5, 'operations').ok)
    end
    c.jobs[5] = { job = 'gruppe6', rank = 'tecnico', duty = true }; c.jobsFail = true; assert(not denied(5, 'operations').ok)
    -- Los ACE siguen teniendo prioridad y funcionan sin empleo
    c.jobsFail = false; c.jobs[1] = nil; grant(c, 1, 'g6_operations_tablet'); open(c, 1, 'operations')
end)

test('Employment adapter requires the same character as the item holder and never maps admin', function()
    local settings = { Job = 'gruppe6', RequireDuty = true, Ranks = { tecnico = 'technician', jefe = 'admin' } }
    local current
    local role = OSSecurity.Employment.new({ settings = settings, read = function() return current end })
    current = { job = 'gruppe6', rank = 'tecnico', duty = true, characterId = 'oschar_0000000001' }
    assert(role(1, 'oschar_0000000001') == 'technician' and role(1, nil) == 'technician')
    assert(role(1, 'oschar_0000000002') == nil)
    current = { job = 'gruppe6', rank = 'jefe', duty = true }; assert(role(1) == nil)
    assert(OSSecurity.Employment.new({ settings = settings })(1) == nil)
    local free = OSSecurity.Employment.new({ settings = { Job = 'gruppe6', RequireDuty = false, Ranks = settings.Ranks },
        read = function() return { job = 'gruppe6', rank = 'tecnico', duty = false } end })
    assert(free(1) == 'technician')
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

test('Owners of a linked property or business see its devices on the Client tablet, read-only and only with that character', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet'); grant(c, 1, 'g6_operations_tablet')
    local camera = create(c.core, 'cctv_camera', { owner = c.players[5].principal })
    local shop = create(c.core, 'cctv_camera', { owner = c.players[5].principal })
    c.assets.properties[200] = { id = 200, price = 50000, owner = 'oscar_vega' }
    c.assets.businesses[3] = { id = 3, name = 'Vanilla', owner = 'otro' }
    c.active[2] = { alias = 'oscar_vega', characterId = 'oschar_0000000001' }
    c.commands.osg6(0, { 'site', camera.id, 'propiedad', '200' })
    c.commands.osg6(0, { 'site', shop.id, 'negocio', '3' })
    c.commands.osg6(0, { 'site', shop.id, 'negocio', '99' }) -- inexistente: no cambia el vinculo
    assert(c.game.inventory.site(camera.id).id == 200 and c.game.inventory.site(shop.id).kind == 'business')
    local session = open(c, 2, 'client')
    local listed = call(c, 2, session, 'devices', { offset = 0 })
    assert(listed.ok and listed.data.total == 1 and listed.data.items[1].id == camera.id and listed.data.items[1].site == 'Propiedad 200')
    assert(not call(c, 2, session, 'maintain', { deviceId = camera.id, action = 'inspect' }).ok)
    assert(not call(c, 2, session, 'device', { deviceId = shop.id }).ok)
    c.assets.businesses[3].owner = 'oscar_vega'
    assert(call(c, 2, session, 'device', { deviceId = shop.id }).data.site == 'Negocio 3 · Vanilla')
    c.active[2] = { alias = 'segundo_test' } -- otro personaje del mismo jugador
    assert(call(c, 2, session, 'devices', { offset = 0 }).data.total == 0)
    c.active[2] = { alias = 'oscar_vega' }; c.sitesFail = true
    assert(call(c, 2, session, 'devices', { offset = 0 }).data.total == 0)
    c.sitesFail = false
    -- El vinculo no da acceso a la tablet Operations
    c.active[1] = { alias = 'oscar_vega' }; local tech = open(c, 1, 'operations')
    assert(call(c, 1, tech, 'devices', {}).data.total == 0)
    -- Retirar el vinculo, y persistencia tras reinicio
    c.commands.osg6(0, { 'site', shop.id, 'none' }); assert(c.game.inventory.site(shop.id) == nil)
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
    assert(restarted.game.inventory.site(camera.id).id == 200 and restarted.game.inventory.site(shop.id) == nil)
    c.commands.osg6(0, { 'site', camera.id, 'none' })
    restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
end)

test('Aimed anchors require admin, a nearby point and valid data, then persist with the admin bucket', function()
    local c = fixture(); c.players[4].point = { x = 100, y = 0, z = 1 }; c.players[4].bucket = 3
    local function aim(source, payload) return c.game.anchorAt(source, payload) end
    local base = { id = 'mount_aim', client = 2, position = { x = 102, y = 0, z = 2 }, normal = { x = 0, y = -2, z = 0 } }
    assert(not aim(1, base)) -- sin ossecurity.admin
    local far = util.copy(base); far.position = { x = 200, y = 0, z = 2 }; assert(not aim(4, far))
    local bad = util.copy(base); bad.extra = true; assert(not aim(4, bad))
    local zero = util.copy(base); zero.normal = { x = 0, y = 0, z = 0 }; assert(not aim(4, zero))
    local nobody = util.copy(base); nobody.client = 99; assert(not aim(4, nobody))
    local message = assert(aim(4, base)); assert(message:find('mount_aim', 1, true))
    local anchor = c.game.inventory.snapshot().anchors.mount_aim
    assert(anchor.owner == c.players[2].principal and anchor.installer == c.players[4].principal and anchor.bucket == 3)
    assert(anchor.normal.y == -1 and anchor.radius == 0.75)
    local other = util.copy(base); other.id = 'mount_aim2'; other.installer = 1; other.radius = 1.5
    assert(aim(4, other)); anchor = c.game.inventory.snapshot().anchors.mount_aim2
    assert(anchor.installer == c.players[1].principal and anchor.radius == 1.5)
end)

test('Aimed anchors and placements persist only runtime-safe numbers (no residual raycast exponents)', function()
    local c = fixture(); c.players[4].point = { x = 1170.1, y = 2711.5, z = 39.1 }
    assert(c.game.anchorAt(4, { id = 'wall', client = 1, position = { x = 1170.226318359375, y = 2712.0000000001, z = 39.093368530273438 },
        normal = { x = -0.99999994039536, y = 2.3283064365387e-17, z = -4.3711388286738e-08 } }))
    local anchor = c.game.inventory.snapshot().anchors.wall
    assert(anchor.normal.x == -1 and anchor.normal.y == 0 and anchor.normal.z == 0)
    assert(anchor.position.x == 1170.2263 and anchor.position.y == 2712 and anchor.position.z == 39.0934)
    assert(OSSecurity.Util.round(359.99999999999994, 2) == 360 and OSSecurity.Util.round(5.6843418860808e-14, 2) == 0)
    assert(math.type(OSSecurity.Util.round(-1.0000000001, 6)) == 'integer')
end)

local function alarmPanel(c, owner)
    for id = 1, 5 do c.players[id].point = { x = 1000 + id * 50, y = 0, z = 1 } end -- nadie en la zona salvo que la prueba lo diga
    local device = create(c.core, 'alarm_panel', { owner = c.players[owner].principal, model = 'prop_ld_keypad_01',
        position = { x = 0, y = 0, z = 1 }, rotation = { x = 0, y = 0, z = 0 } })
    for _, state in ipairs({ 'installing', 'installed', 'active' }) do StorageTest.transition(c.core, device.id, state) end
    return device
end
local function logged(c, kind)
    local found = {}
    for _, entry in ipairs(c.alarmLog) do if entry[1] == kind then found[#found + 1] = entry end end
    return found
end

test('Alarm keypad: code from the tablet, arm with exit delay, wrong codes lock the keypad and alert the owner', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet')
    local panel = alarmPanel(c, 2)
    c.players[2].point = { x = 1, y = 0, z = 1 }
    assert(not c.game.alarms.keypad(2, panel.id, 'arm', '1234')) -- sin codigo configurado
    local session = open(c, 2, 'client')
    local set = call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'pin', pin = '12' }); assert(not set.ok) -- demasiado corto
    set = call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'pin', pin = '1234' }); assert(set.ok and set.data.alarm.hasPin)
    c.players[5].point = { x = 30, y = 0, z = 1 }
    assert(not c.game.alarms.keypad(5, panel.id, 'arm', '1234')) -- lejos del teclado
    local armed = assert(c.game.alarms.keypad(2, panel.id, 'arm', '1234')); assert(armed.mode == 'armed')
    assert(c.game.inventory.alarm(panel.id).mode == 'armed' and c.game.inventory.alarm(panel.id).pin ~= '1234')
    c.players[5].point = { x = 1, y = 1, z = 1 }
    for attempt = 1, 3 do assert(not c.game.alarms.keypad(5, panel.id, 'disarm', '0000')) end
    assert(not c.game.alarms.keypad(5, panel.id, 'disarm', '1234')) -- bloqueado aunque ahora acierte
    assert(#logged(c, 'alert') >= 1 and logged(c, 'alert')[1][2] == 2) -- aviso de manipulacion al titular
    local restarted = fixture(c.core.files); assert(restarted.game.inventory.alarm(panel.id).mode == 'armed')
end)

test('Armed alarm: entry delay for anyone inside, triggers siren and alerts owner and on-duty G6; disarming stops it', function()
    local c = fixture(); local panel = alarmPanel(c, 2)
    c.players[2].point = { x = 1, y = 0, z = 1 }; c.players[5].point = { x = 500, y = 0, z = 1 }; c.players[3].point = { x = 900, y = 0, z = 1 }
    grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    assert(call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'pin', pin = '4321' }).ok)
    assert(c.game.alarms.keypad(2, panel.id, 'arm', '4321'))
    c.players[2].point = { x = 400, y = 0, z = 1 } -- el titular sale
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 0)
    c.core.time = c.core.time + OSSecurity.GameplayConfig.Alarm.ExitDelay + 1
    c.players[5].point = { x = 3, y = 0, z = 1 } -- entra alguien
    c.jobs[3] = { job = 'gruppe6', rank = 'tecnico', duty = true }
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 1 and logged(c, 'entry')[1][2] == 5)
    c.core.time = c.core.time + OSSecurity.GameplayConfig.Alarm.EntryDelay + 1
    c.game.alarms.tick(); assert(#logged(c, 'siren_on') == 1)
    local alerted = {}; for _, entry in ipairs(logged(c, 'alert')) do alerted[entry[2]] = true end
    assert(alerted[2] and alerted[3] and not alerted[5]) -- titular y G6 de servicio, no el intruso
    assert(call(c, 2, session, 'device', { deviceId = panel.id }).data.alarm.triggered)
    local disarmed = call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'disarm' }); assert(disarmed.ok and disarmed.data.alarm.mode == 'disarmed')
    assert(#logged(c, 'siren_off') == 1)
    local events = disarmed.data.alarm.events; assert(events[1].kind == 'disarmed' and events[2].kind == 'triggered')
end)

test('Partial mode ignores authorized people inside but not strangers', function()
    local c = fixture(); local panel = alarmPanel(c, 2)
    grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    assert(call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'pin', pin = '5555' }).ok)
    c.players[2].point = { x = 1, y = 0, z = 1 }; c.players[5].point = { x = 800, y = 0, z = 1 }
    assert(c.game.alarms.keypad(2, panel.id, 'partial', '5555').mode == 'partial')
    c.core.time = c.core.time + OSSecurity.GameplayConfig.Alarm.ExitDelay + 1
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 0) -- el titular sigue dentro: no salta
    c.players[5].point = { x = 2, y = 0, z = 1 }
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 1 and logged(c, 'entry')[1][2] == 5)
    assert(not call(c, 5, open(c, 5, 'inventory'), 'alarm', { deviceId = panel.id, action = 'disarm' }).ok) -- sin acceso
end)

test('Inventory state rejects malformed site links', function()
    local limits = config
    for _, site in ipairs({ { kind = 'house', id = 1 }, { kind = 'property', id = 0 }, { kind = 'property', id = 1.5 }, { kind = 'property', id = 1, owner = 'x' } }) do
        assert(not OSSecurity.InventoryState.site(site))
    end
    local snapshot = OSSecurity.InventoryState.initial()
    assert(not OSSecurity.InventoryState.apply(snapshot, { kind = 'site', at = 1, deviceId = 'bad', site = { kind = 'property', id = 1 } }, limits))
    assert(OSSecurity.InventoryState.apply(snapshot, { kind = 'site', at = 1, deviceId = 'osd_0000000001', site = { kind = 'property', id = 1 } }, limits))
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
    assert(device.owner == c.players[2].principal and device.position.x == 1 and device.metadata.installationId == response.data.installationId)
    assert(device.condition.components.power and device.condition.components.optics)
    assert(call(c, 1, session, 'devices', {}).data.total == 1)
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(c.core.registry.list(0).total == 1 and count(c, 1, 'os_cctv_kit') == 1)
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
    assert(restarted.core.registry.list(0).total == 1 and count(restarted, 1, 'os_cctv_kit') == 1)
end)

test('The alarm kit installs a physical alarm panel linked to its installation and consumes its own materials', function()
    local c = fixture(); grant(c, 1, 'g6_operations_tablet'); grant(c, 1, 'os_alarm_kit'); grant(c, 1, 'os_battery')
    grant(c, 1, 'os_drill'); grant(c, 1, 'os_screwdriver'); anchor(c)
    local session = open(c, 1, 'operations')
    nextRequest = nextRequest + 1
    local used = c.game.handle(1, { id = nextRequest, action = 'use', token = session.token, sequence = session.sequence + 1, args = { item = 'os_alarm_kit' } })
    assert(used.ok and used.placement and used.placement.model == 'prop_ld_keypad_01', used.error)
    local operations = used.session; operations.sequence = 0
    local response = call(c, 1, operations, 'place_confirm', proposal())
    assert(response.ok, response.error)
    local device = c.core.registry.get(0, response.data.id)
    assert(device.type == 'alarm_panel' and device.model == 'prop_ld_keypad_01' and device.metadata.installationId == response.data.installationId)
    assert(count(c, 1, 'os_alarm_kit') == 0 and count(c, 1, 'os_battery') == 0 and count(c, 1, 'os_drill') == 1)
end)

test('Square mount zones accept corners and inverted ceiling orientation, and reject points outside the square', function()
    local c = fixture(); kit(c); anchor(c)
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local outside = proposal(); outside.position = { x = 1, y = 0.8, z = 1 }
    assert(not call(c, 1, session, 'place_confirm', outside).ok)
    assert(call(c, 1, session, 'place_begin').ok)
    local corner = proposal(); corner.position = { x = 1, y = 0.7, z = 1.7 } -- fuera del circulo, dentro del cuadrado
    corner.rotation = { x = -60, y = 180, z = 270 }
    local response = call(c, 1, session, 'place_confirm', corner); assert(response.ok, response.error)
    local device = c.core.registry.get(0, response.data.id)
    assert(device.rotation.x == -60 and device.rotation.y == 180 and device.position.y == 0.7)
end)

test('Placement keeps the chosen depth off the surface within the configured limits', function()
    local c = fixture(); kit(c); grant(c, 1, 'os_cctv_kit'); grant(c, 1, 'os_battery'); anchor(c)
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local deep = proposal(); deep.position.x = 1 - (config.MaxDepth + 0.05) -- normal (-1, 0, 0): separar resta en X
    assert(not call(c, 1, session, 'place_confirm', deep).ok)
    assert(call(c, 1, session, 'place_begin').ok)
    local inside = proposal(); inside.position.x = 1 - (config.MinDepth - 0.05)
    assert(not call(c, 1, session, 'place_confirm', inside).ok)
    assert(call(c, 1, session, 'place_begin').ok)
    local chosen = proposal(); chosen.position.x = 0.85
    local response = call(c, 1, session, 'place_confirm', chosen); assert(response.ok, response.error)
    assert(c.core.registry.get(0, response.data.id).position.x == 0.85)
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
        stub('RegisterNetEvent', function(name, callback)
            assert(name == 'os_security:g6:request' or name == 'os_security:g6:anchorAim' or name:match('^os_security:alarm:'))
            if name == 'os_security:g6:request' then handlers.request = callback else handlers.anchorAim = callback end
        end)
        stub('RegisterCommand', function(name, callback) commands[name] = callback end)
        stub('CreateThread', function() end)
        stub('AddEventHandler', function(name, callback) handlers[name] = callback end)
        stub('GetCurrentResourceName', function() return 'os_security' end)
        stub('GetConvar', function(_, default) return default end) -- sin convars: proveedor standalone
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

-- Proveedor externo simulado con las garantias de os_inventory: recibos por operationId (sin repetir
-- el efecto) y fallos sin recibo; los titulares son personajes, no licencias.
local function externalItems()
    local e = { counts = {}, receipts = {}, up = true, holders = {}, addFails = false, calls = 0 }
    for id = 1, 5 do e.holders[id] = ('oschar_%010d'):format(id) end
    local function bag(holder) e.counts[holder] = e.counts[holder] or {}; return e.counts[holder] end
    e.items = OSSecurity.ExternalItems.new({
        available = function() return e.up end,
        holder = function(source) return e.holders[source] end,
        count = function(holder, item) return bag(holder)[item] or 0 end,
        add = function(holder, item, amount, operationId)
            e.calls = e.calls + 1
            if operationId and e.receipts[operationId] then return true end
            if e.addFails then return false, 'Inventario lleno.' end
            bag(holder)[item] = (bag(holder)[item] or 0) + amount
            if operationId then e.receipts[operationId] = true end
            return true
        end,
        remove = function(holder, item, amount, operationId)
            e.calls = e.calls + 1
            if operationId and e.receipts[operationId] then return true end
            if (bag(holder)[item] or 0) < amount then return false, 'Faltan materiales.' end
            bag(holder)[item] = bag(holder)[item] - amount
            if operationId then e.receipts[operationId] = true end
            return true
        end
    })
    function e.give(source, item, amount) bag(e.holders[source])[item] = (bag(e.holders[source])[item] or 0) + (amount or 1) end
    function e.count(source, item) return bag(e.holders[source])[item] or 0 end
    function e.kit(source)
        e.give(source, 'g6_operations_tablet'); e.give(source, 'os_cctv_kit', 2); e.give(source, 'os_battery', 2)
        e.give(source, 'os_drill'); e.give(source, 'os_screwdriver')
    end
    return e
end

test('External provider: tablets and listings come from the active character, never from the local ledger', function()
    local e = externalItems(); local c = fixture(nil, e); assert(c.loaded, c.loadError)
    grant(c, 2, 'g6_client_tablet') -- objeto local: no cuenta con proveedor externo
    nextRequest = nextRequest + 1
    assert(not c.game.handle(2, { id = nextRequest, action = 'open', args = { kind = 'client' } }).ok)
    e.give(2, 'g6_client_tablet')
    local session = open(c, 2, 'client')
    local listed = call(c, 2, open(c, 2, 'inventory'), 'inventory')
    assert(listed.ok and #listed.data.items == 1 and listed.data.items[1].id == 'g6_client_tablet' and listed.data.items[1].count == 1)
    e.holders[2] = nil
    nextRequest = nextRequest + 1
    assert(not c.game.handle(2, { id = nextRequest, action = 'open', args = { kind = 'client' } }).ok)
    assert(session.token)
end)

test('External provider: a CCTV installation charges materials once, keeps tools and records the holder', function()
    local e = externalItems(); local c = fixture(nil, e); e.kit(1); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local result = call(c, 1, session, 'place_confirm', proposal())
    assert(result.ok, result.error)
    assert(e.count(1, 'os_cctv_kit') == 1 and e.count(1, 'os_battery') == 1 and e.count(1, 'os_drill') == 1 and e.count(1, 'os_screwdriver') == 1)
    local installation = c.game.inventory.snapshot().installations.g6i_0000000001
    assert(installation.status == 'committed' and installation.holder == 'oschar_0000000001')
    assert(count(c, 1, 'os_cctv_kit') == 0 and c.core.registry.list(0).total == 1)
    local restarted = fixture(c.core.files, e); assert(restarted.loaded, restarted.loadError)
    assert(e.count(1, 'os_cctv_kit') == 1 and restarted.core.registry.list(0).total == 1)
end)

test('External provider: missing materials or a changed character never create a device nor charge anything', function()
    local e = externalItems(); local c = fixture(nil, e); e.kit(1); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    e.counts[e.holders[1]].os_battery = 0
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(e.count(1, 'os_cctv_kit') == 2 and c.core.registry.list(0).total == 0)
    e.give(1, 'os_battery', 2); session = open(c, 1, 'operations'); assert(call(c, 1, session, 'place_begin').ok)
    e.holders[1] = 'oschar_0000000099'
    local changed = call(c, 1, session, 'place_confirm', proposal())
    assert(not changed.ok) -- la sesion se reautoriza en cada peticion: el cambio de personaje la invalida
    assert(e.count(1, 'os_cctv_kit') == 0 and (e.counts.oschar_0000000001.os_cctv_kit == 2) and c.core.registry.list(0).total == 0)
end)

test('External provider: an orphan reservation is refunded exactly once on restart, and waits while the provider is down', function()
    local e = externalItems(); local c = fixture(nil, e); e.kit(1); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.core.writeFailure = true -- reserva y cobro hechos; el dispositivo nunca se escribe
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    assert(e.count(1, 'os_cctv_kit') == 1)
    e.up = false
    local waiting = fixture(c.core.files, e); assert(waiting.loaded, waiting.loadError)
    assert(waiting.game.inventory.snapshot().installations.g6i_0000000001.status == 'pending' and e.count(1, 'os_cctv_kit') == 1)
    e.up = true
    local restarted = fixture(c.core.files, e); assert(restarted.loaded, restarted.loadError)
    assert(restarted.game.inventory.snapshot().installations.g6i_0000000001.status == 'cancelled')
    assert(e.count(1, 'os_cctv_kit') == 2 and e.count(1, 'os_battery') == 2)
    assert(fixture(restarted.core.files, e).loaded and e.count(1, 'os_cctv_kit') == 2)
end)

test('External provider: a refund that cannot be confirmed keeps the reservation pending instead of losing items', function()
    local e = externalItems(); local c = fixture(nil, e); e.kit(1); anchor(c); local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    c.core.writeFailure = true
    assert(not call(c, 1, session, 'place_confirm', proposal()).ok)
    e.addFails = true
    local blocked = fixture(c.core.files, e)
    assert(not blocked.loaded and blocked.game.inventory.snapshot().installations.g6i_0000000001.status == 'pending')
    e.addFails = false
    local restarted = fixture(c.core.files, e); assert(restarted.loaded, restarted.loadError)
    assert(e.count(1, 'os_cctv_kit') == 2)
end)

test('osg6 migrate moves local items to the active character once, even if repeated after an interruption', function()
    local e = externalItems(); local c = fixture(nil, e)
    grant(c, 4, 'g6_client_tablet'); grant(c, 4, 'g6_operations_tablet')
    c.failInventory = true
    c.commands.osg6(0, { 'migrate', '4' })
    assert(e.count(4, 'g6_client_tablet') == 1 and not c.game.inventory.status())
    local restarted = fixture(c.core.files, e); assert(restarted.loaded, restarted.loadError)
    restarted.commands.osg6(0, { 'migrate', '4' })
    assert(e.count(4, 'g6_client_tablet') == 1 and e.count(4, 'g6_operations_tablet') == 1)
    assert(count(restarted, 4, 'g6_client_tablet') == 0 and count(restarted, 4, 'g6_operations_tablet') == 0)
    local account = restarted.game.inventory.get(restarted.players[4].principal)
    assert(account.migrated.g6_client_tablet == 1 and account.migrated.g6_operations_tablet == 1)
    restarted.commands.osg6(0, { 'migrate', '4' })
    assert(restarted.replies[#restarted.replies][2]:find('No hay objetos locales', 1, true))
    grant(restarted, 4, 'g6_client_tablet'); restarted.commands.osg6(0, { 'migrate', '4' })
    assert(e.count(4, 'g6_client_tablet') == 2)
    local standalone = fixture()
    standalone.commands.osg6(0, { 'migrate', '4' })
    assert(standalone.replies[#standalone.replies][2]:find('ossecurity_items', 1, true))
end)

test('osg6 give and inventory use the external provider when configured', function()
    local e = externalItems(); local c = fixture(nil, e)
    c.commands.osg6(0, { 'give', '3', 'os_cctv_kit', '2' })
    assert(e.count(3, 'os_cctv_kit') == 2 and count(c, 3, 'os_cctv_kit') == 0)
    c.commands.osg6(0, { 'inventory', '3' })
    assert(c.replies[#c.replies][2] == 'os_cctv_kit=2')
    c.commands.osg6(0, { 'give', '3', 'agua', '1' })
    assert(e.count(3, 'agua') == 0)
end)
