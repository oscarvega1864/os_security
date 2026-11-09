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
    local auth = OSSecurity.TabletAuthorization.new({ identity = identity, inventory = inventory, holdings = holdings, ace = options.ace,
        employment = options.employment, sites = options.sites })
    local sessions = OSSecurity.TabletSessions.new({ auth = auth, alive = options.alive, now = options.now,
        token = function(source) tokenCounter = tokenCounter + 1; return options.token(source, tokenCounter) end })
    local alarmsRef -- se asigna al crear el servicio de alarmas (mas abajo)
    local placement = OSSecurity.InstallationService.new({ inventory = inventory, holdings = holdings, registry = options.registry,
        now = options.now, world = options.world, audit = options.audit, schedule = options.schedule,
        alive = options.alive, invalidate = sessions.close, log = options.log,
        -- Desmontar: perfil con instalacion y acceso tecnico al dispositivo, o su propietario.
        canRemove = function(actor, device)
            if actor.kind == 'operations' then
                return config.Profiles[actor.role] and config.Profiles[actor.role].install == true and auth.access(actor, device, 'repair') == true
            end
            return actor.kind == 'client' and device.owner == actor.principal
        end,
        removed = function(deviceId) if alarmsRef then alarmsRef.forgetDevice(deviceId) end end })
    local function actorOf(source)
        local principal = identity.resolve(source)
        if not principal then return nil end
        return { principal = principal, holder = holdings.external() and holdings.holder(source) or nil, role = 'client', kind = 'client', source = source }
    end
    local effects = options.alarmEffects or {}
    local alarms = OSSecurity.AlarmService.new({
        inventory = inventory, registry = options.registry, now = options.now, world = options.world,
        site = function(deviceId)
            local site = inventory.site(deviceId)
            if not site then return nil end
            return options.sites and options.sites.label(site) or (OSSecurity.Sites.Labels[site.kind] .. ' ' .. site.id)
        end,
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
        siren = effects.siren or function() end,
        alert = function(device, text, kind)
            if not effects.notify then return end
            local notified = {}
            for _, player in ipairs((effects.players or function() return {} end)()) do
                local actor = actorOf(player.source)
                local owner = actor and auth.access(actor, device, 'view')
                local staff = options.employment and options.employment(player.source) ~= nil
                if (owner or staff) and not notified[player.source] then
                    notified[player.source] = true
                    effects.notify(player.source, text, kind, device.position)
                end
            end
        end
    })
    alarmsRef = alarms
    local service = OSSecurity.TabletService.new({ inventory = inventory, holdings = holdings, registry = options.registry, auth = auth, employeeId = options.employeeId,
        sites = options.sites, alarms = alarms })
    local controller = OSSecurity.TabletController.new({ inventory = inventory, holdings = holdings, identity = identity, auth = auth,
        sessions = sessions, service = service, placement = placement, audit = options.audit })
    local gameplay = { inventory = inventory, identity = identity, placement = placement, holdings = holdings, alarms = alarms }
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
    function gameplay.clear() ready = false; controller.clear(); alarms.clear() end
    local commands = OSSecurity.GameplayCommands.register({ sites = options.sites, register = options.register, reply = options.reply, permissions = options.permissions,
        identity = identity, inventory = inventory, holdings = holdings, registry = options.registry, world = options.world, ready = gameplay.status })
    function gameplay.anchorAt(source, payload)
        if not gameplay.status() then return nil, 'Flujo Gruppe Sechs no disponible; revisar servidor.' end
        return commands.aimed(source, payload)
    end
    return gameplay
end
