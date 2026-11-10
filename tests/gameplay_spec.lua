local test, coreFixture, create, equal = StorageTest.test, StorageTest.fixture, StorageTest.create, StorageTest.equal
local util, config, codec = OSSecurity.Util, OSSecurity.GameplayConfig, OSSecurity.JsonCodec
local bootNumber = 0

local function fixture(files, external)
    bootNumber = bootNumber + 1
    local core = coreFixture(files)
    local c = { core = core, wallet = {}, players = {}, aces = {}, jobs = {}, alarmLog = {}, assets = { properties = {}, businesses = {} }, active = {}, commands = {}, audit = {}, replies = {}, invWrites = 0, timers = {} }
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
        players = function()
            local list = {}
            for id, player in pairs(c.players) do if player.connected then list[#list + 1] = id end end
            table.sort(list); return list
        end,
        playerName = function(id) return 'Jugador' .. id end,
        money = {
            available = function() return not c.moneyDown end,
            balance = function(source) return c.wallet[source] and util.copy(c.wallet[source]) or nil end,
            charge = function(source, amount, account)
                local wallet = c.wallet[source]
                if not wallet or wallet[account] < amount then return false, 'insufficient_funds' end
                wallet[account] = wallet[account] - amount; return true
            end,
            refund = function(source, amount, account)
                if c.refundFails then return false end
                c.wallet[source][account] = c.wallet[source][account] + amount; return true
            end
        },
        vehicles = { asset = function(id) return c.vehicleAssets and c.vehicleAssets[id] end,
            alias = function(source) return c.active[source] and c.active[source].alias end,
            driving = function() return nil end, locate = function(plate) return c.vehicleSpots and c.vehicleSpots[plate] end },
        items = external and external.items or nil,
        characterOwnership = external and external.characters or nil,
        locksChanged = function(list) c.doorBroadcasts = (c.doorBroadcasts or 0) + 1; c.lastDoors = list end,
        alarmEffects = {
            players = function()
                local list = {}
                for id, player in pairs(c.players) do
                    if player.connected then list[#list + 1] = { source = id, position = util.copy(player.point), bucket = player.bucket, inside = player.inside } end
                end
                return list
            end,
            entry = function(source, device, seconds) c.alarmLog[#c.alarmLog + 1] = { 'entry', source, device.id, seconds } end,
            entryStop = function(deviceId) c.alarmLog[#c.alarmLog + 1] = { 'entry_stop', deviceId } end,
            siren = function(deviceId, device) c.alarmLog[#c.alarmLog + 1] = { device and 'siren_on' or 'siren_off', deviceId } end,
            notify = function(source, text) c.alarmLog[#c.alarmLog + 1] = { 'alert', source, text } end
        },
        employment = OSSecurity.Employment.new({ settings = config.Employment, read = function(source)
            if c.jobsFail then error('proveedor caido') end
            return c.jobs[source]
        end }),
        sites = OSSecurity.Sites.new({
            asset = function(category, id) if c.sitesFail then error('caido') end; return c.assets[category][id] end,
            list = function(category)
                local result = {}
                for _, asset in pairs(c.assets[category]) do result[#result + 1] = asset end
                return result
            end,
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
    assert(#logged(c, 'entry_stop') == 1) -- al saltar se cortan los pitidos de entrada
    local alerted = {}; for _, entry in ipairs(logged(c, 'alert')) do alerted[entry[2]] = true end
    assert(alerted[2] and alerted[3] and not alerted[5]) -- titular y G6 de servicio, no el intruso
    assert(call(c, 2, session, 'device', { deviceId = panel.id }).data.alarm.triggered)
    local disarmed = call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'disarm' }); assert(disarmed.ok and disarmed.data.alarm.mode == 'disarmed')
    assert(#logged(c, 'siren_off') == 1)
    local events = disarmed.data.alarm.events; assert(events[1].kind == 'disarmed' and events[2].kind == 'triggered')
end)

test('Interior presence: someone just outside the property is ignored, someone inside the interior counts', function()
    local c = fixture(); local panel = alarmPanel(c, 2)
    c.players[2].point = { x = 1, y = 0, z = 1 }; c.players[5].point = { x = 500, y = 0, z = 1 }; c.players[3].point = { x = 900, y = 0, z = 1 }
    grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    assert(call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'pin', pin = '4321' }).ok)
    assert(c.game.alarms.keypad(2, panel.id, 'arm', '4321'))
    c.core.time = c.core.time + OSSecurity.GameplayConfig.Alarm.ExitDelay + 1
    c.players[2].point = { x = 4, y = 0, z = 1 }; c.players[2].inside = { [panel.id] = false } -- en la calle, junto a la puerta
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 0)
    c.players[2].inside = nil -- sin dato del cliente: esfera
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 1)
    c.players[2].point = { x = 1, y = 0, z = 1 }
    assert(c.game.alarms.keypad(2, panel.id, 'disarm', '4321')); assert(c.game.alarms.keypad(2, panel.id, 'arm', '4321'))
    c.core.time = c.core.time + OSSecurity.GameplayConfig.Alarm.ExitDelay + 1
    c.players[2].point = { x = 25, y = 0, z = 1 }; c.players[2].inside = { [panel.id] = true } -- dentro, al fondo de la casa
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 2)
end)

test('Disarming during the entry delay stops the entry beeps and never triggers', function()
    local c = fixture(); local panel = alarmPanel(c, 2)
    c.players[2].point = { x = 1, y = 0, z = 1 }; c.players[5].point = { x = 500, y = 0, z = 1 }; c.players[3].point = { x = 900, y = 0, z = 1 }
    grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    assert(call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'pin', pin = '4321' }).ok)
    assert(c.game.alarms.keypad(2, panel.id, 'arm', '4321'))
    c.players[2].point = { x = 400, y = 0, z = 1 }
    c.core.time = c.core.time + OSSecurity.GameplayConfig.Alarm.ExitDelay + 1
    c.players[2].point = { x = 1, y = 0, z = 1 } -- vuelve el titular
    c.game.alarms.tick(); assert(#logged(c, 'entry') == 1 and #logged(c, 'entry_stop') == 0)
    assert(c.game.alarms.keypad(2, panel.id, 'disarm', '4321'))
    local stops = logged(c, 'entry_stop'); assert(#stops == 1 and stops[1][2] == panel.id)
    c.core.time = c.core.time + OSSecurity.GameplayConfig.Alarm.EntryDelay + 1
    c.game.alarms.tick(); assert(#logged(c, 'siren_on') == 0)
end)

test('Using a tag from the inventory acts on the nearest keypad in reach only', function()
    local c = fixture(); local panel = alarmPanel(c, 2)
    grant(c, 2, 'g6_client_tablet'); local session = open(c, 2, 'client')
    assert(call(c, 2, session, 'alarm', { deviceId = panel.id, action = 'pin', pin = '1111' }).ok)
    local _, far = c.game.alarms.tagNearest(2); assert(far:find('Acerca'))
    c.players[2].point = { x = 1, y = 0, z = 1 }
    local _, unknown = c.game.alarms.tagNearest(2); assert(unknown == 'Chapa no reconocida.') -- sin chapa programada
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

test('Uninstalling retires the device, frees the mount and returns the kit, only near it, with tools and permission', function()
    local c = fixture(); kit(c); anchor(c)
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local installed = call(c, 1, session, 'place_confirm', proposal()); assert(installed.ok, installed.error)
    local id = installed.data.id
    assert(count(c, 1, 'os_cctv_kit') == 1)
    local detail = call(c, 1, session, 'device', { deviceId = id }); assert(detail.data.removable)
    c.players[1].point = { x = 50, y = 0, z = 1 }
    assert(not call(c, 1, session, 'remove_begin', { deviceId = id }).ok) -- lejos
    c.players[1].point = { x = 0, y = 0, z = 1 }
    local begun = call(c, 1, session, 'remove_begin', { deviceId = id }); assert(begun.ok and begun.removal.deviceId == id, begun.error)
    assert(not call(c, 1, session, 'remove_confirm', { deviceId = 'osd_0000000099' }).ok) -- otro dispositivo: anula el contexto
    assert(call(c, 1, session, 'remove_begin', { deviceId = id }).ok)
    local removed = call(c, 1, session, 'remove_confirm', { deviceId = id }); assert(removed.ok and removed.data.removed, removed.error)
    assert(c.core.registry.get(0, id).state == 'retired' and count(c, 1, 'os_cctv_kit') == 2)
    local snapshot = c.game.inventory.snapshot(); assert(snapshot.installations[installed.data.installationId].status == 'removed')
    assert(not call(c, 1, session, 'remove_begin', { deviceId = id }).ok) -- ya desmontado
    assert(call(c, 1, session, 'place_begin').ok) -- el montaje vuelve a estar libre
    local restarted = fixture(c.core.files); assert(restarted.loaded, restarted.loadError)
end)

test('Supervisors cannot uninstall; the device owner can from the Client tablet', function()
    local c = fixture(); kit(c); anchor(c)
    local tech = open(c, 1, 'operations'); assert(call(c, 1, tech, 'place_begin').ok)
    local installed = call(c, 1, tech, 'place_confirm', proposal()); assert(installed.ok)
    local id = installed.data.id
    grant(c, 3, 'g6_operations_tablet'); grant(c, 3, 'os_drill'); grant(c, 3, 'os_screwdriver'); grantAccess(c, 3, id, 'supervisor')
    c.players[3].point = { x = 0, y = 0, z = 1 }
    assert(not call(c, 3, open(c, 3, 'operations'), 'remove_begin', { deviceId = id }).ok)
    grant(c, 2, 'g6_client_tablet'); grant(c, 2, 'os_drill'); grant(c, 2, 'os_screwdriver'); c.players[2].point = { x = 0, y = 0, z = 1 }
    local owner = open(c, 2, 'client')
    assert(call(c, 2, owner, 'device', { deviceId = id }).data.removable)
    assert(call(c, 2, owner, 'remove_begin', { deviceId = id }).ok)
    assert(call(c, 2, owner, 'remove_confirm', { deviceId = id }).ok and count(c, 2, 'os_cctv_kit') == 1)
end)

for kitItem, model in pairs({ os_alarm_kit = 'prop_ld_keypad_01', os_alarm_kit_panel = 'hei_prop_hei_securitypanel',
    os_cctv_kit_mini = 'hei_prop_bank_cctv_01', os_cctv_kit_dome = 'prop_cctv_cam_05a' }) do
local deviceType = OSSecurity.GameplayConfig.Products[kitItem].deviceType
test('The kit ' .. kitItem .. ' installs a physical ' .. deviceType .. ' (' .. model .. ') and consumes its own materials', function()
    local c = fixture(); grant(c, 1, 'g6_operations_tablet'); grant(c, 1, kitItem); grant(c, 1, 'os_battery')
    grant(c, 1, 'os_drill'); grant(c, 1, 'os_screwdriver'); anchor(c)
    local session = open(c, 1, 'operations')
    nextRequest = nextRequest + 1
    local used = c.game.handle(1, { id = nextRequest, action = 'use', token = session.token, sequence = session.sequence + 1, args = { item = kitItem } })
    assert(used.ok and used.placement and used.placement.model == model, used.error)
    local operations = used.session; operations.sequence = 0
    local response = call(c, 1, operations, 'place_confirm', proposal())
    assert(response.ok, response.error)
    local device = c.core.registry.get(0, response.data.id)
    assert(device.type == deviceType and device.model == model and device.metadata.installationId == response.data.installationId)
    assert(count(c, 1, kitItem) == 0 and count(c, 1, 'os_battery') == 0 and count(c, 1, 'os_drill') == 1)
end)
end

test('Placement validates the rotation pivot against the zone and stores the model origin next to it', function()
    local c = fixture(); kit(c); anchor(c)
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local far = proposal(); far.pivot = { x = 1, y = 0, z = 1 }; far.position = { x = 1, y = -1.2, z = 1 }
    assert(not call(c, 1, session, 'place_confirm', far).ok) -- origen demasiado lejos del pivote
    assert(call(c, 1, session, 'place_begin').ok)
    local outside = proposal(); outside.pivot = { x = 1, y = 0.9, z = 1 }; outside.position = { x = 1, y = 0.7, z = 1 }
    assert(not call(c, 1, session, 'place_confirm', outside).ok) -- pivote fuera del cuadrado
    assert(call(c, 1, session, 'place_begin').ok)
    local good = proposal(); good.pivot = { x = 1, y = 0.2, z = 1.1 }; good.position = { x = 1, y = 0.45, z = 1.05 }
    local response = call(c, 1, session, 'place_confirm', good); assert(response.ok, response.error)
    local device = c.core.registry.get(0, response.data.id)
    assert(math.abs(device.position.y - 0.45) < 1e-6 and math.abs(device.position.z - 1.05) < 1e-6)
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
            assert(name == 'os_security:g6:request' or name == 'os_security:g6:anchorAim' or name == 'os_security:g6:zoneAim' or name:match('^os_security:shop:') or name:match('^os_security:alarm:') or name:match('^os_security:locks:') or name:match('^os_security:car:') or name:match('^os_security:lockpick:'))
            if name == 'os_security:g6:request' then handlers.request = callback else handlers.anchorAim = callback end
        end)
        stub('RegisterCommand', function(name, callback) commands[name] = callback end)
        stub('CreateThread', function() end)
        stub('AddEventHandler', function(name, callback) handlers[name] = callback end)
        stub('GetCurrentResourceName', function() return 'os_security' end)
        stub('exports', setmetatable({}, { __call = function() end }))
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
            if e.addFails or e.failItem == item then return false, 'Inventario lleno.' end
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


-- Cerraduras de puertas ------------------------------------------------------------------------
local function property(c, id, owner, point)
    c.assets.properties[id] = { id = id, owner = owner, position = point or { x = 100, y = 100, z = 30 } }
end
local function doorReport(id, doors) return { kind = 'property', id = id, doors = doors } end
local FRONT = { model = 520341586, x = 103, y = 100, z = 30 }
local FRONT2 = { model = 520341586, x = 104.5, y = 100, z = 30 } -- otra hoja (puerta doble)
local BACK = { model = -1234567, x = 100, y = 110, z = 30 }

test('Doors of an owned property are detected from a nearby player, locked with the stock cylinder; unowned or far reports are ignored', function()
    local c = fixture(); assert(c.loaded, c.loadError)
    property(c, 7, nil)
    c.players[2].point = { x = 101, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT })) == 0) -- sin titular no hay cerradura
    property(c, 7, 'ana')
    c.players[2].point = { x = 300, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT })) == 0) -- quien informa esta lejos
    c.players[2].point = { x = 101, y = 100, z = 30 }
    local far = { model = 5, x = 150, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT, BACK, far, { model = 'x', x = 1, y = 1, z = 1 } })) == 2)
    local list = c.game.locks.list()
    assert(#list == 2 and list[1].id == 'p7_1' and list[1].locked == true and list[1].tier == nil and c.game.locks.security('p7_1') == 1 and c.lastDoors and #c.lastDoors == 2)
    assert(c.game.locks.report(2, doorReport(7, { FRONT2 })) == 0) -- enfriamiento por propiedad
    c.core.time = c.core.time + 61
    assert(c.game.locks.report(2, doorReport(7, { FRONT, FRONT2 })) == 1) -- el duplicado no se repite
    local restarted = fixture(c.core.files); property(restarted, 7, 'ana')
    assert(#restarted.game.locks.list() == 3 and restarted.game.locks.security('p7_1') == 1)
    c.assets.properties[7].owner = nil
    assert(#c.game.locks.list() == 0) -- sin titular las puertas quedan libres
    c.assets.businesses[3] = { id = 3, owner = 'ana', position = { x = 500, y = 0, z = 10 } }
    c.players[2].point = { x = 500, y = 1, z = 10 }
    assert(c.game.locks.report(2, { kind = 'business', id = 3, doors = { { model = 1, x = 502, y = 0, z = 10 } } }) == 1)
    assert(c.game.locks.list()[1].id == 'n3_1' and c.game.locks.list()[1].locked == false) -- los negocios quedan abiertos
end)

test('Only the current owner holds the key (admins too need their own character); double doors lock together and reassignment moves the key', function()
    local c = fixture(); property(c, 7, 'ana')
    c.active[2] = { alias = 'ana' }; c.active[5] = { alias = 'luis' }
    c.players[2].point = { x = 102, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT, FRONT2, BACK })) == 3)
    c.players[5].point = { x = 102.5, y = 100, z = 30 }
    local _, denied = c.game.locks.toggle(5); assert(denied == 'No tienes la llave de esta puerta.')
    c.players[2].point = { x = 102.5, y = 100, z = 30 }
    local opened = assert(c.game.locks.toggle(2)); assert(opened.locked == false)
    local doors = c.game.inventory.doors()
    assert(doors.p7_1.locked == false and doors.p7_2.locked == false and doors.p7_3.locked == true) -- ambas hojas, no la trasera
    c.players[2].point = { x = 200, y = 100, z = 30 }
    assert(not c.game.locks.toggle(2)) -- lejos
    c.assets.properties[7].owner = 'luis'
    c.players[2].point = { x = 102.5, y = 100, z = 30 }
    assert(not c.game.locks.toggle(2) and assert(c.game.locks.toggle(5)).locked == true)
    c.players[4].point = { x = 100, y = 110.5, z = 30 }
    local _, adminWhy = c.game.locks.toggle(4); assert(adminWhy:find('llave')) -- un administrador con otro personaje no tiene la llave
end)

test('Changing the cylinder needs the open door, a screwdriver and the kit; charges once and returns the previous cylinder', function()
    local e = externalItems(); local c = fixture(nil, e); property(c, 7, 'ana')
    c.active[2] = { alias = 'ana' }
    c.players[2].point = { x = 102, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT })) == 1)
    local _, why = c.game.locks.changeBegin(2, 'os_lock_kit'); assert(why == 'Abre la puerta antes de cambiar el bombin.')
    assert(c.game.locks.toggle(2))
    _, why = c.game.locks.changeBegin(2, 'os_lock_kit'); assert(why == 'No tienes ese bombin.')
    e.give(2, 'os_lock_kit'); e.give(2, 'os_lock_kit_high')
    _, why = c.game.locks.changeBegin(2, 'os_lock_kit'); assert(why == 'Necesitas un destornillador.')
    e.give(2, 'os_screwdriver')
    assert(not c.game.locks.changeBegin(2, 'os_drill')) -- no es un bombin
    assert(c.game.locks.changeBegin(2, 'os_lock_kit'))
    assert(not c.game.locks.toggle(2)) -- no se puede cerrar durante el cambio
    local _, cancelled = c.game.locks.changeFinish(2, false); assert(cancelled:find('no se ha gastado'))
    assert(e.count(2, 'os_lock_kit') == 1 and c.game.locks.security('p7_1') == 1)
    assert(c.game.locks.changeBegin(2, 'os_lock_kit'))
    local done = assert(c.game.locks.changeFinish(2, true))
    assert(done.tier == 2 and e.count(2, 'os_lock_kit') == 0 and c.game.locks.security('p7_1') == 2)
    assert(not c.game.locks.changeFinish(2, true)) -- un solo uso
    _, why = c.game.locks.changeBegin(2, 'os_lock_kit'); assert(why:find('ya tiene'))
    assert(c.game.locks.changeBegin(2, 'os_lock_kit_high'))
    assert(c.game.locks.changeFinish(2, true).tier == 3)
    assert(e.count(2, 'os_lock_kit_high') == 0 and e.count(2, 'os_lock_kit') == 1 and e.count(2, 'os_screwdriver') == 1) -- vuelve el anterior
    local door = c.game.inventory.doors().p7_1
    assert(door.cylinder == 'os_lock_kit_high' and door.changes == 2)
end)

test('A stranger cannot change a cylinder but an on-duty G6 technician can; moving away voids the change', function()
    local e = externalItems(); local c = fixture(nil, e); property(c, 7, 'ana')
    c.active[2] = { alias = 'ana' }
    c.players[2].point = { x = 102, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT })) == 1); assert(c.game.locks.toggle(2))
    e.give(5, 'os_lock_kit'); e.give(5, 'os_screwdriver')
    c.players[5].point = { x = 102.5, y = 100, z = 30 }
    local _, why = c.game.locks.changeBegin(5, 'os_lock_kit'); assert(why:find('titular o un tecnico'))
    c.jobs[5] = { job = 'gruppe6', rank = 'tecnico', duty = true, characterId = e.holders[5] }
    assert(c.game.locks.changeBegin(5, 'os_lock_kit'))
    c.players[5].point = { x = 120, y = 100, z = 30 }
    assert(not c.game.locks.changeFinish(5, true) and e.count(5, 'os_lock_kit') == 1 and c.game.locks.security('p7_1') == 1)
end)

test('An admin can drop a wrongly detected door: it stays free and is never re-detected until /g6puerta restores it', function()
    local c = fixture(); property(c, 7, 'ana')
    c.players[4].point = { x = 102, y = 100, z = 30 }
    assert(c.game.locks.report(4, doorReport(7, { FRONT })) == 1)
    assert(not c.game.locks.unregister(2, 'p7_1'))
    assert(c.game.locks.unregister(4, 'p7_1'))
    assert(#c.game.locks.list() == 0 and c.game.inventory.doors().p7_1.ignored == true)
    c.core.time = c.core.time + 61
    assert(c.game.locks.report(4, doorReport(7, { FRONT })) == 0)
    local message = assert(c.game.locks.register(4, { kind = 'propiedad', id = 7, model = FRONT.model, position = { x = 103, y = 100, z = 30 } }))
    assert(message:find('p7_1') and #c.game.locks.list() == 1)
    assert(not c.game.locks.register(2, { kind = 'propiedad', id = 7, model = 1, position = { x = 101, y = 101, z = 30 } }))
    local _, missing = c.game.locks.register(4, { kind = 'propiedad', id = 99, model = 1, position = { x = 101, y = 101, z = 30 } })
    assert(missing:find('inexistente'))
end)

test('Inventory state rejects malformed doors', function()
    local base = { id = 'p7_1', site = { kind = 'property', id = 7 }, model = 1, position = { x = 1, y = 2, z = 3 }, bucket = 0,
        tier = 1, locked = true, changes = 0, updatedAt = 1 }
    assert(OSSecurity.InventoryState.door(base))
    local function bad(field, value) local d = util.copy(base); d[field] = value; return not OSSecurity.InventoryState.door(d) end
    assert(bad('id', 'x_1') and bad('tier', 2) and bad('cylinder', 'os_drill') and bad('locked', 'yes') and bad('ignored', false) and bad('extra', 1))
    local upgraded = util.copy(base); upgraded.cylinder, upgraded.tier = 'os_lock_kit_high', 3
    assert(OSSecurity.InventoryState.door(upgraded))
end)

test('A mount created for a property links the installed device to it without another step', function()
    local c = fixture(); kit(c)
    c.assets.properties[7] = { id = 7, owner = 'ana', position = { x = 0, y = 0, z = 1 } }
    c.players[4].point = { x = 0, y = 0, z = 1 }; c.players[1].point = { x = 0, y = 0, z = 1 }
    local base = { id = 'prop7_zona', client = 2, installer = 1, position = { x = 1, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0 } }
    local missing = util.copy(base); missing.site = { kind = 'property', id = 99 }
    local _, err = c.game.anchorAt(4, missing); assert(err:find('inexistente'))
    local forged = util.copy(base); forged.site = { kind = 'garage', id = 7 }; assert(not c.game.anchorAt(4, forged))
    base.site = { kind = 'property', id = 7 }
    local message = assert(c.game.anchorAt(4, base)); assert(message:find('Propiedad 7', 1, true))
    assert(c.game.inventory.snapshot().anchors.prop7_zona.site.id == 7)
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local result = call(c, 1, session, 'place_confirm', proposal('prop7_zona')); assert(result.ok, result.error)
    local site = c.game.inventory.site(result.data.id)
    assert(site and site.kind == 'property' and site.id == 7)
end)


-- Vehiculos: cierre centralizado y alarma -------------------------------------------------------
local function carFixture()
    local e = externalItems(); local c = fixture(nil, e); assert(c.loaded, c.loadError)
    local v = { assets = { [12] = { id = 12, plate = 'OS000012', owner = 'ana' } }, aliases = { [2] = 'ana', [5] = 'luis' }, driving = {},
        log = {}, admins = { [4] = true } }
    v.cars = OSSecurity.CarService.new({ inventory = c.game.inventory, now = function() return c.core.time end, world = function(source)
            local player = c.players[source]; return player and util.copy(player.point), 0 end,
        holdings = c.game.holdings, log = function() end, audit = function() end,
        employment = OSSecurity.Employment.new({ settings = config.Employment, read = function(source) return c.jobs[source] end }),
        isAdmin = function(source) return v.admins[source] == true end,
        vehicles = { asset = function(id) return v.assets[id] end, alias = function(source) return v.aliases[source] end,
            driving = function(source) return v.driving[source] end },
        effects = { locked = function(vehicle, locked, alarm, remote) v.log[#v.log + 1] = { 'locked', vehicle.plate, locked, alarm, remote } end,
            alarm = function(vehicle, seconds) v.log[#v.log + 1] = { 'alarm', vehicle.plate, seconds } end,
            notifyOwner = function(alias, text) v.log[#v.log + 1] = { 'notify', alias, text } end } })
    return c, e, v
end
local function carAt(x) return { plate = 'OS000012  ', position = { x = x or 0, y = 0, z = 1 } } end
local function logged(v, kind) local n = 0; for _, entry in ipairs(v.log) do if entry[1] == kind then n = n + 1 end end; return n end

test('Plates map to os_devtools vehicle IDs only in the OS + digits format', function()
    assert(OSSecurity.CarService.plateId('OS000012') == 12 and OSSecurity.CarService.plateId(' OS000012 ') == 12)
    assert(not OSSecurity.CarService.plateId('ABC123') and not OSSecurity.CarService.plateId('OS') and not OSSecurity.CarService.plateId(nil))
end)

test('Installing in a vehicle needs the driver seat, engine off, ownership or a technician, the kit and a screwdriver; lock before alarm', function()
    local c, e, v = carFixture()
    local _, why = v.cars.installBegin(2, 'os_car_lock_kit'); assert(why:find('volante'))
    v.driving[2] = { plate = 'OS000012', engine = true, speed = 0 }
    _, why = v.cars.installBegin(2, 'os_car_lock_kit'); assert(why:find('motor'))
    v.driving[2].engine = false
    _, why = v.cars.installBegin(2, 'os_car_alarm_kit'); assert(why:find('cierre centralizado'))
    _, why = v.cars.installBegin(2, 'os_car_lock_kit'); assert(why == 'No tienes ese kit.')
    e.give(2, 'os_car_lock_kit'); e.give(2, 'os_car_alarm_kit')
    _, why = v.cars.installBegin(2, 'os_car_lock_kit'); assert(why:find('destornillador'))
    e.give(2, 'os_screwdriver')
    v.driving[5] = { plate = 'OS000012', engine = false, speed = 0 }; e.give(5, 'os_car_lock_kit'); e.give(5, 'os_screwdriver')
    _, why = v.cars.installBegin(5, 'os_car_lock_kit'); assert(why:find('dueno o un tecnico'))
    v.driving[2].plate = 'XX12345'; _, why = v.cars.installBegin(2, 'os_car_lock_kit'); assert(why:find('matricula OS'))
    v.driving[2].plate = 'OS000012'
    assert(v.cars.installBegin(2, 'os_car_lock_kit'))
    assert(not v.cars.installFinish(2, false) and e.count(2, 'os_car_lock_kit') == 1) -- cancelado: no gasta
    assert(v.cars.installBegin(2, 'os_car_lock_kit'))
    v.driving[2] = nil; assert(not v.cars.installFinish(2, true) and e.count(2, 'os_car_lock_kit') == 1) -- salio del coche
    v.driving[2] = { plate = 'OS000012', engine = false, speed = 0 }
    assert(v.cars.installBegin(2, 'os_car_lock_kit'))
    assert(v.cars.installFinish(2, true).kind == 'lock' and e.count(2, 'os_car_lock_kit') == 0 and e.count(2, 'os_screwdriver') == 1)
    _, why = v.cars.installBegin(2, 'os_car_lock_kit'); assert(why:find('ya tiene'))
    c.jobs[5] = { job = 'gruppe6', rank = 'tecnico', duty = true, characterId = e.holders[5] }
    e.give(5, 'os_car_alarm_kit')
    assert(v.cars.installBegin(5, 'os_car_alarm_kit')); assert(v.cars.installFinish(5, true).kind == 'alarm')
    local record = c.game.inventory.cars()['12']
    assert(record.lock and record.alarm and not record.locked and record.changes == 2 and record.plate == 'OS000012')
end)

test('Only the owner locks with the key fob (not an admin with another character); a stranger trying to enter a locked car sets the alarm off once and alerts the owner', function()
    local c, e, v = carFixture()
    v.driving[2] = { plate = 'OS000012', engine = false, speed = 0 }
    e.give(2, 'os_car_lock_kit'); e.give(2, 'os_screwdriver')
    assert(v.cars.installBegin(2, 'os_car_lock_kit')); assert(v.cars.installFinish(2, true))
    c.players[2].point = { x = 5, y = 0, z = 1 }; c.players[5].point = { x = 1, y = 0, z = 1 }
    local _, why = v.cars.toggle(5, carAt()); assert(why:find('llave'))
    c.players[2].point = { x = 40, y = 0, z = 1 }; assert(not v.cars.toggle(2, carAt())) -- lejos
    c.players[2].point = { x = 5, y = 0, z = 1 }
    local locked = assert(v.cars.toggle(2, carAt())); assert(locked.locked and v.log[#v.log][1] == 'locked' and v.log[#v.log][3] == true)
    assert(v.cars.desired('OS000012').locked == true and v.cars.desired('OS999999') == nil)
    _, why = v.cars.tamper(5, carAt()); assert(why == 'Esta cerrado.' and logged(v, 'alarm') == 0) -- sin alarma no suena
    _, why = v.cars.tamper(2, carAt()); assert(why:find('mando'))
    assert(v.cars.toggle(2, carAt())) -- abrir para instalar la alarma
    e.give(2, 'os_car_alarm_kit'); assert(v.cars.installBegin(2, 'os_car_alarm_kit')); assert(v.cars.installFinish(2, true))
    assert(v.cars.toggle(2, carAt()).message:find('alarma armada'))
    c.players[5].point = { x = 30, y = 0, z = 1 }; assert(not v.cars.tamper(5, carAt()) and logged(v, 'alarm') == 0) -- lejos
    c.players[5].point = { x = 1, y = 0, z = 1 }
    assert(v.cars.tamper(5, carAt()) and logged(v, 'alarm') == 1 and logged(v, 'notify') == 1)
    assert(v.cars.tamper(5, carAt()) and logged(v, 'alarm') == 1) -- ya esta sonando
    local opened = assert(v.cars.toggle(2, carAt())); assert(not opened.locked and v.log[#v.log - 1][1] == 'alarm' and v.log[#v.log - 1][3] == 0)
    assert(not v.cars.tamper(5, carAt())) -- abierto: nada
    local _, adminWhy = v.cars.toggle(4, carAt()); assert(adminWhy:find('llave')) -- administrador con otro personaje: sin llave
    assert(v.cars.toggle(2, carAt()).locked)
    assert(#v.cars.describe() == 1 and v.cars.describe()[1]:find('cerrado'))
end)

test('Inventory state rejects malformed vehicle security records', function()
    local base = { id = 12, plate = 'OS000012', lock = true, alarm = true, locked = false, changes = 2, updatedAt = 1 }
    assert(OSSecurity.InventoryState.car(base))
    local function bad(field, value) local r = util.copy(base); r[field] = value; return not OSSecurity.InventoryState.car(r) end
    assert(bad('lock', false) and bad('plate', 'OS 12') and bad('id', 0) and bad('locked', 'si') and bad('extra', 1))
end)

test('Without a kit the owner still locks with the key next to the car, and only the owner can start the engine', function()
    local c, e, v = carFixture()
    c.players[2].point = { x = 3, y = 0, z = 1 }; c.players[5].point = { x = 1, y = 0, z = 1 }
    local _, why = v.cars.toggle(2, { plate = 'XX1234', position = { x = 0, y = 0, z = 1 } }); assert(why:find('matricula OS'))
    c.players[2].point = { x = 6, y = 0, z = 1 }
    _, why = v.cars.toggle(2, carAt()); assert(why:find('puerta')) -- sin cierre centralizado: hay que estar junto al coche
    c.players[2].point = { x = 3, y = 0, z = 1 }
    local locked = assert(v.cars.toggle(2, carAt())); assert(locked.locked and v.log[#v.log][5] == false) -- sin destellos de mando
    assert(v.cars.desired('OS000012').locked == true)
    _, why = v.cars.tamper(5, carAt()); assert(why == 'Esta cerrado.')
    assert(not v.cars.toggle(2, carAt()).locked and v.cars.desired('OS000012') == nil)
    _, why = v.cars.engine(2); assert(why:find('volante'))
    v.driving[5] = { plate = 'OS000012', engine = false, speed = 0 }; _, why = v.cars.engine(5); assert(why:find('llave'))
    v.driving[2] = { plate = 'OS000012', engine = false, speed = 0 }; assert(v.cars.engine(2).owned)
    v.driving[5] = { plate = 'VMENU01', engine = false, speed = 0 }; assert(v.cars.engine(5).free) -- vehiculos ajenos a os_devtools: libres
    v.driving[4] = { plate = 'OS000012', engine = true, speed = 0 }; assert(not v.cars.engine(4)) -- administrador con otro personaje: sin llave
end)

-- Ganzua ---------------------------------------------------------------------------------------
test('Lockpicking a locked property door: difficulty by cylinder, minimum time per pin, breaks on failure and alerts the owner on success', function()
    local e = externalItems(); local c = fixture(nil, e); property(c, 7, 'ana')
    c.players[2].point = { x = 102, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT })) == 1)
    local alerts, roll = {}, 100
    local pick = OSSecurity.LockpickService.new({ holdings = c.game.holdings, world = function(source) return util.copy(c.players[source].point), 0 end,
        now = function() return c.core.time end, locks = c.game.locks, cars = { pickTarget = function() return nil end },
        random = function() return roll end, notifyOwner = function(alias, text) alerts[#alerts + 1] = { alias, text } end, audit = function() end })
    c.players[5].point = { x = 102.5, y = 100, z = 30 }
    local _, why = pick.begin(5, nil); assert(why == 'No tienes ganzua.')
    e.give(5, 'os_lockpick', 2)
    local challenge = assert(pick.begin(5, nil)); assert(challenge.kind == 'door' and challenge.pins == 3 and challenge.tier == 1)
    c.core.time = c.core.time + 1 -- 3 pines en 1 s: demasiado rapido
    roll = 1; local fast = assert(pick.finish(5, true)); assert(not fast.ok and fast.broken and e.count(5, 'os_lockpick') == 1)
    assert(pick.begin(5, nil)); c.core.time = c.core.time + 5; roll = 100
    local failed = assert(pick.finish(5, false)); assert(not failed.ok and not failed.broken and e.count(5, 'os_lockpick') == 1)
    assert(pick.begin(5, nil)); assert(pick.finish(5, 'cancel').ok == false and e.count(5, 'os_lockpick') == 1)
    assert(pick.begin(5, nil)); c.core.time = c.core.time + 5
    local opened = assert(pick.finish(5, true)); assert(opened.ok and c.game.inventory.doors().p7_1.locked == false)
    assert(#alerts == 1 and alerts[1][1] == 'ana' and alerts[1][2]:find('forzado'))
    local _, open = pick.begin(5, nil); assert(open:find('abierta'))
    -- Bombin de alta seguridad: mas pines y zona mas pequena.
    c.active[2] = { alias = 'ana' }; e.give(2, 'os_lock_kit_high'); e.give(2, 'os_screwdriver')
    assert(c.game.locks.changeBegin(2, 'os_lock_kit_high')); assert(c.game.locks.changeFinish(2, true))
    assert(c.game.locks.toggle(2).locked)
    local hard = assert(pick.begin(5, nil)); assert(hard.pins == 7 and hard.zone < challenge.zone)
    c.players[5].point = { x = 130, y = 100, z = 30 }; assert(not pick.finish(5, true)) -- se alejo
end)

test('Lockpicking a locked vehicle opens it, sets its alarm off and alerts the owner', function()
    local c, e, v = carFixture()
    v.driving[2] = { plate = 'OS000012', engine = false, speed = 0 }
    e.give(2, 'os_car_lock_kit'); e.give(2, 'os_car_alarm_kit'); e.give(2, 'os_screwdriver')
    assert(v.cars.installBegin(2, 'os_car_lock_kit')); assert(v.cars.installFinish(2, true))
    assert(v.cars.installBegin(2, 'os_car_alarm_kit')); assert(v.cars.installFinish(2, true))
    c.players[2].point = { x = 5, y = 0, z = 1 }; assert(v.cars.toggle(2, carAt()).locked)
    local alerts = {}
    local pick = OSSecurity.LockpickService.new({ holdings = c.game.holdings, world = function(source) return util.copy(c.players[source].point), 0 end,
        now = function() return c.core.time end, locks = { pickTarget = function() return nil, 'No hay ninguna puerta con cerradura a tu alcance.' end },
        cars = v.cars, random = function() return 100 end, notifyOwner = function(alias, text) alerts[#alerts + 1] = { alias, text } end, audit = function() end })
    e.give(5, 'os_lockpick'); c.players[5].point = { x = 1, y = 0, z = 1 }
    local challenge = assert(pick.begin(5, carAt())); assert(challenge.kind == 'vehicle' and challenge.pins == 5)
    c.core.time = c.core.time + 10
    assert(pick.finish(5, true).ok)
    assert(not c.game.inventory.cars()['12'].locked and logged(v, 'alarm') == 1 and alerts[1][1] == 'ana')
    local _, none = pick.begin(5, carAt()); assert(none:find('cerrado'))
end)

test('Hotwiring: without the key a screwdriver allows a hotwire; difficulty by security, alarm and owner alert, owner locking revokes it', function()
    local c, e, v = carFixture()
    v.driving[5] = { plate = 'OS000012', engine = false, speed = 0 }
    local _, why, can = v.cars.engine(5); assert(why:find('llave') and not can) -- sin destornillador: no hay puente
    e.give(5, 'os_screwdriver')
    _, why, can = v.cars.engine(5); assert(why:find('puente') and can == true)
    local plain = assert(v.cars.hotwireBegin(5)); assert(plain.tier == 1 and plain.decoys == 2)
    assert(not v.cars.hotwireFinish(5, true)) -- demasiado rapido
    assert(v.cars.hotwireBegin(5)); c.core.time = c.core.time + 10
    v.driving[5] = nil; assert(not v.cars.hotwireFinish(5, true)) -- salio del coche
    v.driving[5] = { plate = 'OS000012', engine = false, speed = 0 }
    assert(v.cars.hotwireBegin(5)); c.core.time = c.core.time + 10
    assert(not v.cars.hotwireFinish(5, false))
    assert(v.cars.hotwireBegin(5)); c.core.time = c.core.time + 10
    assert(v.cars.hotwireFinish(5, true).message:find('Puente') and v.cars.engine(5).hotwired)
    assert(logged(v, 'notify') == 1)
    -- El dueno instala cierre y alarma y cierra con su llave: el puente deja de valer y la siguiente vez es mas dificil.
    v.driving[2] = { plate = 'OS000012', engine = false, speed = 0 }
    e.give(2, 'os_car_lock_kit'); e.give(2, 'os_car_alarm_kit'); e.give(2, 'os_screwdriver')
    assert(v.cars.installBegin(2, 'os_car_lock_kit')); assert(v.cars.installFinish(2, true))
    assert(v.cars.installBegin(2, 'os_car_alarm_kit')); assert(v.cars.installFinish(2, true))
    c.players[2].point = { x = 1, y = 0, z = 1 }; assert(v.cars.toggle(2, carAt()).locked)
    assert(not v.cars.engine(5)) -- sin puente
    assert(v.cars.toggle(2, carAt()).locked == false) -- abierto otra vez (lo forzaria con ganzua)
    v.driving[2] = nil
    local hard = assert(v.cars.hotwireBegin(5)); assert(hard.tier == 3 and hard.band < plain.band)
    assert(logged(v, 'notify') == 2) -- aviso: estan intentando arrancarlo
end)

test('Vehicle key and tamper require the same routing bucket as the vehicle', function()
    local c, e, v = carFixture()
    c.players[2].point = { x = 3, y = 0, z = 1 }; c.players[5].point = { x = 1, y = 0, z = 1 }
    local elsewhere = carAt(); elsewhere.bucket = 3
    assert(not v.cars.toggle(2, elsewhere)) -- otro bucket: no llega
    assert(v.cars.toggle(2, carAt()).locked)
    assert(not v.cars.tamper(5, elsewhere))
    assert(c.game.inventory.car('12').locked == true and c.game.inventory.car('99') == nil)
end)


-- Zonas de montaje desde la tablet (Instalaciones) ----------------------------------------------
test('Tablet zones: the installer picks a nearby client, marks the zone with the viewfinder and installs on it from its card', function()
    local c = fixture(); kit(c); assert(c.loaded, c.loadError)
    c.players[1].point = { x = 0, y = 0, z = 1 }; c.players[2].point = { x = 3, y = 0, z = 1 }
    for _, id in ipairs({ 3, 4, 5 }) do c.players[id].point = { x = 300, y = 0, z = 1 } end
    c.assets.properties[7] = { id = 7, owner = 'ana', position = { x = 10, y = 0, z = 1 } }; c.active[2] = { alias = 'ana' }
    local function reopen() c.core.time = c.core.time + 11; return open(c, 1, 'operations') end
    local session = open(c, 1, 'operations')
    local listed = call(c, 1, session, 'zones'); assert(listed.ok, listed.error)
    assert(#listed.data.zones == 0 and #listed.data.clients == 2 and listed.data.clients[1].self and listed.data.clients[2].id == 2)
    local _, why = c.game.zoneAt(1, { radius = 0.5, position = { x = 1, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0 } })
    assert(why:find('caducado')) -- sin reservar el marcado no se registra nada
    assert(not call(c, 1, session, 'zone_begin', { client = 5 }).ok) -- el cliente debe estar al lado
    local begun = call(c, 1, session, 'zone_begin', { client = 2 }); assert(begun.ok, begun.error)
    assert(begun.data.id == 'zona_1' and begun.data.client == 'Jugador2' and begun.data.site:find('Propiedad 7', 1, true))
    assert(not call(c, 1, session, 'zones').ok) -- la tablet se cierra para marcar
    local bad = c.game.zoneAt(1, { radius = 0.5, position = { x = 40, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0 } })
    assert(not bad) -- demasiado lejos (y el marcado se consume)
    begun = call(c, 1, reopen(), 'zone_begin', { client = 2 }); assert(begun.ok)
    local done = assert(c.game.zoneAt(1, { radius = 0.5, position = { x = 1, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0.0000001 }, place = 'Low Power St<b>' }))
    assert(done.id == 'zona_1')
    local zone = c.game.inventory.snapshot().anchors.zona_1
    assert(zone.owner == c.players[2].principal and zone.installer == c.players[1].principal and zone.site.id == 7)
    assert(zone.place == 'Low Power Stb' and zone.client == 'Jugador2' and zone.normal.z == 0 and zone.radius == 0.5)
    session = reopen()
    listed = call(c, 1, session, 'zones')
    local card = listed.data.zones[1]
    assert(card.id == 'zona_1' and card.status == 'free' and card.surface == 'wall' and card.size == 1 and card.mine and card.deletable)
    assert(card.site:find('Propiedad 7', 1, true) and card.distance == 1)
    assert(not call(c, 1, session, 'zone_install', { anchorId = 'zona_1', kit = 'os_alarm_kit' }).ok) -- no tiene ese kit
    c.players[1].point = { x = 30, y = 0, z = 1 }
    local far = call(c, 1, session, 'zone_install', { anchorId = 'zona_1', kit = 'os_cctv_kit' }); assert(not far.ok and far.error:find('Acercate'))
    c.players[1].point = { x = 0, y = 0, z = 1 }
    session = reopen()
    local placement = call(c, 1, session, 'zone_install', { anchorId = 'zona_1', kit = 'os_cctv_kit' })
    assert(placement.ok and #placement.placement.mounts == 1 and placement.placement.mounts[1].id == 'zona_1')
    local installed = call(c, 1, session, 'place_confirm', proposal('zona_1')); assert(installed.ok, installed.error)
    assert(c.game.inventory.site(installed.data.id).id == 7)
    listed = call(c, 1, session, 'zones')
    assert(listed.data.zones[1].status == 'installed' and listed.data.zones[1].deviceId == installed.data.id and not listed.data.zones[1].deletable)
    assert(not call(c, 1, session, 'zone_delete', { anchorId = 'zona_1' }).ok) -- usada: no se borra
end)

test('Tablet zones: only installers see their zones, other profiles cannot mark, and unused zones can be deleted', function()
    local c = fixture(); kit(c); grant(c, 3, 'g6_operations_tablet'); grant(c, 2, 'g6_client_tablet'); grant(c, 4, 'g6_operations_tablet')
    for id = 1, 5 do c.players[id].point = { x = id, y = 0, z = 1 } end
    anchor(c, 'otra', 4)
    local supervisor = open(c, 3, 'operations')
    assert(not call(c, 3, supervisor, 'zones').ok and not call(c, 3, supervisor, 'zone_begin', { client = 3 }).ok)
    local client = open(c, 2, 'client'); assert(not call(c, 2, client, 'zones').ok)
    local session = open(c, 1, 'operations')
    assert(#call(c, 1, session, 'zones').data.zones == 0) -- la zona de otro tecnico no aparece
    assert(not call(c, 1, session, 'zone_delete', { anchorId = 'otra' }).ok)
    assert(call(c, 1, session, 'zone_begin', { client = 1 }).ok) -- para si mismo
    assert(c.game.zoneAt(1, { radius = 3, position = { x = 1, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0 } }) == nil) -- tamano fuera de rango
    assert(call(c, 1, open(c, 1, 'operations'), 'zone_begin', { client = 1 }).ok)
    assert(c.game.zoneAt(1, { radius = 1, position = { x = 1, y = 0, z = 3 }, normal = { x = 0, y = 0, z = -1 } }))
    session = open(c, 1, 'operations')
    local zones = call(c, 1, session, 'zones').data.zones
    assert(#zones == 1 and zones[1].id == 'zona_1' and zones[1].surface == 'ceiling' and zones[1].client == 'Jugador1')
    assert(call(c, 1, session, 'zone_delete', { anchorId = 'zona_1' }).ok and not c.game.inventory.snapshot().anchors.zona_1)
    local admin = open(c, 4, 'operations')
    assert(#call(c, 4, admin, 'zones').data.zones == 1) -- el administrador ve todas
    assert(not OSSecurity.InventoryState.anchor({ id = 'x', owner = c.players[1].principal, installer = c.players[1].principal,
        position = { x = 0, y = 0, z = 0 }, normal = { x = 1, y = 0, z = 0 }, radius = 1, bucket = 0, place = '<script>' }))
end)

test('Client tablet: own property doors, own protected vehicles with GPS position and alarm incidents', function()
    local c = fixture(); grant(c, 2, 'g6_client_tablet'); grant(c, 5, 'g6_client_tablet'); c.aces[5][config.Ace.client] = true
    property(c, 7, 'ana'); c.active[2] = { alias = 'ana' }; c.active[5] = { alias = 'luis' }
    c.players[2].point = { x = 101, y = 100, z = 30 }
    assert(c.game.locks.report(2, doorReport(7, { FRONT, BACK })) == 2)
    c.vehicleAssets = { [12] = { id = 12, plate = 'OS000012', owner = 'ana' }, [13] = { id = 13, plate = 'OS000013', owner = 'luis' } }
    c.vehicleSpots = { OS000012 = { x = 5, y = 6, z = 7 } }
    for _, id in ipairs({ 12, 13 }) do
        assert(c.game.inventory.apply({ kind = 'car', carId = tostring(id), car = { id = id, plate = ('OS%06d'):format(id), lock = true, alarm = id == 12,
            locked = true, changes = 1, updatedAt = c.core.time } }))
    end
    local session = open(c, 2, 'client')
    local doors = call(c, 2, session, 'doors'); assert(doors.ok, doors.error)
    assert(#doors.data.items == 2 and doors.data.items[1].locked and doors.data.items[1].site:find('Propiedad 7', 1, true) and doors.data.items[1].level == 1)
    local cars = call(c, 2, session, 'trackers').data.items
    assert(#cars == 1 and cars[1].plate == 'OS000012' and cars[1].alarm and cars[1].position.x == 5)
    local other = open(c, 5, 'client')
    assert(#call(c, 5, other, 'doors').data.items == 0 and call(c, 5, other, 'trackers').data.items[1].position == nil)
    local device = alarmPanel(c, 2)
    session = open(c, 2, 'client')
    assert(call(c, 2, session, 'alarm', { deviceId = device.id, action = 'arm' }).ok)
    local incidents = call(c, 2, session, 'incidents'); assert(incidents.ok, incidents.error)
    assert(#incidents.data.items >= 1 and incidents.data.items[1].kind == 'armed' and incidents.data.items[1].deviceId == device.id)
    assert(#call(c, 5, open(c, 5, 'client'), 'incidents').data.items == 0)
    grant(c, 1, 'g6_operations_tablet'); local operations = open(c, 1, 'operations')
    assert(not call(c, 1, operations, 'doors').ok and not call(c, 1, operations, 'devices', { module = 'locks' }).ok)
end)

-- Tienda Gruppe Sechs ------------------------------------------------------------------------------
local COUNTER = { x = 10.17, y = -671.55, z = 33.45 }
test('Shop: catalog only at the counter; public items for anyone, staff items only for on-duty G6 or professional ACE', function()
    local c = fixture(); assert(c.loaded, c.loadError)
    c.players[2].point = util.copy(COUNTER); c.wallet[2] = { bank = 5000, cash = 100 }
    local catalog = assert(c.game.shop.catalog(2))
    assert(not catalog.staff and catalog.balance.bank == 5000 and catalog.maxQuantity == 10)
    local function find(list, item) for _, p in ipairs(list) do if p.item == item then return p end end end
    assert(find(catalog.products, 'os_lock_kit').allowed and not find(catalog.products, 'os_cctv_kit').allowed and not find(catalog.products, 'os_lockpick'))
    c.players[1].point = util.copy(COUNTER)
    assert(assert(c.game.shop.catalog(1)).staff) -- ACE de tecnico
    c.players[5].point = util.copy(COUNTER); c.jobs[5] = { job = 'gruppe6', rank = 'tecnico', duty = true }
    assert(assert(c.game.shop.catalog(5)).staff) -- empleo de servicio
    c.jobs[5].duty = false; assert(not assert(c.game.shop.catalog(5)).staff)
    c.players[2].point = { x = 50, y = -671.55, z = 33.45 }
    local _, far = c.game.shop.catalog(2); assert(far:find('mostrador'))
    c.players[2].point = util.copy(COUNTER); c.players[2].bucket = 3; assert(not c.game.shop.catalog(2))
    c.players[2].bucket = 0; c.moneyDown = true
    local _, down = c.game.shop.catalog(2); assert(down:find('Pago no disponible'))
end)

test('Shop: purchases are validated, charged once and delivered to the local ledger', function()
    local c = fixture(); assert(c.loaded, c.loadError)
    c.players[2].point = util.copy(COUNTER); c.wallet[2] = { bank = 5000, cash = 100 }
    local function buy(cart, account) c.core.time = c.core.time + 3; return c.game.shop.buy(2, cart, account) end
    local done = assert(buy({ { item = 'os_lock_kit', amount = 2 }, { item = 'os_screwdriver', amount = 1 } }, 'bank'))
    assert(done.total == 1760 and c.wallet[2].bank == 3240 and done.balance.bank == 3240 and not done.partial)
    assert(count(c, 2, 'os_lock_kit') == 2 and count(c, 2, 'os_screwdriver') == 1)
    local _, why = buy({ { item = 'os_cctv_kit', amount = 1 } }, 'bank'); assert(why:find('personal'))
    _, why = buy({ { item = 'os_lockpick', amount = 1 } }, 'bank'); assert(why == 'Producto no disponible.')
    _, why = buy({ { item = 'os_lock_kit', amount = 11 } }, 'bank'); assert(why:find('Maximo'))
    _, why = buy({ { item = 'os_battery', amount = 1 }, { item = 'os_battery', amount = 1 } }, 'bank'); assert(why == 'Producto no disponible.')
    _, why = buy({ { item = 'os_battery', amount = 1, price = 0 } }, 'bank'); assert(why == 'Carrito no valido.')
    _, why = buy({ { item = 'os_battery', amount = 1 } }, 'crypto'); assert(why:find('Forma de pago'))
    _, why = buy({ { item = 'os_lock_kit_high', amount = 1 } }, 'cash'); assert(why == 'Saldo insuficiente.' and c.wallet[2].cash == 100)
    assert(c.wallet[2].bank == 3240 and count(c, 2, 'os_cctv_kit') == 0) -- los rechazos no cobran
    c.core.time = c.core.time + 3
    assert(c.game.shop.buy(2, { { item = 'os_battery', amount = 1 } }, 'cash'))
    _, why = c.game.shop.buy(2, { { item = 'os_battery', amount = 1 } }, 'cash'); assert(why:find('Espera')) -- una compra cada 2 s
    c.players[1].point = util.copy(COUNTER); c.wallet[1] = { bank = 3000, cash = 0 }
    assert(c.game.shop.buy(1, { { item = 'os_cctv_kit', amount = 1 }, { item = 'os_drill', amount = 1 } }, 'bank'))
    assert(c.wallet[1].bank == 3000 - 950 - 380)
end)

test('Shop: with the character inventory, undeliverable items are refunded and a failed refund is reported', function()
    local e = externalItems(); local c = fixture(nil, e); assert(c.loaded, c.loadError)
    c.players[2].point = util.copy(COUNTER); c.wallet[2] = { bank = 10000, cash = 0 }
    e.failItem = 'os_car_alarm_kit'
    local result = assert(c.game.shop.buy(2, { { item = 'os_car_lock_kit', amount = 1 }, { item = 'os_car_alarm_kit', amount = 2 } }, 'bank'))
    assert(result.partial and result.message:find('Devueltos $3800', 1, true) and result.total == 1250)
    assert(c.wallet[2].bank == 10000 - 1250 and e.count(2, 'os_car_lock_kit') == 1 and e.count(2, 'os_car_alarm_kit') == 0)
    e.failItem = nil; e.addFails = true; c.refundFails = true; c.core.time = c.core.time + 3
    result = assert(c.game.shop.buy(2, { { item = 'os_battery', amount = 2 } }, 'bank'))
    assert(result.partial and result.message:find('administrador') and c.wallet[2].bank == 8750 - 90)
    local logged = false
    for _, reply in ipairs(c.replies) do if reply[2]:find('PENDIENTE') then logged = true end end
    assert(logged)
end)

test('Shop: an admin moves the counter to the Union Depository road or to their position; it persists and is broadcast', function()
    local c = fixture(); assert(c.loaded, c.loadError)
    local moved = {}
    c.game.shop = OSSecurity.ShopService.new({ holdings = c.game.holdings, inventory = c.game.inventory, identity = c.game.identity,
        world = function(source) local p = c.players[source]; return util.copy(p.point), p.bucket end, now = function() return c.core.time end,
        isStaff = function() return false end, isAdmin = function(source) return source == 4 end, audit = function() end,
        files = { read = function(path) return c.core.files[path] end, write = function(path, content) c.core.files[path] = content; return true end },
        moved = function(list) moved[#moved + 1] = list end,
        money = { available = function() return true end, balance = function() return { bank = 0, cash = 0 } end } })
    local _, why = c.game.shop.move(2, 'here'); assert(why:find('ossecurity.admin'))
    _, why = c.game.shop.move(4, 'road', { x = 900, y = 0, z = 30 }); assert(why:find('carretera'))
    assert(not c.game.shop.move(4, 'road', { x = 'a', y = 0, z = 0 }))
    local message = assert(c.game.shop.move(4, 'road', { x = 40.123, y = -700.456, z = 29.9 }))
    assert(message:find('40.12') and #moved == 1 and moved[1][1].x == 40.12 and moved[1][1].y == -700.46)
    c.players[2].point = { x = 40.12, y = -700.46, z = 29.9 }; c.wallet[2] = { bank = 100, cash = 0 }
    assert(c.game.shop.catalog(2)) -- el mostrador ya esta en la calle
    c.players[4].point = { x = 5, y = 5, z = 30 }; c.players[4].bucket = 2
    _, why = c.game.shop.move(4, 'here'); assert(why:find('bucket'))
    c.players[4].bucket = 0; assert(c.game.shop.move(4, 'here'))
    local reloaded = OSSecurity.ShopService.new({ files = { read = function(path) return c.core.files[path] end, write = function() return true end },
        isAdmin = function() return false end, world = function() return nil end, now = function() return 0 end })
    local location = reloaded.locations()[1]
    assert(location.x == 5 and location.y == 5 and location.id == 'union') -- tras reiniciar sigue donde se dejo
end)

test('Live CCTV: only viewers of an installed, powered camera get its framing; worn optics add noise and failures cut the signal', function()
    local c = fixture(); kit(c); anchor(c); grant(c, 2, 'g6_client_tablet')
    local session = open(c, 1, 'operations')
    assert(call(c, 1, session, 'place_begin').ok)
    local installed = call(c, 1, session, 'place_confirm', proposal()); assert(installed.ok, installed.error)
    local id = installed.data.id
    local client = open(c, 2, 'client')
    local summary = call(c, 2, client, 'device', { deviceId = id }); assert(summary.data.live == true and summary.data.liveReason == nil)
    local live = call(c, 2, client, 'live', { deviceId = id }); assert(live.ok, live.error)
    assert(live.data.position.x == 1 and live.data.normal.x == -1 and live.data.noise == 0 and #live.data.cameras == 1 and live.data.index == 1)
    grant(c, 3, 'g6_operations_tablet')
    local stranger = open(c, 3, 'operations'); assert(not call(c, 3, stranger, 'live', { deviceId = id }).ok) -- sin acceso al dispositivo
    assert(c.core.registry.service(0, id, 'fault', { slot = 'optics', health = 40 }))
    live = call(c, 2, client, 'live', { deviceId = id }); assert(live.ok and live.data.noise == 0.45)
    assert(c.core.registry.service(0, id, 'fault', { slot = 'optics', health = 0 }))
    live = call(c, 2, client, 'live', { deviceId = id }); assert(not live.ok and live.error:find('optica'))
    summary = call(c, 2, client, 'device', { deviceId = id }); assert(not summary.data.live and summary.data.liveReason:find('optica'))
    local noCamera = alarmPanel(c, 2)
    assert(not call(c, 2, client, 'live', { deviceId = noCamera.id }).ok)
end)

-- Ordenes de trabajo ---------------------------------------------------------------------------------
test('Work orders: a client requests, an on-duty technician accepts and bills, the client pays and the technician gets his share', function()
    local c = fixture(); assert(c.loaded, c.loadError)
    grant(c, 2, 'g6_client_tablet'); grant(c, 1, 'g6_operations_tablet'); grant(c, 3, 'g6_operations_tablet')
    c.assets.properties[7] = { id = 7, owner = 'ana', position = { x = 50, y = 60, z = 30 } }; c.active[2] = { alias = 'ana' }
    c.wallet[2] = { bank = 5000, cash = 0 }; c.wallet[1] = { bank = 0, cash = 0 }
    local client = open(c, 2, 'client')
    local list = call(c, 2, client, 'requests'); assert(list.ok, list.error)
    assert(#list.data.items == 0 and #list.data.places == 2 and list.data.places[2].value == 'site:property:7' and list.data.places[2].label:find('Propiedad 7', 1, true) and #list.data.kinds == 6)
    assert(not call(c, 2, client, 'request_create', { kind = 'cctv', place = 'here', note = '   ' }).ok) -- sin descripcion
    assert(not call(c, 2, client, 'request_create', { kind = 'hack', place = 'here', note = 'x' }).ok)
    assert(not call(c, 2, client, 'request_create', { kind = 'cctv', place = 'site:property:99', note = 'Camara' }).ok) -- no es suya
    local created = call(c, 2, client, 'request_create', { kind = 'cctv', place = 'site:property:7', note = 'Dos camaras <b>en la entrada</b>' })
    assert(created.ok, created.error) assert(created.data.id == 'ot_000001')
    local order = c.game.inventory.orders().ot_000001
    assert(order.status == 'open' and order.position.x == 50 and order.place:find('Propiedad 7', 1, true) and not order.note:find('[<>]') and order.note:find('entrada'))
    assert(not call(c, 2, client, 'request_create', { kind = 'alarm', place = 'here', note = 'Otra' }).ok) -- una cada 10 s
    local supervisor = open(c, 3, 'operations')
    assert(not call(c, 3, supervisor, 'order_accept', { orderId = 'ot_000001' }).ok) -- supervisor sin perfil de instalacion
    local tech = open(c, 1, 'operations')
    local orders = call(c, 1, tech, 'orders'); assert(orders.ok and #orders.data.items == 1 and orders.data.items[1].clientName == 'Jugador2')
    assert(not call(c, 1, tech, 'order_bill', { orderId = 'ot_000001', price = 500 }).ok) -- primero hay que aceptarla
    local accepted = call(c, 1, tech, 'order_accept', { orderId = 'ot_000001' }); assert(accepted.ok and accepted.data.position.x == 50)
    assert(c.game.inventory.orders().ot_000001.techName == 'Jugador1')
    assert(not call(c, 1, tech, 'order_bill', { orderId = 'ot_000001', price = 999999 }).ok)
    assert(call(c, 1, tech, 'order_bill', { orderId = 'ot_000001', price = 1000 }).ok)
    assert(not call(c, 2, client, 'request_cancel', { orderId = 'ot_000001' }).ok) -- facturada: ya no se cancela
    local paid = call(c, 2, client, 'request_pay', { orderId = 'ot_000001' }); assert(paid.ok, paid.error)
    order = c.game.inventory.orders().ot_000001
    assert(order.status == 'paid' and order.payout == 'done' and c.wallet[2].bank == 4000 and c.wallet[1].bank == 600)
    assert(not call(c, 2, client, 'request_pay', { orderId = 'ot_000001' }).ok) -- no se paga dos veces
end)

test('Work orders: offline technicians are paid later, clients cancel their own open orders and have a limit of open requests', function()
    local c = fixture(); assert(c.loaded, c.loadError)
    grant(c, 2, 'g6_client_tablet'); grant(c, 1, 'g6_operations_tablet'); grant(c, 5, 'g6_client_tablet'); c.aces[5][config.Ace.client] = true
    c.wallet[2] = { bank = 3000, cash = 0 }; c.wallet[1] = { bank = 100, cash = 0 }
    local client = open(c, 2, 'client')
    local function create(note) c.core.time = c.core.time + 11; return call(c, 2, client, 'request_create', { kind = 'repair', place = 'here', note = note }) end
    assert(create('Uno').ok and create('Dos').ok and create('Tres').ok)
    local fourth = create('Cuatro'); assert(not fourth.ok and fourth.error:find('3'))
    assert(call(c, 2, client, 'request_cancel', { orderId = 'ot_000003' }).ok and c.game.inventory.orders().ot_000003.status == 'cancelled')
    local other = open(c, 5, 'client'); assert(not call(c, 5, other, 'request_cancel', { orderId = 'ot_000001' }).ok) -- no es suya
    local tech = open(c, 1, 'operations')
    assert(call(c, 1, tech, 'order_accept', { orderId = 'ot_000001' }).ok and call(c, 1, tech, 'order_bill', { orderId = 'ot_000001', price = 2000 }).ok)
    c.players[1].connected = false
    client = open(c, 2, 'client')
    assert(call(c, 2, client, 'request_pay', { orderId = 'ot_000001' }).ok)
    assert(c.game.inventory.orders().ot_000001.payout == 'pending' and c.wallet[1].bank == 100)
    c.players[1].connected = true; c.core.time = c.core.time + 11
    tech = open(c, 1, 'operations')
    local listed = call(c, 1, tech, 'orders'); assert(listed.ok)
    assert(c.wallet[1].bank == 100 + 1200 and c.game.inventory.orders().ot_000001.payout == 'done')
    c.wallet[2].bank = 10
    assert(call(c, 1, tech, 'order_accept', { orderId = 'ot_000002' }).ok and call(c, 1, tech, 'order_bill', { orderId = 'ot_000002', price = 500 }).ok)
    client = open(c, 2, 'client')
    local poor = call(c, 2, client, 'request_pay', { orderId = 'ot_000002' }); assert(not poor.ok and poor.error:find('Saldo'))
    assert(c.game.inventory.orders().ot_000002.status == 'billed')
    assert(not OSSecurity.InventoryState.order({ id = 'ot_000009', kind = 'cctv', status = 'billed', client = c.players[2].principal,
        note = 'x', place = 'y', position = { x = 0, y = 0, z = 0 }, createdAt = 1, updatedAt = 1 })) -- facturada sin tecnico ni precio
end)

test('Character ownership: devices belong to the active character, so another character of the same account sees nothing', function()
    local e = externalItems(); e.characters = true
    local c = fixture(nil, e); assert(c.loaded, c.loadError)
    local own = create(c.core, 'cctv_camera', { owner = 'char:oschar_0000000002' })
    create(c.core, 'cctv_camera', { owner = c.players[2].principal }) -- dato por cuenta: ya no es de nadie
    e.give(2, 'g6_client_tablet')
    local listed = call(c, 2, open(c, 2, 'client'), 'devices', { offset = 0 })
    assert(listed.ok and listed.data.total == 1 and listed.data.items[1].id == own.id)
    assert(not codec.encode(listed):find('char:', 1, true))
    e.holders[2] = 'oschar_0000000009'; e.give(2, 'g6_client_tablet') -- mismo jugador, otro personaje
    local other = open(c, 2, 'client')
    assert(call(c, 2, other, 'devices', { offset = 0 }).data.total == 0)
    local requests = call(c, 2, other, 'requests'); assert(requests.ok and #requests.data.items == 0)
    e.holders[2] = nil
    nextRequest = nextRequest + 1
    assert(not c.game.handle(2, { id = nextRequest, action = 'open', args = { kind = 'client' } }).ok)
end)

test('Character ownership: on start, account data moves to the only character that installed it and survives restarts', function()
    local e = externalItems(); local c = fixture(nil, e); e.kit(1)
    assert(c.game.inventory.apply({ kind = 'anchor', anchor = { id = 'mount_1', owner = c.players[1].principal, installer = c.players[1].principal,
        position = { x = 1, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0 }, radius = 0.75, bucket = 0 } }))
    local operations = open(c, 1, 'operations')
    assert(call(c, 1, operations, 'place_begin').ok)
    local placed = call(c, 1, operations, 'place_confirm', proposal())
    assert(placed.ok, placed.error)
    local deviceId = c.game.inventory.snapshot().installations.g6i_0000000001.deviceId
    local license = c.players[1].principal
    e.characters = true
    local moved = fixture(c.core.files, e); assert(moved.loaded, moved.loadError)
    local snapshot = moved.game.inventory.snapshot()
    local char = 'char:oschar_0000000001'
    assert(snapshot.accounts[license] == nil and snapshot.accounts[char].grants[deviceId] == 'technician')
    assert(snapshot.anchors.mount_1.owner == char and snapshot.installations.g6i_0000000001.owner == char and snapshot.owners[deviceId] == char)
    moved.aces[1][config.Ace.client] = true; e.give(1, 'g6_client_tablet')
    local mine = call(moved, 1, open(moved, 1, 'client'), 'devices', { offset = 0 })
    assert(mine.ok and mine.data.total == 1 and mine.data.items[1].id == deviceId)
    local again = fixture(c.core.files, e); assert(again.loaded, again.loadError)
    assert(again.game.inventory.snapshot().revision == snapshot.revision) -- sin repetir la migracion
    e.holders[1] = 'oschar_0000000009'; e.give(1, 'g6_client_tablet'); again.aces[1][config.Ace.client] = true
    assert(call(again, 1, open(again, 1, 'client'), 'devices', { offset = 0 }).data.total == 0)
end)
