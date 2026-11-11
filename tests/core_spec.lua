local failures, total = 0, 0
local function test(name, run)
    total = total + 1
    local ok, err = pcall(run)
    if not ok then failures = failures + 1 end
    __testResult(name, ok, tostring(err))
end

local root = '/repo/'
local scripts, clientScripts, sharedScripts = {}, {}, {}
local declarations = {}
local nuiPage, nuiFiles, strictMode
local manifestEnvironment = setmetatable({
    fx_version = function(value) declarations.fx_version = value end,
    game = function(value) declarations.game = value end,
    author = function() end,
    description = function() end,
    shared_scripts = function(value) sharedScripts = value end,
    client_script = function(value) clientScripts = { value } end,
    client_scripts = function(value) clientScripts = value end,
    ui_page = function(value) nuiPage = value end,
    files = function(value) nuiFiles = value end,
    nui_callback_strict_mode = function(value) strictMode = value end,
    server_scripts = function(value) scripts = value end
}, { __index = function(_, key) error('Unexpected manifest declaration: ' .. key) end })
assert(loadfile(root .. 'fxmanifest.lua', 't', manifestEnvironment))()
for _, file in ipairs(sharedScripts) do dofile(root .. file) end
for _, file in ipairs(scripts) do if file ~= 'server/main.lua' then dofile(root .. file) end end

local util, validation = OSSecurity.Util, OSSecurity.DeviceValidation
local defaults = OSSecurity.ServerConfig
local codec = OSSecurity.JsonCodec

local function equal(left, right)
    assert(util.equal(left, right), 'Values differ')
end

local function fixture(files, limits)
    local context = { files = files or {}, writes = 0, logs = {}, time = 1700000000, allowed = { [7] = true } }
    context.limits = util.copy(limits or defaults)
    context.permissions = OSSecurity.Permissions.new({
        ace = 'ossecurity.admin', limits = context.limits,
        isAceAllowed = function(source, ace) return ace == 'ossecurity.admin' and context.allowed[source] == true end,
        now = function() return context.time end
    })
    context.store = OSSecurity.JsonStorage.new({
        base = 'data/devices', limits = context.limits,
        read = function(path)
            if context.readError then return nil, 'Injected read failure' end
            return context.files[path]
        end,
        write = function(path, content)
            context.writes = context.writes + 1
            if context.writeException then error('Injected write exception') end
            if context.writeFailure then
                if context.partialWrite then context.files[path] = '{partial' end
                if context.completeWriteBeforeError then context.files[path] = content end
                return false
            end
            context.files[path] = context.truncate and content:sub(1, 10) or content
            return true
        end,
        encode = function(value)
            if context.encodeError then error('Injected encode failure') end
            return codec.encode(value)
        end,
        decode = codec.decode,
        log = function(message) context.logs[#context.logs + 1] = message end
    })
    context.registry = OSSecurity.DeviceRegistry.new({
        store = context.store, limits = context.limits, authorize = context.permissions.authorize,
        now = function() return context.time end
    })
    context.loaded, context.loadError = context.registry.load()
    return context
end

local function create(context, deviceType, extra)
    local input = extra or {}
    input.type = deviceType or 'cctv_camera'
    local device, err = context.registry.create(0, input)
    assert(device, err)
    return device
end

local function transition(context, id, state)
    local device, err = context.registry.setState(0, id, state)
    assert(device, err)
    return device
end

test('Manifest paths, loading order, version and Lua 5.4 syntax', function()
    equal(declarations, { fx_version = 'cerulean', game = 'gta5' })
    for _, file in ipairs(__luaFiles) do assert(loadfile(root .. file)) end
    for _, file in ipairs(clientScripts) do assert(loadfile(root .. file)) end
    assert(OSSecurity.Config.Version == '0.14.0')
    assert(nuiPage == 'web/index.html' and strictMode == 'true')
    for _, file in ipairs(nuiFiles) do local handle = assert(io.open(root .. file, 'rb')); handle:close() end
    assert(#scripts > 0 and scripts[#scripts] == 'server/main.lua')
end)

test('Missing files initialize an empty registry without writing', function()
    local c = fixture()
    assert(c.loaded and c.writes == 0)
    local result = assert(c.registry.list(0))
    assert(result.total == 0 and #result.items == 0)
end)

test('All seven catalog types create valid logical devices', function()
    local c = fixture()
    local types = OSSecurity.DeviceCatalog.list()
    assert(#types == 7)
    for _, deviceType in ipairs(types) do
        local device = create(c, deviceType)
        assert(device.type == deviceType and device.model == 'generic' and device.state == 'registered')
        assert(device.position == nil and device.rotation == nil and device.owner == nil)
        assert(validation.device(device, c.limits))
    end
end)

test('Unknown types and client-style object replacement are rejected', function()
    local c = fixture()
    assert(not c.registry.create(0, { type = 'unknown' }))
    for _, field in ipairs({ 'id', 'state', 'createdAt', 'schemaVersion', 'history', 'condition' }) do
        assert(not c.registry.create(0, { type = 'bodycam', [field] = 'forged' }))
    end
    assert(c.writes == 0)
end)

test('Identifiers are unique across serialization, reload and retirement', function()
    local c = fixture()
    local seen = {}
    for _ = 1, 12 do local d = create(c); assert(not seen[d.id]); seen[d.id] = true end
    assert(c.registry.retire(0, 'osd_0000000001'))
    local restarted = fixture(c.files)
    assert(restarted.loaded, restarted.loadError)
    local d = create(restarted)
    assert(d.id == 'osd_0000000013' and not seen[d.id])
    assert(restarted.registry.get(0, 'osd_0000000001').state == 'retired')
end)

test('Valid lifecycle, monotonic timestamps and complete history', function()
    local c = fixture()
    local d = create(c)
    for _, state in ipairs({ 'installing', 'installed', 'active', 'fault', 'maintenance', 'active' }) do
        c.time = c.time + 1
        d = transition(c, d.id, state)
    end
    c.time = c.time - 100
    local retired = assert(c.registry.retire(0, d.id))
    assert(retired.updatedAt == d.updatedAt and #retired.history == 8)
    assert(validation.device(retired, c.limits))
end)

test('Invalid transitions, repeated states and retired reactivation rejected', function()
    local c = fixture()
    local d = create(c)
    local writes = c.writes
    for _, state in ipairs({ 'active', 'maintenance', 'fault', 'registered', 'unknown' }) do
        assert(not c.registry.setState(0, d.id, state))
    end
    assert(not c.registry.setState(0, d.id, {}))
    assert(c.writes == writes)
    assert(c.registry.retire(0, d.id))
    for _, state in ipairs({ 'registered', 'installing', 'installed', 'active', 'maintenance', 'fault', 'retired' }) do
        assert(not c.registry.setState(0, d.id, state))
    end
end)

test('Optional identifiers and finite coordinates survive real JSON roundtrip', function()
    local c = fixture()
    local d = create(c, 'smart_lock', { model = 'logical_lock', owner = 'owner-01', propertyId = 'property-01',
        position = { x = -12.5, y = 100.25, z = 20 }, rotation = { x = 0, y = 0, z = 90 } })
    local restarted = fixture(c.files)
    assert(restarted.loaded, restarted.loadError)
    equal(d, assert(restarted.registry.get(0, d.id)))
end)

test('Invalid IDs, identifiers, coordinates and unsupported fields rejected', function()
    local c = fixture()
    for _, input in ipairs({
        { owner = 23 }, { owner = '' }, { owner = string.rep('x', 129) }, { model = {} },
        { model = '' }, { model = '../model' }, { propertyId = 'a', vehicleId = 'b' },
        { position = { x = math.huge, y = 0, z = 0 } },
        { position = { x = 0 / 0, y = 0, z = 0 } },
        { position = { x = 1000001, y = 0, z = 0 } },
        { position = { x = 1, y = 2 } }, { rotation = { x = 0, y = 0, z = 361 } }
    }) do
        input.type = 'bodycam'
        assert(not c.registry.create(0, input))
    end
    for _, id in ipairs({ 'osd_0000000000', '../data', 'x', string.rep('x', 10000) }) do
        assert(not c.registry.get(0, id))
        assert(not c.registry.retire(0, id))
    end
    assert(not c.registry.get(0, {}))
    assert(not c.registry.get(0, 'osd_0000000099'))
    assert(c.writes == 0)
end)

test('Metadata rejects unknown keys, functions, nesting, metatables and cycles', function()
    local c = fixture()
    local cyclic = {}; cyclic.self = cyclic
    for _, value in ipairs({ 'bad', { enabled = true }, { value = {} }, { value = function() end },
        { [1] = true }, cyclic, setmetatable({}, {}) }) do
        assert(not c.registry.create(0, { type = 'bodycam', metadata = value }))
    end
    assert(c.writes == 0)
end)

test('Extensible metadata descriptors enforce types, bounds and required fields', function()
    local schema = { label = { type = 'string', required = true, maxLength = 8 },
        enabled = { type = 'boolean' }, value = { type = 'number', min = 1, max = 5 } }
    assert(validation.metadata({ label = 'test', enabled = false, value = 3 }, schema))
    for _, value in ipairs({ {}, { label = 'too-long-value' }, { label = 'a', enabled = 1 },
        { label = 'a', value = 6 }, { label = 'a', value = math.huge }, { label = 'a', unknown = true } }) do
        assert(not validation.metadata(value, schema))
    end
end)

test('ACE authorization protects every registry operation, including reads', function()
    local c = fixture()
    local d = create(c)
    for _, source in ipairs({ 2, 9, -1, '0', {}, 1.5, math.huge }) do
        assert(not c.registry.create(source, { type = 'bodycam' }))
        assert(not c.registry.get(source, d.id))
        assert(not c.registry.list(source))
        assert(not c.registry.setState(source, d.id, 'installing'))
        assert(not c.registry.retire(source, d.id))
    end
    assert(c.writes == 1)
    assert(c.registry.get(7, d.id))
    assert(c.registry.create(7, { type = 'bodycam' }))
    c.allowed[7] = false
    assert(not c.registry.get(7, d.id)) -- permisos revocados se comprueban de nuevo
end)

test('Creation cap includes retired devices; pagination is sorted and bounded', function()
    local limits = util.copy(defaults); limits.MaxDevices = 3
    local c = fixture(nil, limits)
    for _ = 1, 3 do create(c) end
    assert(c.registry.retire(0, 'osd_0000000001'))
    assert(not c.registry.create(0, { type = 'bodycam' }))
    local page = assert(c.registry.list(0, 1, 1))
    assert(page.total == 3 and #page.items == 1 and page.items[1].id == 'osd_0000000002')
    assert(#c.registry.list(0, 3, 1).items == 0)
    for _, args in ipairs({ { -1, 1 }, { 0, 0 }, { 0, 101 }, { 0.5, 1 }, { '0', 1 }, { 4, 1 }, { false, 1 } }) do
        assert(not c.registry.list(0, args[1], args[2]))
    end
end)

test('Per-player read/write rate limits reset and console remains usable', function()
    local c = fixture()
    for _ = 1, defaults.ReadRequestsPerWindow do assert(c.registry.list(7)) end
    assert(not c.registry.list(7))
    assert(c.registry.list(0))
    for _ = 1, defaults.WriteRequestsPerWindow do assert(c.registry.create(7, { type = 'bodycam' })) end
    assert(not c.registry.create(7, { type = 'bodycam' }))
    c.time = c.time + defaults.RateWindowSeconds
    assert(c.registry.list(7))
    c.permissions.forget(7)
    assert(c.registry.create(7, { type = 'bodycam' }))
end)

test('Returned objects and catalog entries cannot mutate authoritative state', function()
    local c = fixture()
    local d = create(c)
    d.state = 'active'; d.history[1].to = 'retired'; d.metadata.bad = true
    local stored = assert(c.registry.get(0, d.id))
    assert(stored.state == 'registered' and stored.history[1].to == 'registered' and not stored.metadata.bad)
    local definition = OSSecurity.DeviceCatalog.get('bodycam')
    definition.metadataSchema.bad = { type = 'string' }
    assert(not OSSecurity.DeviceCatalog.get('bodycam').metadataSchema.bad)
end)

test('Corrupt JSON, unsupported schema, trailing data and null fail closed', function()
    local valid = fixture(); create(valid)
    local raw = valid.files['data/devices.a.json']
    for _, content in ipairs({ '{broken', '', 'null', '{}', raw .. ' trailing',
        (raw:gsub('"schemaVersion"%s*:%s*1', '"schemaVersion":999')) }) do
        local files = { ['data/devices.a.json'] = content }
        local c = fixture(files)
        assert(not c.loaded)
        assert(not c.registry.create(0, { type = 'bodycam' }))
        assert(not c.registry.list(0))
        assert(files['data/devices.a.json'] == content and c.writes == 0 and #c.logs > 0)
    end
end)

test('A corrupt inactive slot is preserved even when another snapshot is valid', function()
    local c = fixture(); create(c); create(c)
    c.files['data/devices.a.json'] = '{bad'
    local restarted = fixture(c.files)
    assert(not restarted.loaded and restarted.writes == 0)
    assert(c.files['data/devices.a.json'] == '{bad')
end)

test('Invalid loaded records, counters, history and coordinates are rejected', function()
    local c = fixture(); local d = create(c)
    local original = codec.decode(c.files['data/devices.a.json'])
    local changes = {
        function(data) data.nextId = 1 end,
        function(data) data.revision = data.revision + 1 end,
        function(data) data.devices[d.id].type = 'unknown' end,
        function(data) data.devices[d.id].state = 'active' end,
        function(data) data.devices[d.id].metadata.unknown = true end,
        function(data) data.devices[d.id].position = { x = 1, y = 2 } end,
        function(data) data.devices[d.id].condition.components.sensor = { health = 101 } end,
        function(data) data.devices[d.id].installation.quality = -1 end,
        function(data) data.devices[d.id].createdAt = data.devices[d.id].updatedAt + 1 end
    }
    for _, change in ipairs(changes) do
        local modified = util.copy(original); change(modified)
        local restarted = fixture({ ['data/devices.a.json'] = codec.encode(modified) })
        assert(not restarted.loaded and restarted.writes == 0)
    end
end)

test('Legacy component health and installation quality remain readable independently', function()
    local c = fixture(); local d = create(c)
    d.schemaVersion = 1
    d.condition = { components = {} }
    d.maintenance = { events = {} }
    d.installation.quality = 85
    d.condition.components.sensor = { health = 45, wear = 55, expectedLifetimeHours = 1200, faults = { 'pending' } }
    d.maintenance.events = {
        { kind = 'fault', componentId = 'sensor', at = d.createdAt },
        { kind = 'repair', componentId = 'sensor', at = d.createdAt, notes = 'Contract example' },
        { kind = 'replacement', componentId = 'sensor', at = d.createdAt, replacementId = 'part-02' }
    }
    assert(validation.device(d, c.limits))
    assert(d.state == 'registered')
    d.condition.components.sensor.health = 'bad'
    assert(not validation.device(d, c.limits))
    d.condition.components.sensor.health = 45
    d.maintenance.events[1].kind = 'unknown'
    assert(not validation.device(d, c.limits))
end)

test('Write failure blocks access, never confirms a device and preserves the last snapshot', function()
    local c = fixture(); local d = create(c)
    local before = c.files['data/devices.a.json']
    c.writeFailure = true
    local result = c.registry.create(0, { type = 'bodycam' })
    assert(not result and not c.registry.status() and #c.logs > 0)
    assert(c.files['data/devices.a.json'] == before)
    assert(not c.registry.list(0))
    local restarted = fixture(c.files)
    assert(restarted.loaded and restarted.registry.get(0, d.id))
    assert(restarted.registry.list(0).total == 1)
end)

test('Failed state save does not change the last confirmed state after reload', function()
    local c = fixture(); local d = create(c)
    c.writeFailure = true
    assert(not c.registry.setState(0, d.id, 'installing'))
    local restarted = fixture(c.files)
    assert(restarted.registry.get(0, d.id).state == 'registered')
end)

test('Ambiguous complete writes return failure; reload recovers them without reusing IDs', function()
    local c = fixture(); create(c)
    c.writeFailure, c.completeWriteBeforeError = true, true
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(not c.registry.status())
    local restarted = fixture(c.files)
    assert(restarted.loaded, restarted.loadError)
    assert(restarted.registry.get(0, 'osd_0000000002').type == 'bodycam')
    assert(create(restarted).id == 'osd_0000000003')
end)

test('Partial writes and false-success writes are detected and preserved for diagnosis', function()
    for _, mode in ipairs({ 'partial', 'truncate', 'exception' }) do
        local c = fixture(); create(c)
        local before = c.files['data/devices.a.json']
        if mode == 'partial' then c.writeFailure, c.partialWrite = true, true end
        if mode == 'truncate' then c.truncate = true end
        if mode == 'exception' then c.writeException = true end
        assert(not c.registry.create(0, { type = 'bodycam' }))
        assert(not c.registry.status() and c.files['data/devices.a.json'] == before)
        local writes = c.writes
        assert(not c.registry.retire(0, 'osd_0000000001') and c.writes == writes)
        local restarted = fixture(c.files)
        assert(restarted.loaded == (mode == 'exception'))
    end
end)

test('Read errors do not initialize an empty store or write any files', function()
    local c = fixture(); c.readError = true
    assert(not c.registry.load())
    assert(not c.registry.create(0, { type = 'bodycam' }) and c.writes == 0)
end)

test('External file changes and oversized files block writes without overwriting data', function()
    local c = fixture(); create(c); create(c)
    c.files['data/devices.a.json'] = '{external'
    local writes = c.writes
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.files['data/devices.a.json'] == '{external' and c.writes == writes)
    local limits = util.copy(defaults); limits.MaxFileBytes = 20
    local oversized = fixture({ ['data/devices.a.json'] = string.rep('x', 21) }, limits)
    assert(not oversized.loaded and oversized.writes == 0)
end)

test('Serialization errors are logged, do not write and keep confirmed state available', function()
    local c = fixture(); local d = create(c)
    local writes = c.writes
    c.encodeError = true
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.registry.status() and c.writes == writes and #c.logs > 0)
    assert(c.registry.get(0, d.id))
    c.encodeError = false
    assert(create(c).id == 'osd_0000000002')
end)

test('Serialized size limit rejects a mutation before writing any data', function()
    local limits = util.copy(defaults); limits.MaxFileBytes = 20
    local c = fixture(nil, limits)
    assert(c.loaded)
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.writes == 0 and c.registry.status() and c.registry.list(0).total == 0)
    assert(#c.logs > 0)
end)

test('History reserves the last event for retirement and never truncates records', function()
    local limits = util.copy(defaults); limits.MaxHistory = 4
    local c = fixture(nil, limits); local d = create(c)
    transition(c, d.id, 'installing'); transition(c, d.id, 'installed')
    assert(not c.registry.setState(0, d.id, 'active'))
    local retired = assert(c.registry.retire(0, d.id))
    assert(#retired.history == 4 and retired.state == 'retired')
end)

test('Snapshots with duplicated revisions or altered historical data are rejected', function()
    local c = fixture(); local d = create(c); transition(c, d.id, 'installing')
    local newer = codec.decode(c.files['data/devices.b.json'])
    local older = codec.decode(c.files['data/devices.a.json'])
    newer.devices[d.id].model = 'changed'
    assert(validation.snapshot(newer, c.limits))
    assert(not fixture({ ['data/devices.a.json'] = codec.encode(older),
        ['data/devices.b.json'] = codec.encode(newer) }).loaded)
    assert(not fixture({ ['data/devices.a.json'] = codec.encode(older),
        ['data/devices.b.json'] = codec.encode(older) }).loaded)
end)

test('Storage interface rejects bulk replacement, skipped revisions and deletion', function()
    assert(not pcall(OSSecurity.JsonStorage.new, { base = '../outside' }))
    local c = fixture(); local d = create(c)
    local data = codec.decode(c.files['data/devices.a.json'])
    data.revision = data.revision + 2
    assert(not c.store.save(data))
    data.revision = data.revision - 1
    data.devices[d.id] = nil
    assert(not c.store.save(data))
    assert(c.writes == 1)
end)

test('Administrative command parsing, explicit ACE and bounded output', function()
    local c, handler, replies = fixture(), nil, {}
    OSSecurity.DeviceCommands.register({
        registry = c.registry, permissions = c.permissions, defaultPageSize = defaults.DefaultPageSize,
        encode = codec.encode, reply = function(source, message) replies[#replies + 1] = { source, message } end,
        register = function(name, callback, restricted)
            assert(name == 'osdev' and restricted == false); handler = callback
        end
    })
    handler(9, { 'create', 'bodycam' }); assert(c.writes == 0 and replies[#replies][1] == 9)
    handler(0, { 'create', 'bodycam' }); assert(c.writes == 1)
    handler(0, { 'list', 'bad' }); assert(replies[#replies][2]:find('numeros enteros', 1, true))
    handler(0, { 'list', '0', '1' })
    handler(0, { 'info', 'osd_0000000001' })
    handler(0, { 'state', 'osd_0000000001', 'installing' }); assert(c.writes == 2)
    handler(0, { 'remove', 'osd_0000000001' }); assert(c.writes == 3)
    handler(0, { 'state', 'osd_0000000001', 'active' }); assert(c.writes == 3)
    handler(0, { 'create', 'bodycam', 'extra' }); assert(c.writes == 3)
    handler(7, { 'list' }); assert(replies[#replies][1] == 7)
    assert(not c.permissions.isAdmin(9)) -- group.admin no interviene en la autorizacion
end)

-- Integration wiring with FiveM API doubles. Does not start FXServer.
test('FiveM wiring: startup, commands, restart persistence and safe file errors', function()
    local files, handlers, commands, logs = {}, {}, {}, {}
    local readUnavailable = false
    local originalPrint, originalOpen = print, io.open
    local function boot(nativeReturn)
        handlers, commands = {}, {}
        RegisterNetEvent = function(name) assert(name == 'os_security:g6:request' or name == 'os_security:g6:anchorAim' or name == 'os_security:g6:zoneAim' or name:match('^os_security:shop:') or name:match('^os_security:alarm:') or name:match('^os_security:locks:') or name:match('^os_security:car:') or name:match('^os_security:lockpick:'), 'Unexpected network event') end
        RegisterCommand = function(name, callback) commands[name] = callback end
        AddEventHandler = function(name, callback) handlers[name] = callback end
        CreateThread = function() end -- bucles periodicos (alarmas) fuera de la prueba
        exports = setmetatable({}, { __call = function(_, name, callback) assert(name == 'GetDoorSecurity' and type(callback) == 'function') end })
        GetCurrentResourceName = function() return 'os_security' end
        GetResourceState = function() return 'started' end
        GetConvar = function(_, default) return default end -- sin convars: proveedor standalone
        IsPlayerAceAllowed = function(source, ace) return source == 7 and ace == 'ossecurity.admin' end
        TriggerClientEvent = function(_, source) assert(source > 0) end
        TriggerEvent = function(name, payload) assert(name == 'chat:addMessage' and payload.args[1] == OSSecurity.Brand.Name) end
        LoadResourceFile = function(resource, file)
            assert(resource == 'os_security')
            if readUnavailable then return nil end
            return files[file]
        end
        SaveResourceFile = function(resource, file, content, length)
            assert(resource == 'os_security' and length == #content)
            files[file] = content; return nativeReturn or true
        end
        io.open = function(mount, mode)
            assert(mount:match('^@os_security/data/') and mode == 'rb')
            return nil, 'missing', 2
        end
        print = function(message) logs[#logs + 1] = message end
        dofile(root .. 'server/main.lua')
        dofile(root .. 'client/main.lua')
        handlers.onResourceStart('another_resource')
        assert(not OSSecurity.Registry.status())
        handlers.onResourceStart('os_security')
        assert(OSSecurity.Registry.status())
    end
    local ok, err = pcall(function()
        boot(1) -- El binding local devuelve el BOOL nativo como entero.
        commands.oshello(0, {})
        commands.osdev(9, { 'create', 'bodycam' }); assert(next(files) == nil)
        commands.osdev(0, { 'create', 'bodycam' })
        assert(OSSecurity.Registry.status(), 'SaveResourceFile wrote the snapshot and returned integer 1, but the core blocked it')
        commands.osdev(7, { 'list' })
        -- Panel de os_admin: mismos comandos, respuestas recogidas en lugar de enviadas al chat.
        local panel = {}
        for _, action in ipairs(OSSecurity.AdminPanel.build(OSSecurity.AdminPanelRun).actions) do panel[action.id] = action end
        local sent = 0; TriggerClientEvent = function() sent = sent + 1 end
        local created = panel.crear.handler(7, { tipo = 'alarm_panel' }); assert(created.ok and created.message:find('^Persistido'), created.message)
        local listed = panel.dispositivos.handler(7, {}); assert(listed.ok and listed.message:find('^Dispositivos: 2') and #listed.rows == 2)
        local detail = panel.detalle.handler(7, { dispositivo = 'osd_0000000002' }); assert(detail.ok and #detail.rows >= 2)
        assert(not panel.crear.handler(9, { tipo = 'bodycam' }).ok) -- sin ossecurity.admin
        assert(not panel.estado.handler(7, { dispositivo = 'osd_0000000099', estado = 'active' }).ok)
        assert(not panel.vincular.handler(7, { dispositivo = 'osd_0000000002', tipo = 'propiedad' }).ok)
        assert(sent == 0, 'Panel replies must not reach the chat')
        -- Acciones que siguen en el juego: abren el editor en el cliente y cierran el panel.
        local events = {}; TriggerClientEvent = function(name, player, payload) events[#events + 1] = { name, player, payload } end
        local zone = panel.montaje.handler(7, { cliente = 7, vinculo = 'propiedad', id = 5 })
        assert(zone.ok and zone.close and events[1][1] == 'os_security:g6:anchorEditor' and events[1][2] == 7)
        assert(events[1][3].site.kind == 'property' and events[1][3].site.id == 5 and events[1][3].id:match('^prop5_') and events[1][3].client == 7)
        assert(not panel.montaje.handler(7, { cliente = 7, vinculo = 'negocio' }).ok) -- falta el ID
        assert(not panel.montaje.handler(7, { cliente = 7, vinculo = 'none', nombre = 'con espacios' }).ok)
        local door = panel.puertaapuntada.handler(7, { tipo = 'propiedad', id = 5 })
        assert(door.ok and door.close and events[#events][1] == 'os_security:locks:aimDoor' and events[#events][3].id == 5)
        GetPlayerPed = function() return 0 end -- sin posicion: no hay puerta cercana
        assert(not panel.puertacercana.handler(7, {}).ok)
        GetPlayerPed = nil
        assert(#events == 2)
        TriggerClientEvent = function(_, source) assert(source > 0) end
        commands.osstatus(0, {})
        local logCount = #logs
        handlers.onResourceStop('another_resource'); assert(#logs == logCount)
        handlers.onResourceStop('os_security'); assert(logs[#logs]:find('[OS SECURITY]', 1, true))
        boot() -- mismas cadenas JSON, nuevo registro y adaptador
        assert(OSSecurity.Registry.get(0, 'osd_0000000001'))
        commands.osdev(0, { 'create', 'bodycam' })
        assert(OSSecurity.Registry.get(0, 'osd_0000000003'))
        source = 7; handlers.playerDropped()
        readUnavailable = true
        io.open = function() return nil, 'permission denied', 13 end
        assert(not OSSecurity.Registry.load())
        assert(not OSSecurity.Registry.create(0, { type = 'bodycam' }))
        readUnavailable = false
    end)
    print, io.open = originalPrint, originalOpen
    assert(ok, err)
end)

-- Compartir el mismo banco de pruebas con las regresiones del adaptador JSON.
StorageTest = { test = test, fixture = fixture, create = create, equal = equal, transition = transition }
dofile(root .. 'tests/storage_json_spec.lua')
dofile(root .. 'tests/storage_write_spec.lua')
dofile(root .. 'tests/maintenance_spec.lua')
dofile(root .. 'tests/gameplay_spec.lua')
dofile(root .. 'tests/client_spec.lua')
dofile(root .. 'tests/admin_access_spec.lua')
dofile(root .. 'tests/web_spec.lua')
StorageTest = nil

print(('Tests: %d | Passed: %d | Failed: %d'):format(total, total - failures, failures))
__failures = failures
