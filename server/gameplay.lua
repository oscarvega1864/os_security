OSSecurity.Gameplay = {}

function OSSecurity.Gameplay.new(options)
    local ready, tokenCounter = false, 0
    local config = OSSecurity.GameplayConfig
    -- Con proveedor externo de objetos y characterOwnership, cada personaje es titular de lo suyo.
    local characterOwnership = options.items ~= nil and options.characterOwnership == true
    local identity = OSSecurity.Identity.new({ connected = options.connected, identifier = options.identifier,
        character = characterOwnership and function(source) return options.items.holder(source) end or nil })
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
    local function ownerOf(device) return inventory.owner(device.id) or device.owner end
    local auth = OSSecurity.TabletAuthorization.new({ identity = identity, inventory = inventory, holdings = holdings, ace = options.ace, ownerOf = ownerOf,
        employment = options.employment, sites = options.sites })
    local sessions = OSSecurity.TabletSessions.new({ auth = auth, alive = options.alive, now = options.now,
        token = function(source) tokenCounter = tokenCounter + 1; return options.token(source, tokenCounter) end })
    local alarmsRef -- se asigna al crear el servicio de alarmas (mas abajo)
    local placement = OSSecurity.InstallationService.new({ inventory = inventory, holdings = holdings, registry = options.registry,
        now = options.now, world = options.world, audit = options.audit, schedule = options.schedule,
        alive = options.alive, invalidate = sessions.close, log = options.log, ownerOf = ownerOf,
        -- Desmontar: perfil con instalacion y acceso tecnico al dispositivo, o su propietario.
        canRemove = function(actor, device)
            if actor.kind == 'operations' then
                return config.Profiles[actor.role] and config.Profiles[actor.role].install == true and auth.access(actor, device, 'repair') == true
            end
            return actor.kind == 'client' and ownerOf(device) == actor.principal
        end,
        removed = function(deviceId) if alarmsRef then alarmsRef.forgetDevice(deviceId) end end })
    local function actorOf(source)
        local principal = identity.resolve(source)
        if not principal then return nil end
        return { principal = principal, holder = holdings.external() and holdings.holder(source) or nil, role = 'client', kind = 'client', source = source }
    end
    local effects = options.alarmEffects or {}
    local function siteLabel(deviceId)
        local site = inventory.site(deviceId)
        if not site then return nil end
        return options.sites and options.sites.label(site) or (OSSecurity.Sites.Labels[site.kind] .. ' ' .. site.id)
    end
    local dispatchRef, staffRef -- central de operaciones y "es personal G6" (se crean mas abajo)
    local alarms = OSSecurity.AlarmService.new({
        inventory = inventory, registry = options.registry, now = options.now, world = options.world,
        site = siteLabel,
        authorized = function(actor, device) return actor ~= nil and auth.access(actor, device, 'view') == true end,
        actorOf = actorOf,
        players = effects.players or function() return {} end,
        hash = effects.hash or function(pin) return 'plain:' .. pin end,
        verify = effects.verify or function(pin, hash) return hash == 'plain:' .. pin end,
        serial = effects.serial or function() return tostring(options.now()) end,
        who = effects.who or function(source) return 'jugador ' .. source end,
        whoPrincipal = function() return 'tablet' end,
        tagsSupported = function() return holdings.external() end,
        heldTags = function(source, deviceId)
            if not items then return {} end
            local holder = holdings.holder(source)
            return holder and items.tagSerials(holder, deviceId) or {}
        end,
        makeTag = function(actor, device, serial)
            if not items or not actor.holder then return nil, 'Personaje activo no disponible.' end
            return items.makeTag(actor.holder, device.id, serial)
        end,
        entry = effects.entry or function() end,
        entryStop = effects.entryStop or function() end,
        siren = effects.siren or function() end,
        alert = function(device, text, kind, reason)
            -- Con central de operaciones (salto o manipulacion), el personal G6 recibe el aviso de la central
            -- (queda guardado y se puede asignar); aqui solo se avisa al titular. Sin ella, a todos como antes.
            local central = reason ~= nil and dispatchRef ~= nil and staffRef ~= nil
            if effects.notify then
                local notified = {}
                for _, player in ipairs((effects.players or function() return {} end)()) do
                    local actor = actorOf(player.source)
                    local owner = actor and auth.access(actor, device, 'view')
                    local staff = options.employment and options.employment(player.source) ~= nil
                    if central and staffRef(player.source) then owner, staff = false, false end
                    if (owner or staff) and not notified[player.source] then
                        notified[player.source] = true
                        effects.notify(player.source, text, kind, device.position)
                    end
                end
            end
            if central then
                dispatchRef.raise(device, reason, ownerOf(device), siteLabel(device.id) or (OSSecurity.Brand.DevicePrefix .. ' · ' .. device.id))
            end
        end
    })
    alarmsRef = alarms
    local locks = OSSecurity.LockService.new({ inventory = inventory, world = options.world, now = options.now, sites = options.sites,
        isAdmin = function(source) return options.permissions ~= nil and options.permissions.isAdmin(source) == true end,
        employment = options.employment, holdings = holdings, log = options.log, changed = options.locksChanged,
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    local noop = function() end
    local carEffects = options.carEffects or {}
    local cars = OSSecurity.CarService.new({ inventory = inventory, now = options.now, world = options.world, holdings = holdings,
        employment = options.employment, log = options.log,
        isAdmin = function(source) return options.permissions ~= nil and options.permissions.isAdmin(source) == true end,
        vehicles = options.vehicles or { asset = noop, alias = noop, driving = noop },
        effects = { locked = carEffects.locked or noop, alarm = carEffects.alarm or noop, notifyOwner = carEffects.notifyOwner or noop },
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    local lockpick = OSSecurity.LockpickService.new({ holdings = holdings, world = options.world, now = options.now, locks = locks, cars = cars,
        random = options.random or math.random, notifyOwner = carEffects.notifyOwner or noop,
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    -- Tienda: personal G6 = empleo de servicio o ACE profesional (tecnico, supervisor o admin).
    local function isStaff(source)
        for _, ace in ipairs({ config.Ace.technician, config.Ace.supervisor, config.Ace.admin }) do
            if options.ace(source, ace) then return true end
        end
        if not options.employment then return false end
        local holder = holdings.external() and holdings.holder(source) or nil
        return options.employment(source, holder) ~= nil
    end
    local shop = OSSecurity.ShopService.new({ holdings = holdings, inventory = inventory, identity = identity, world = options.world,
        now = options.now, isStaff = isStaff, log = options.log, files = options.files, moved = options.shopMoved,
        isAdmin = function(source) return options.permissions ~= nil and options.permissions.isAdmin(source) == true end,
        money = options.money or { available = function() return false end, balance = noop, charge = noop, refund = noop },
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    local orders = OSSecurity.OrderService.new({ inventory = inventory, identity = identity, world = options.world, now = options.now,
        sites = options.sites, alias = (options.vehicles or {}).alias, playerName = options.playerName, players = options.players,
        money = options.money or { available = function() return false end, charge = noop, refund = noop }, isStaff = isStaff,
        notify = options.notifyPlayer,
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    local dispatch = OSSecurity.DispatchService.new({ inventory = inventory, identity = identity, world = options.world, now = options.now,
        sites = options.sites, alias = (options.vehicles or {}).alias, playerName = options.playerName, players = options.players,
        isStaff = isStaff, notify = options.notifyPlayer or effects.notify,
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    dispatchRef, staffRef = dispatch, isStaff
    local zones = OSSecurity.ZoneService.new({ inventory = inventory, holdings = holdings, identity = identity, world = options.world, now = options.now,
        sites = options.sites, players = options.players, playerName = options.playerName,
        alias = (options.vehicles or {}).alias, productOfModel = placement.productOfModel,
        profile = function(source) return auth.profile(source, 'operations') end,
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    local service = OSSecurity.TabletService.new({ inventory = inventory, holdings = holdings, registry = options.registry, auth = auth, ownerOf = ownerOf, employeeId = options.employeeId,
        sites = options.sites, alarms = alarms, locks = locks, cars = cars,
        audit = function(action, source, id) if options.audit then options.audit(action, source, id) end end })
    local controller = OSSecurity.TabletController.new({ inventory = inventory, holdings = holdings, identity = identity, auth = auth,
        sessions = sessions, service = service, placement = placement, zones = zones, orders = orders, dispatch = dispatch, audit = options.audit })
    local gameplay = { inventory = inventory, identity = identity, placement = placement, holdings = holdings, alarms = alarms, locks = locks, cars = cars,
        lockpick = lockpick, zones = zones, shop = shop, orders = orders, dispatch = dispatch }
    function gameplay.status() return ready and inventory.status() and options.registry.status() end
    -- Datos antiguos por cuenta (license): pasan al unico personaje que hizo sus instalaciones.
    -- Si una cuenta instalo con varios personajes no se adivina: se avisa y se deja como estaba.
    function gameplay.rehome()
        local snapshot = inventory.snapshot()
        if not snapshot then return nil, 'Inventario no disponible.' end
        local holders = {}
        for _, installation in pairs(snapshot.installations) do
            if OSSecurity.Identity.account(installation.installer) and installation.holder then
                holders[installation.installer] = holders[installation.installer] or {}
                holders[installation.installer][installation.holder] = true
            end
        end
        local accounts = {}
        for principal in pairs(snapshot.accounts) do
            if OSSecurity.Identity.account(principal) then accounts[#accounts + 1] = principal end
        end
        table.sort(accounts)
        for _, principal in ipairs(accounts) do
            local only, count = nil, 0
            for holder in pairs(holders[principal] or {}) do only, count = holder, count + 1 end
            local target = only and ('char:' .. only) or nil
            if count == 1 and OSSecurity.Identity.character(target) then
                local done, err = inventory.apply({ kind = 'rehome', principal = principal, target = target })
                if not done then return nil, 'No se pudieron pasar los datos de la cuenta a su personaje: ' .. tostring(err) end
                if options.log then options.log(('Datos de %s... asignados al personaje %s.'):format(principal:sub(1, 14), only)) end
            elseif options.log then
                options.log(('Cuenta %s... sin un personaje claro (%d); sus datos no se muestran a ningun personaje.'):format(principal:sub(1, 14), count))
            end
        end
        return true
    end
    function gameplay.load()
        ready = false
        local loaded, err = inventory.load()
        if not loaded then return nil, err end
        if characterOwnership then
            local moved, moveError = gameplay.rehome()
            if not moved then return nil, moveError end
        end
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
    function gameplay.drop(source) controller.drop(source); locks.drop(source); cars.drop(source); lockpick.drop(source); shop.drop(source) end
    function gameplay.clear() ready = false; controller.clear(); alarms.clear(); locks.clear(); cars.clear(); lockpick.clear() end
    -- Zona marcada con el visor (desde la tablet): el servidor revalida perfil, cercania y datos.
    function gameplay.zoneAt(source, payload)
        if not gameplay.status() then return nil, 'Flujo Gruppe Sechs no disponible; revisar servidor.' end
        return zones.commit(source, payload)
    end
    local commands = OSSecurity.GameplayCommands.register({ sites = options.sites, register = options.register, reply = options.reply, permissions = options.permissions,
        identity = identity, inventory = inventory, holdings = holdings, registry = options.registry, world = options.world, ready = gameplay.status,
        locks = locks, cars = cars })
    function gameplay.anchorAt(source, payload)
        if not gameplay.status() then return nil, 'Flujo Gruppe Sechs no disponible; revisar servidor.' end
        return commands.aimed(source, payload)
    end
    return gameplay
end
