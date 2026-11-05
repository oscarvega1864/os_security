local test, fixture, create = StorageTest.test, StorageTest.fixture, StorageTest.create
local codec = OSSecurity.JsonCodec

local function nativeFixture()
    local c = { files = {}, logs = {}, traces = {}, calls = 0, result = 1 }
    c.adapter = OSSecurity.ResourceFiles.new({
        resource = 'os_security_test',
        load = function(resource, path)
            assert(resource == 'os_security_test')
            if c.permission or (c.unreadable and c.calls > 0) or c.missing then return nil end
            return c.files[path]
        end,
        open = function(path, mode)
            assert(mode == 'rb')
            if c.permission then return nil, 'Permission denied', 13 end
            if c.unreadable and c.calls > 0 then return { close = function() end } end
            return nil, 'No such file', 2
        end,
        save = function(resource, path, content, length)
            assert(resource == 'os_security_test' and type(content) == 'string' and length == #content)
            c.calls = c.calls + 1
            c.lastBytes = length
            if c.exception then error(c.exception) end
            c.files[path] = c.truncate and content:sub(1, 10) or content
            return c.result
        end
    })
    c.store = OSSecurity.JsonStorage.new({
        base = 'data/devices', limits = OSSecurity.ServerConfig,
        read = c.adapter.read, write = c.adapter.write,
        encode = codec.encode, decode = codec.decode,
        log = function(message) c.logs[#c.logs + 1] = message end,
        trace = function(message) c.traces[#c.traces + 1] = message end
    })
    c.registry = OSSecurity.DeviceRegistry.new({
        store = c.store, limits = OSSecurity.ServerConfig,
        authorize = function(source) return source == 0 end,
        now = function() return 1700000000 end
    })
    assert(c.registry.load())
    return c
end

test('Regression: integer BOOL 1 is normalized and both alternating snapshots verify', function()
    local c = nativeFixture()
    create(c); create(c)
    assert(c.registry.status() and c.registry.list(0).total == 2)
    assert(c.files['data/devices.a.json'] and c.files['data/devices.b.json'])
    assert(c.registry.load())
    assert(c.registry.list(0).total == 2)
    assert(c.traces[#c.traces]:find('native_type=number native_result=1', 1, true))
    assert(c.traces[#c.traces]:find('Escritura verificada.', 1, true))
end)

test('Native BOOL accepts only true or 1, rejecting zero, nil and other truthy values', function()
    for _, result in ipairs({ true, 1 }) do
        local c = nativeFixture(); c.result = result
        assert(c.registry.create(0, { type = 'bodycam' }))
    end
    for _, result in ipairs({ false, 0, 2, -1, 1.5, '1', 'true', {} }) do
        local c = nativeFixture(); c.result = result
        assert(not c.registry.create(0, { type = 'bodycam' }))
        assert(not c.registry.status() and c.logs[#c.logs]:find('[storage:write]', 1, true))
    end
    local c = nativeFixture(); c.result = nil
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.logs[#c.logs]:find('native_type=nil', 1, true))
end)

test('Native adapter sends UTF-8 byte length, never character count or an inferred length', function()
    local c = nativeFixture()
    local payload = '{"text":"camara \195\161 \240\159\148\146"}'
    local ok = c.adapter.write('data/devices.a.json', payload)
    assert(ok and c.lastBytes == #payload and #payload > utf8.len(payload))
    assert(c.adapter.read('data/devices.a.json') == payload)
end)

test('Integer success never bypasses byte-integrity checks or post-write read failures', function()
    local c = nativeFixture(); c.truncate = true
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(not c.registry.status() and c.logs[#c.logs]:find('[storage:integrity]', 1, true))
    c = nativeFixture(); c.unreadable = true
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.logs[#c.logs]:find('[storage:read]', 1, true))
    c = nativeFixture(); c.missing = true
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.logs[#c.logs]:find('[storage:read]', 1, true))
end)

test('Permission diagnostics use errno or explicit access errors, without logging exception text', function()
    local c = nativeFixture(); c.permission = true
    assert(not c.registry.load())
    assert(c.logs[#c.logs]:find('[storage:permission]', 1, true))
    assert(c.logs[#c.logs]:find('errno=13', 1, true))
    c = nativeFixture(); c.exception = 'Permission denied: SECRET_TEST_MARKER'
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.logs[#c.logs]:find('[storage:permission]', 1, true))
    assert(not c.logs[#c.logs]:find('SECRET_TEST_MARKER', 1, true))
    c = nativeFixture(); c.exception = 'SECRET_TEST_MARKER'
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.logs[#c.logs]:find('[storage:write]', 1, true))
    assert(not c.logs[#c.logs]:find('SECRET_TEST_MARKER', 1, true))
end)

test('Serialization and validation have distinct stages and do not write', function()
    local c = nativeFixture(); local d = create(c)
    local snapshot = codec.decode(c.files['data/devices.a.json'])
    snapshot.schemaVersion = 999
    assert(not c.store.save(snapshot))
    assert(c.logs[#c.logs]:find('[storage:validation]', 1, true) and c.calls == 1)
    local base = fixture(); create(base); base.encodeError = true
    assert(not base.registry.create(0, { type = 'bodycam' }))
    assert(base.logs[#base.logs]:find('[storage:serialization]', 1, true))
    assert(c.registry.get(0, d.id))
end)

test('Failed native return reports before/after sizes and leaves the confirmed slot intact', function()
    local c = nativeFixture(); create(c)
    local confirmed = c.files['data/devices.a.json']
    c.result = 0
    assert(not c.registry.create(0, { type = 'bodycam' }))
    assert(c.files['data/devices.a.json'] == confirmed)
    assert(c.logs[#c.logs]:find('before_bytes=-1', 1, true))
    assert(c.logs[#c.logs]:find('expected_bytes=', 1, true))
    assert(c.logs[#c.logs]:find('after_bytes=', 1, true))
    assert(c.logs[#c.logs]:find('native_type=number native_result=0', 1, true))
end)
