OSSecurity.Gameplay = {}

function OSSecurity.Gameplay.new(options)
    local ready, tokenCounter = false, 0
    local config = OSSecurity.GameplayConfig
    local identity = OSSecurity.Identity.new({ connected = options.connected, identifier = options.identifier })
    local store = OSSecurity.JsonStorage.new({
        base = config.StorageBase, limits = config, validation = OSSecurity.InventoryState,
        initialSnapshot = OSSecurity.InventoryState.initial(),
        read = options.files.read, write = options.files.write,
        encode = OSSecurity.JsonCodec.encode, decode = OSSecurity.JsonCodec.decode,
        log = options.log
    })
    local inventory = OSSecurity.StandaloneInventory.new({ store = store, limits = config, now = options.now })
    -- Objetos: registro local por cuenta (standalone) o proveedor externo por personaje (options.items).
    -- Montajes, instalaciones y concesiones siempre viven en el registro local.
    local items = options.items
    local holdings = {}
    function holdings.external() return items ~= nil end
    function holdings.available() return items == nil or items.available() end
    function holdings.holder(source)
        if not items then return nil end
        return items.holder(source)
    end
    function holdings.has(actor, item, amount)
        if items then return actor.holder ~= nil and items.has(actor.holder, item, amount or 1) end
        return inventory.has(actor.principal, item, amount or 1)
    end
    function holdings.list(actor)
        if items then
            if not actor.holder then return nil, 'Personaje activo no disponible.' end
            return items.list(actor.holder)
        end
        local account, err = inventory.get(actor.principal)
        if not account then return nil, err end
        local result = {}
        for item, entry in pairs(account.items) do result[item] = entry.count end
        return result
    end
    function holdings.take(installation)
        if not installation.holder then return true end
        return items.take(installation.id, installation.holder, installation.materials)
    end
    function holdings.refund(installation)
        if not installation.holder then return true end
        if not items then return nil, 'Proveedor externo no configurado; devolucion pendiente.' end
        return items.refund(installation.id, installation.holder, installation.materials)
    end
    function holdings.grant(holder, item, amount, operationId) return items.grant(holder, item, amount, operationId) end
    local auth = OSSecurity.TabletAuthorization.new({ identity = identity, inventory = inventory, holdings = holdings, ace = options.ace })
    local sessions = OSSecurity.TabletSessions.new({ auth = auth, alive = options.alive, now = options.now,
        token = function(source) tokenCounter = tokenCounter + 1; return options.token(source, tokenCounter) end })
    local placement = OSSecurity.InstallationService.new({ inventory = inventory, holdings = holdings, registry = options.registry,
        now = options.now, world = options.world, audit = options.audit, schedule = options.schedule,
        alive = options.alive, invalidate = sessions.close, log = options.log })
    local service = OSSecurity.TabletService.new({ inventory = inventory, holdings = holdings, registry = options.registry, auth = auth, employeeId = options.employeeId })
    local controller = OSSecurity.TabletController.new({ inventory = inventory, holdings = holdings, identity = identity, auth = auth,
        sessions = sessions, service = service, placement = placement, audit = options.audit })
    local gameplay = { inventory = inventory, identity = identity, placement = placement, holdings = holdings }
    function gameplay.status() return ready and inventory.status() and options.registry.status() end
    function gameplay.load()
        ready = false
        local loaded, err = inventory.load()
        if not loaded then return nil, err end
        if not options.registry.status() then return nil, 'Device Core no disponible para reconciliar instalaciones.' end
        local recovered, recoveryError = placement.recover()
        if not recovered then return nil, recoveryError end
        ready = true
        return true
    end
    function gameplay.handle(source, request)
        if not gameplay.status() then return { ok = false, error = 'Flujo Gruppe Sechs no disponible; revisar servidor.', close = true } end
        return controller.handle(source, request)
    end
    function gameplay.drop(source) controller.drop(source) end
    function gameplay.clear() ready = false; controller.clear() end
    OSSecurity.GameplayCommands.register({ register = options.register, reply = options.reply, permissions = options.permissions,
        identity = identity, inventory = inventory, holdings = holdings, registry = options.registry, world = options.world, ready = gameplay.status })
    return gameplay
end
