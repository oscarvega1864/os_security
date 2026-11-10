OSSecurity.StandaloneInventory = {}

function OSSecurity.StandaloneInventory.new(options)
    local data, errorMessage
    local inventory = {}
    function inventory.load()
        data, errorMessage = options.store.load()
        return data ~= nil, errorMessage
    end
    function inventory.status()
        local blocked, err = options.store.isBlocked()
        return data ~= nil and not blocked, errorMessage or err
    end
    function inventory.snapshot()
        if not inventory.status() then return nil, 'Inventario no disponible.' end
        return OSSecurity.Util.copy(data)
    end
    function inventory.get(principal)
        if not inventory.status() then return nil, 'Inventario no disponible.' end
        if not OSSecurity.Identity.valid(principal) then return nil, 'Identidad invalida.' end
        return OSSecurity.Util.copy(data.accounts[principal] or { items = {}, grants = {} })
    end
    function inventory.site(deviceId)
        if not inventory.status() or not data.sites then return nil end
        local site = data.sites[deviceId]
        return site and { kind = site.kind, id = site.id } or nil
    end
    function inventory.alarm(deviceId)
        if not inventory.status() or not data.alarms or not data.alarms[deviceId] then return nil end
        return OSSecurity.Util.copy(data.alarms[deviceId])
    end
    function inventory.cars()
        if not inventory.status() then return nil end
        return OSSecurity.Util.copy(data.cars or {})
    end
    -- Un registro de vehiculo (sin copiar: solo lectura, para la sincronizacion periodica).
    function inventory.car(id)
        if not inventory.status() or not data.cars then return nil end
        local record = data.cars[id]
        return record and { locked = record.locked, alarm = record.alarm, lock = record.lock } or nil
    end
    function inventory.orders()
        if not inventory.status() then return nil end
        return OSSecurity.Util.copy(data.orders or {})
    end
    function inventory.doors()
        if not inventory.status() then return nil end
        return OSSecurity.Util.copy(data.doors or {})
    end
    function inventory.has(principal, item, amount)
        local account = inventory.get(principal)
        return account ~= nil and account.items[item] ~= nil and account.items[item].count >= (amount or 1)
    end
    function inventory.apply(op)
        if not inventory.status() then return nil, 'Inventario no disponible.' end
        op = OSSecurity.Util.copy(op)
        op.at = math.max(options.now(), data.lastOperation and data.lastOperation.at or 0)
        if op.installation then op.installation.createdAt, op.installation.updatedAt = op.at, op.at end
        local candidate, err = OSSecurity.InventoryState.apply(data, op, options.limits)
        if not candidate then return nil, err end
        local saved, saveError = options.store.save(candidate)
        if not saved then return nil, saveError end
        data = candidate
        return OSSecurity.Util.copy(candidate)
    end
    function inventory.grant(principal, item, amount)
        return inventory.apply({ kind = 'grant', principal = principal, item = item, amount = amount })
    end
    function inventory.reserve(installation) return inventory.apply({ kind = 'reserve', installation = installation }) end
    function inventory.finish(id, deviceId) return inventory.apply({ kind = 'finish', installationId = id, deviceId = deviceId }) end
    function inventory.cancel(id, reason) return inventory.apply({ kind = 'cancel', installationId = id, reason = reason }) end
    return inventory
end
