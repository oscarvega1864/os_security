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

    local function bytes(content) return type(content) == 'string' and #content or -1 end

    -- Solo campos tecnicos controlados: nunca JSON, propietarios o excepciones.
    local function diagnostic(stage, message, context)
        local summary = ('[storage:%s] %s | revision=%s active=%s'):format(
            stage, message, current and current.revision or '-', active and paths[active] or '-')
        return summary .. (context and ' | ' .. context or '')
    end

    local function nativeDetails(details)
        if type(details) ~= 'table' then return 'native_type=unknown native_result=unknown' end
        local result = details.nativeResult
        local safeValue = (type(result) == 'boolean' or type(result) == 'number') and tostring(result) or '-'
        local valueType = type(result)
        if details.nativeType == 'nil' or details.nativeType == 'string' then valueType = details.nativeType end
        return ('native_type=%s native_result=%s exception=%s'):format(valueType, safeValue, tostring(details.exception == true))
    end

    local function fail(stage, message, context)
        message = diagnostic(stage, message, context)
        blocked = message
        options.log(message)
        return nil, message
    end

    local function reject(stage, message, context)
        message = diagnostic(stage, message, context)
        options.log(message)
        return nil, message
    end

    local function read(path)
        local ok, content, err, details = pcall(options.read, path)
        if not ok then return nil, 'Error de lectura.', { stage = 'read' } end
        return content, err, details
    end

    local function readStage(details)
        return type(details) == 'table' and details.stage == 'permission' and 'permission' or 'read'
    end

    local function readDetails(path, details)
        local code = type(details) == 'table' and details.errno or nil
        return ('path=%s errno=%s'):format(path, type(code) == 'number' and code or 'unknown')
    end

    local function decode(content)
        if type(content) ~= 'string' or #content > options.limits.MaxFileBytes then
            return nil, 'JSON vacio, ilegible o demasiado grande.', 'validation'
        end
        local ok, data = pcall(options.decode, content)
        if not ok then return nil, 'JSON corrupto.', 'corruption' end
        local valid, err = validation.snapshot(data, options.limits)
        if not valid then return nil, err, 'validation' end
        return data
    end

    function store.load()
        local snapshots = {}
        for index, path in ipairs(paths) do
            local content, err, details = read(path)
            if err then return fail(readStage(details), 'Error al cargar snapshot.', readDetails(path, details)) end
            if content ~= nil then
                local data, reason, stage = decode(content)
                if not data then return fail(stage, reason .. ' No se sobrescribira.', 'path=' .. path) end
                snapshots[index] = data
            end
            known[index] = content
        end
        if snapshots[1] and snapshots[2] then
            if snapshots[1].revision == snapshots[2].revision then
                return fail('integrity', 'Snapshots con revision duplicada; revisar manualmente.')
            end
            active = snapshots[1].revision > snapshots[2].revision and 1 or 2
            local older = snapshots[3 - active]
            local newer = snapshots[active]
            local valid, err = validation.successor(older, newer)
            if not valid then return fail('integrity', 'Secuencia de snapshots inconsistente: ' .. err) end
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
        if not valid then return reject('validation', err) end
        local consecutive, sequenceError = validation.successor(current, snapshot)
        if not consecutive then return reject('validation', sequenceError) end
        local ok, encoded = pcall(options.encode, snapshot)
        if not ok or type(encoded) ~= 'string' or #encoded > options.limits.MaxFileBytes then
            return reject('serialization', 'No se pudo serializar el cambio dentro del limite.')
        end
        local decoded, reason = decode(encoded)
        if not decoded then return reject('serialization', 'Serializacion invalida: ' .. reason) end
        if not OSSecurity.Util.equal(snapshot, decoded) then return reject('integrity', 'Serializacion altera los datos.') end
        -- Detectar ediciones/corrupcion externa antes de sobrescribir un slot.
        for index, path in ipairs(paths) do
            local content, readError, details = read(path)
            if readError then return fail(readStage(details), 'Error de lectura previo al guardado.', readDetails(path, details)) end
            if content ~= known[index] then
                return fail('integrity', 'Almacenamiento modificado externamente. No se sobrescribira.', 'path=' .. path)
            end
        end
        local target = active == 1 and 2 or 1
        local context = ('path=%s next_revision=%d before_bytes=%d expected_bytes=%d'):format(
            paths[target], snapshot.revision, bytes(known[target]), #encoded)
        if options.trace then options.trace(diagnostic('write', 'Antes de escribir.', context)) end
        local written, result, details = pcall(options.write, paths[target], encoded)
        if not written or result ~= true then
            local observed, readError = read(paths[target])
            local stage = type(details) == 'table' and details.stage == 'permission' and 'permission' or 'write'
            return fail(stage, 'Fallo al guardar; registro bloqueado hasta reiniciar y revisar datos.',
                context .. ' ' .. nativeDetails(details) .. (' after_bytes=%d read_error=%s'):format(bytes(observed), tostring(readError ~= nil)))
        end
        local persisted, readError, readInfo = read(paths[target])
        context = context .. ' ' .. nativeDetails(details) .. (' after_bytes=%d'):format(bytes(persisted))
        if readError then
            return fail(readStage(readInfo), 'Error de lectura posterior; registro bloqueado.', context .. ' ' .. readDetails(paths[target], readInfo))
        end
        if persisted == nil then
            return fail('read', 'Snapshot ausente tras escritura declarada; registro bloqueado.', context)
        end
        if persisted ~= encoded then
            return fail('integrity', 'Fallo de integridad posterior; registro bloqueado.', context)
        end
        active, current = target, OSSecurity.Util.copy(snapshot)
        known[target] = encoded
        if options.trace then options.trace(diagnostic('integrity', 'Escritura verificada.', context)) end
        return true
    end

    function store.isBlocked() return blocked ~= nil, blocked end
    return store
end
