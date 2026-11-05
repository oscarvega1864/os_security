OSSecurity.DeviceRegistry = {}

function OSSecurity.DeviceRegistry.new(options)
    local util, validation = OSSecurity.Util, OSSecurity.DeviceValidation
    local data, loadError
    local registry = {}

    function registry.load()
        data, loadError = options.store.load()
        return data ~= nil, loadError
    end

    function registry.status()
        local blocked, err = options.store.isBlocked()
        return data ~= nil and not blocked, loadError or err
    end

    local function access(source, writing)
        local allowed, err = options.authorize(source, writing)
        if not allowed then return nil, err end
        local ready = registry.status()
        if not ready then return nil, 'Registro no disponible; revisar consola y almacenamiento.' end
        return true
    end

    local function find(id)
        if not validation.id(id) then return nil, 'ID invalido; formato osd_0000000001.' end
        if not data.devices[id] then return nil, 'Dispositivo no encontrado.' end
        return data.devices[id]
    end

    local function commit(candidate, id)
        candidate.revision = data.revision + 1
        local ok, err = options.store.save(candidate)
        if not ok then return nil, err end
        data = candidate
        return util.copy(data.devices[id])
    end

    function registry.create(source, input)
        local allowed, err = access(source, true)
        if not allowed then return nil, err end
        local normalized, reason = validation.create(input)
        if not normalized then return nil, reason end
        local count = 0
        for _ in pairs(data.devices) do count = count + 1 end
        if count >= options.limits.MaxDevices then return nil, 'Limite total de dispositivos alcanzado (incluye retirados).' end
        if data.nextId > validation.MaxSequence then return nil, 'Secuencia de IDs agotada.' end
        local now = options.now()
        local id = ('osd_%010d'):format(data.nextId)
        normalized.id, normalized.state = id, 'registered'
        normalized.createdAt, normalized.updatedAt = now, now
        normalized.schemaVersion = validation.SchemaVersion
        normalized.installation, normalized.condition = {}, { components = {} }
        normalized.maintenance = { events = {} }
        normalized.history = { { to = 'registered', at = now } }
        local candidate = util.copy(data)
        candidate.devices[id], candidate.nextId = normalized, data.nextId + 1
        return commit(candidate, id)
    end

    function registry.get(source, id)
        local allowed, err = access(source, false)
        if not allowed then return nil, err end
        local device, reason = find(id)
        if not device then return nil, reason end
        return util.copy(device)
    end

    function registry.list(source, offset, limit)
        local allowed, err = access(source, false)
        if not allowed then return nil, err end
        if offset == nil then offset = 0 end
        if limit == nil then limit = options.limits.DefaultPageSize end
        if not util.integer(offset, 0, options.limits.MaxDevices)
            or not util.integer(limit, 1, options.limits.MaxPageSize) then
            return nil, 'Paginacion invalida o fuera de limites.'
        end
        local ids = {}
        for id in pairs(data.devices) do ids[#ids + 1] = id end
        table.sort(ids)
        local items = {}
        for index = offset + 1, math.min(offset + limit, #ids) do
            local device = data.devices[ids[index]]
            items[#items + 1] = { id = device.id, type = device.type, state = device.state }
        end
        return { items = items, total = #ids, offset = offset, limit = limit }
    end

    function registry.setState(source, id, target)
        local allowed, err = access(source, true)
        if not allowed then return nil, err end
        local device, reason = find(id)
        if not device then return nil, reason end
        if not OSSecurity.DeviceStates.canTransition(device.state, target) then
            return nil, 'Transicion no permitida desde ' .. device.state .. '.'
        end
        -- Reservar un evento para retirar sin truncar el historial.
        local maximum = options.limits.MaxHistory - (target == 'retired' and 0 or 1)
        if #device.history >= maximum then return nil, 'Limite de historial alcanzado; retirar el dispositivo.' end
        local candidate = util.copy(data)
        local updated = candidate.devices[id]
        local now = math.max(options.now(), device.updatedAt)
        updated.history[#updated.history + 1] = { from = device.state, to = target, at = now }
        updated.state, updated.updatedAt = target, now
        return commit(candidate, id)
    end

    function registry.retire(source, id) return registry.setState(source, id, 'retired') end
    return registry
end
