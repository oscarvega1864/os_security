local test, fixture, create, equal = StorageTest.test, StorageTest.fixture, StorageTest.create, StorageTest.equal
local codec, util = OSSecurity.JsonCodec, OSSecurity.Util

-- Double del contrato Cfx lua-rapidjson (rama grit): lua_istable selecciona
-- objectmeta/arraymeta; nil mantiene las metatablas JSON predeterminadas.
-- Fuente: citizenfx/lua-rapidjson, commit 60f4dd4, rapidjson_decode().
-- El parser real de la suite sigue leyendo el JSON; no se simulan dispositivos.
-- No equivale a ejecutar el modulo C++ ni FXServer.
local function withNativeContract(run)
    local original = json
    local objectMeta, arrayMeta = { __jsontype = 'object' }, { __jsontype = 'array' }
    json = {
        null = original.null,
        encode = original.encode,
        decode = function(content, position, null, requestedObject, requestedArray)
            local objects = type(requestedObject) == 'table' and requestedObject or objectMeta
            local arrays = type(requestedArray) == 'table' and requestedArray or arrayMeta
            local value, nextPosition, err = original.decode(content, position, null, objects, arrays)
            local function tag(item)
                if type(item) ~= 'table' or item == original.null then return end
                -- dkjson ya aplica las metatablas solicitadas; el puente JS
                -- devuelve tablas planas y necesita las etiquetas del doble.
                if getmetatable(item) == nil then
                    setmetatable(item, #item > 0 and arrays or objects)
                end
                for _, child in pairs(item) do tag(child) end
            end
            tag(value)
            return value, nextPosition, err
        end
    }
    local ok, err = pcall(run)
    json = original
    assert(ok, err)
end

test('Regression: FXServer JSON metadata permits osdev create and persisted reload', function()
    withNativeContract(function()
        local value = json.decode('{"devices":[]}', 1, json.null, nil, nil)
        assert(getmetatable(value).__jsontype == 'object')
        assert(not util.object(value)) -- el contrato de dominio sigue siendo estricto
        local c = fixture()
        assert(c.loaded)
        local device, err = c.registry.create(0, { type = 'cctv_camera' })
        assert(device, err)
        assert(c.writes == 1 and c.registry.list(0).total == 1)
        local restarted = fixture(c.files)
        assert(restarted.loaded, restarted.loadError)
        equal(device, assert(restarted.registry.get(0, device.id)))
        assert(create(restarted).id == 'osd_0000000002')
    end)
end)

test('Empty arrays and objects normalize recursively without weakening domain checks', function()
    withNativeContract(function()
        for _, content in ipairs({ '{}', '[]', '{"metadata":{},"events":[]}',
            '{"metadata":[],"installation":[],"condition":{"components":[]},"maintenance":{"events":[]}}' }) do
            local decoded = codec.decode(content)
            local function plain(value)
                if type(value) ~= 'table' then return end
                assert(getmetatable(value) == nil)
                for _, child in pairs(value) do plain(child) end
            end
            plain(decoded)
        end
        assert(not util.object(setmetatable({}, {})))
        assert(not util.array(setmetatable({}, {}), 10))
    end)
end)

test('FXServer metadata normalization preserves corrupt snapshots and write failure protection', function()
    withNativeContract(function()
        local c = fixture(); create(c)
        local confirmed = c.files['data/devices.a.json']
        c.writeFailure = true
        assert(not c.registry.create(0, { type = 'bodycam' }))
        assert(not c.registry.status() and c.files['data/devices.a.json'] == confirmed)
        local restarted = fixture(c.files)
        assert(restarted.loaded and restarted.registry.list(0).total == 1)
        c.files['data/devices.b.json'] = '{corrupt'
        local corrupt = fixture(c.files)
        assert(not corrupt.loaded and corrupt.writes == 0)
        assert(c.files['data/devices.b.json'] == '{corrupt')
    end)
end)

test('FXServer metadata normalization still rejects invalid schemas, fields and trailing JSON', function()
    withNativeContract(function()
        local c = fixture(); create(c)
        local raw = c.files['data/devices.a.json']
        for _, content in ipairs({ raw .. '{}', raw .. ' trailing', '{}', '[]', 'false',
            (raw:gsub('"schemaVersion"%s*:%s*1', '"schemaVersion":999')) }) do
            local invalid = fixture({ ['data/devices.a.json'] = content })
            assert(not invalid.loaded and invalid.writes == 0)
        end
        local unknown = codec.decode(raw)
        unknown.extra = true
        assert(not OSSecurity.DeviceValidation.snapshot(unknown, c.limits))
    end)
end)

test('Decoder-specific JSON null markers are never normalized to empty containers', function()
    local original = json
    -- dkjson usa una tabla especial y RapidJSON una funcion. Probar ambos
    -- marcadores sin depender de que el puente JS soporte null como dato Lua.
    for _, marker in ipairs({ setmetatable({}, { __tojson = function() return 'null' end }),
        function() end }) do
        local objectMeta
        json = {
            null = marker,
            decode = function(content, _, passedNull, objects)
                assert(passedNull == marker)
                objectMeta = objects
                return setmetatable({ metadata = marker }, objects or {}), #content + 1
            end
        }
        local ok, err = pcall(function()
            local value = codec.decode('{"metadata":null}')
            assert(type(objectMeta) == 'table')
            assert(value.metadata == marker)
            assert(not OSSecurity.DeviceValidation.metadata(value.metadata, {}))
        end)
        json = original
        assert(ok, err)
    end
end)
