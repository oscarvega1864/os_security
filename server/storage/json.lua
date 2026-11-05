-- Interfaz de almacenamiento: load(), save(snapshot), isBlocked().
-- Dos snapshots alternos: nunca se escribe sobre la ultima revision confirmada.
-- Sin yields durante save; cada mutacion se confirma tras escritura y relectura.
OSSecurity.JsonStorage = {}

function OSSecurity.JsonStorage.new(options)
    assert(type(options.base) == 'string' and options.base:match('^data/[%w_%-]+$'),
        'La ruta JSON debe permanecer dentro de data/ del recurso.')
    local validation = OSSecurity.DeviceValidation
    local paths = { options.base .. '.a.json', options.base .. '.b.json' }
    local active, current, blocked = nil, nil, 'Almacenamiento sin inicializar.'
    local known = {}
    local store = {}

    local function fail(message)
        blocked = message
        options.log(message)
        return nil, message
    end

    local function reject(message)
        options.log(message)
        return nil, message
    end

    local function read(path)
        local ok, content, err = pcall(options.read, path)
        if not ok then return nil, 'Error de lectura.' end
        return content, err
    end

    local function decode(content)
        if type(content) ~= 'string' or #content > options.limits.MaxFileBytes then
            return nil, 'JSON vacio, ilegible o demasiado grande.'
        end
        local ok, data = pcall(options.decode, content)
        if not ok then return nil, 'JSON corrupto.' end
        local valid, err = validation.snapshot(data, options.limits)
        if not valid then return nil, err end
        return data
    end

    function store.load()
        local snapshots = {}
        for index, path in ipairs(paths) do
            local content, err = read(path)
            if err then return fail(path .. ': ' .. err) end
            if content ~= nil then
                local data, reason = decode(content)
                if not data then return fail(path .. ': ' .. reason .. ' No se sobrescribira.') end
                snapshots[index] = data
            end
            known[index] = content
        end
        if snapshots[1] and snapshots[2] then
            if snapshots[1].revision == snapshots[2].revision then
                return fail('Snapshots con revision duplicada; revisar manualmente.')
            end
            active = snapshots[1].revision > snapshots[2].revision and 1 or 2
            local older = snapshots[3 - active]
            local newer = snapshots[active]
            local valid, err = validation.successor(older, newer)
            if not valid then return fail('Secuencia de snapshots inconsistente: ' .. err) end
        else
            active = snapshots[1] and 1 or (snapshots[2] and 2 or nil)
        end
        local data = active and snapshots[active] or {
            schemaVersion = validation.SchemaVersion, revision = 0, nextId = 1, devices = {}
        }
        current, blocked = OSSecurity.Util.copy(data), nil
        return OSSecurity.Util.copy(data)
    end

    function store.save(snapshot)
        if blocked then return nil, blocked end
        local valid, err = validation.snapshot(snapshot, options.limits)
        if not valid then return reject(err) end
        local consecutive, sequenceError = validation.successor(current, snapshot)
        if not consecutive then return reject(sequenceError) end
        local ok, encoded = pcall(options.encode, snapshot)
        if not ok or type(encoded) ~= 'string' or #encoded > options.limits.MaxFileBytes then
            return reject('No se pudo serializar el cambio dentro del limite.')
        end
        local decoded, reason = decode(encoded)
        if not decoded then return reject('Serializacion invalida: ' .. reason) end
        if not OSSecurity.Util.equal(snapshot, decoded) then return reject('Serializacion altera los datos.') end
        -- Detectar ediciones/corrupcion externa antes de sobrescribir un slot.
        for index, path in ipairs(paths) do
            local content, readError = read(path)
            if readError or content ~= known[index] then
                return fail('Almacenamiento modificado externamente: ' .. path .. '. No se sobrescribira.')
            end
        end
        local target = active == 1 and 2 or 1
        local written, result = pcall(options.write, paths[target], encoded)
        if not written or result ~= true then
            return fail('Fallo al guardar ' .. paths[target] .. '; registro bloqueado hasta reiniciar y revisar datos.')
        end
        local persisted, readError = read(paths[target])
        if readError or persisted ~= encoded then
            return fail('Fallo al verificar ' .. paths[target] .. '; registro bloqueado hasta reiniciar y revisar datos.')
        end
        active, current = target, OSSecurity.Util.copy(snapshot)
        known[target] = encoded
        return true
    end

    function store.isBlocked() return blocked ~= nil, blocked end
    return store
end
