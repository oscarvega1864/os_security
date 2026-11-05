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
    local auth = OSSecurity.TabletAuthorization.new({ identity = identity, inventory = inventory, ace = options.ace })
    local sessions = OSSecurity.TabletSessions.new({ auth = auth, alive = options.alive, now = options.now,
        token = function(source) tokenCounter = tokenCounter + 1; return options.token(source, tokenCounter) end })
    local placement = OSSecurity.InstallationService.new({ inventory = inventory, registry = options.registry,
        now = options.now, world = options.world, audit = options.audit, schedule = options.schedule,
        alive = options.alive, invalidate = sessions.close })
    local service = OSSecurity.TabletService.new({ inventory = inventory, registry = options.registry, auth = auth, employeeId = options.employeeId })
    local controller = OSSecurity.TabletController.new({ inventory = inventory, identity = identity, auth = auth,
        sessions = sessions, service = service, placement = placement, audit = options.audit })
    local gameplay = { inventory = inventory, identity = identity, placement = placement }
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
        identity = identity, inventory = inventory, registry = options.registry, world = options.world, ready = gameplay.status })
    return gameplay
end
