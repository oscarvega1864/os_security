OSSecurity.GameplayCommands = {}

function OSSecurity.GameplayCommands.register(options)
    local usage = 'osg6 give <jugador> <item> <cantidad> | inventory <jugador> | migrate <jugador> | access <jugador> <dispositivo> <client|technician|supervisor|none> | anchor <id> <cliente> <instalador> <x> <y> <z> <nx> <ny> <nz> [radio] | site <dispositivo> <propiedad|negocio> <id> | site <dispositivo> none | installations | doors | door remove <puerta> | cars | diagnose'
    local holdings = options.holdings
    local function target(value)
        local player = tonumber(value)
        local principal, identityError = options.identity.resolve(player)
        if not principal then return nil, identityError end
        local actor = { principal = principal }
        if holdings.external() then
            local holder, holderError = holdings.holder(player)
            if not holder then return nil, holderError end
            actor.holder = holder
        end
        return actor
    end
    -- Alta de montaje comun a la consola (coordenadas escritas) y a /g6anchor (punto apuntado en el juego).
    local function createAnchor(id, ownerSource, installerSource, position, normal, radius, bucket, site)
        local owner = options.identity.resolve(tonumber(ownerSource))
        local installer = options.identity.resolve(tonumber(installerSource))
        if not owner or not installer or not OSSecurity.InventoryState.vector(position, 1000000)
            or not OSSecurity.InventoryState.vector(normal, 1000) or not OSSecurity.Util.finite(radius) then
            return nil, 'Identidades o coordenadas de montaje invalidas.'
        end
        local round = OSSecurity.Util.round
        -- Componentes residuales del raycast (|v| < 1e-6) a cero antes de normalizar; despues, 9 decimales.
        normal = { x = round(normal.x, 6), y = round(normal.y, 6), z = round(normal.z, 6) }
        local length = math.sqrt(normal.x^2 + normal.y^2 + normal.z^2)
        if length < 0.001 then return nil, 'La normal no puede ser cero.' end
        position = { x = round(position.x, 4), y = round(position.y, 4), z = round(position.z, 4) }
        for _, axis in ipairs({ 'x', 'y', 'z' }) do normal[axis] = round(normal[axis] / length, 9) end
        if bucket == nil then local _, installerBucket = options.world(tonumber(installerSource)); bucket = installerBucket end
        return options.inventory.apply({ kind = 'anchor', anchor = { id = id, owner = owner, installer = installer,
            position = position, normal = normal, radius = round(radius, 3), bucket = bucket, site = site } })
    end
    options.register('osg6', function(source, args)
        if not options.permissions.isAdmin(source) then options.reply(source, 'Se requiere ossecurity.admin.'); return end
        local action, result, err = args[1]
        if action == 'give' and #args == 4 then
            local actor, actorError = target(args[2])
            if not actor then options.reply(source, actorError); return end
            local amount = tonumber(args[4])
            if not OSSecurity.ItemCatalog[args[3]] or not OSSecurity.Util.integer(amount, 1, OSSecurity.GameplayConfig.MaxItemQuantity) then
                options.reply(source, 'Objeto o cantidad no validos.'); return
            end
            if holdings.external() then result, err = holdings.grant(actor.holder, args[3], amount)
            else result, err = options.inventory.apply({ kind = 'grant', principal = actor.principal, item = args[3], amount = amount }) end
        elseif action == 'inventory' and #args == 2 then
            local actor, actorError = target(args[2])
            if not actor then options.reply(source, actorError); return end
            local counts, reason = holdings.list(actor)
            if not counts then options.reply(source, reason); return end
            local items = {}
            for item, amount in pairs(counts) do items[#items + 1] = ('%s=%d'):format(item, amount) end
            table.sort(items); options.reply(source, #items > 0 and table.concat(items, ' | ') or OSSecurity.Brand.Text.noInventory)
            return
        elseif action == 'migrate' and #args == 2 then
            -- Pasa los objetos locales de la cuenta al personaje activo en el proveedor externo.
            -- Clave de operacion = total migrado tras esta entrega: tras un corte se repite sin duplicar.
            if not holdings.external() then options.reply(source, 'Migracion disponible solo con ossecurity_items=os_inventory.'); return end
            local actor, actorError = target(args[2])
            if not actor then options.reply(source, actorError); return end
            local account, reason = options.inventory.get(actor.principal)
            if not account then options.reply(source, reason); return end
            local names = {}
            for item in pairs(account.items) do names[#names + 1] = item end
            table.sort(names)
            if #names == 0 then options.reply(source, 'No hay objetos locales que migrar.'); return end
            local moved = {}
            for _, item in ipairs(names) do
                local amount = account.items[item].count
                local total = ((account.migrated or {})[item] or 0) + amount
                local operationId = ('g6mig:%s:%s:%d'):format(actor.principal:sub(9, 24), item, total)
                local granted, grantError = holdings.grant(actor.holder, item, amount, operationId)
                if not granted then options.reply(source, ('Migracion detenida en %s: %s'):format(item, tostring(grantError))); return end
                local saved, saveError = options.inventory.apply({ kind = 'migrate', principal = actor.principal, item = item, amount = amount })
                if not saved then options.reply(source, ('Migracion detenida en %s: %s. Repetir el comando no duplica.'):format(item, tostring(saveError))); return end
                moved[#moved + 1] = ('%s=%d'):format(item, amount)
            end
            options.reply(source, ('Migrado a %s: %s'):format(actor.holder, table.concat(moved, ' | ')))
            return
        elseif action == 'access' and #args == 4 then
            local principal, identityError = options.identity.resolve(tonumber(args[2]))
            if not principal then options.reply(source, identityError); return end
            if not options.registry.get(0, args[3]) then options.reply(source, 'Dispositivo no disponible.'); return end
            result, err = options.inventory.apply({ kind = 'access', principal = principal, deviceId = args[3], role = args[4] })
        elseif action == 'site' and (#args == 3 or #args == 4) then
            -- Vincula un dispositivo a una propiedad o negocio: su titular lo ve en la tablet Client.
            if not options.registry.get(0, args[2]) then options.reply(source, 'Dispositivo no disponible.'); return end
            local site
            if #args == 4 then
                local kind = ({ propiedad = 'property', property = 'property', negocio = 'business', business = 'business' })[args[3]]
                site = { kind = kind, id = tonumber(args[4]) }
                if not kind or not OSSecurity.InventoryState.site(site) then options.reply(source, 'Tipo o ID no validos.'); return end
                if not options.sites or not options.sites.available() then options.reply(source, 'Proveedor de propiedades no disponible.'); return end
                if not options.sites.get(site) then options.reply(source, ('%s inexistente.'):format(OSSecurity.Sites.Labels[kind] .. ' ' .. site.id)); return end
            elseif args[3] ~= 'none' then options.reply(source, usage); return end
            result, err = options.inventory.apply({ kind = 'site', deviceId = args[2], site = site })
            if result then
                options.reply(source, site and ('%s vinculado a %s.'):format(args[2], options.sites.label(site)) or (args[2] .. ' desvinculado.'))
                return
            end
        elseif action == 'anchor' and (#args == 10 or #args == 11) then
            local position = { x = tonumber(args[5]), y = tonumber(args[6]), z = tonumber(args[7]) }
            local normal = { x = tonumber(args[8]), y = tonumber(args[9]), z = tonumber(args[10]) }
            local radius = args[11] and tonumber(args[11]) or 0.75
            if args[11] and not tonumber(args[11]) then options.reply(source, 'Identidades o coordenadas de montaje invalidas.'); return end
            result, err = createAnchor(args[2], args[3], args[4], position, normal, radius)
        elseif action == 'installations' and #args == 1 then
            local snapshot, reason = options.inventory.snapshot()
            if not snapshot then options.reply(source, reason); return end
            local ids = {}; for id in pairs(snapshot.installations) do ids[#ids + 1] = id end; table.sort(ids)
            for _, id in ipairs(ids) do
                local installation = snapshot.installations[id]
                options.reply(source, ('%s | %s | %s'):format(id, installation.status, installation.deviceId or '-'))
            end
            options.reply(source, ('Instalaciones: %d'):format(#ids)); return
        elseif action == 'doors' and #args == 1 then
            local lines = options.locks.describe()
            options.reply(source, ('Puertas con cerradura: %d'):format(#lines))
            for _, line in ipairs(lines) do options.reply(source, line) end
            return
        elseif action == 'door' and args[2] == 'remove' and #args == 3 then
            local message, reason = options.locks.unregister(source, args[3])
            options.reply(source, message or reason); return
        elseif action == 'cars' and #args == 1 then
            local lines = options.cars.describe()
            options.reply(source, ('Vehiculos con equipo de seguridad: %d'):format(#lines))
            for _, line in ipairs(lines) do options.reply(source, line) end
            return
        elseif action == 'diagnose' and #args == 1 then
            options.reply(source, ('Device Core=%s | Inventario=%s | Objetos=%s | Flujo G6=%s'):format(
                tostring(options.registry.status()), tostring(options.inventory.status()),
                holdings.external() and ('externo:' .. tostring(holdings.available())) or 'local', tostring(options.ready())))
            return
        else options.reply(source, usage); return end
        options.reply(source, result and 'Operacion Gruppe Sechs persistida.' or (err or 'Operacion rechazada.'))
    end, false)

    -- /g6anchor: el administrador apunta a la pared; el cliente solo propone punto y normal.
    -- El servidor exige ossecurity.admin, valida los datos y que el punto este cerca de su posicion real.
    local function aimed(source, payload)
        if not OSSecurity.Util.integer(source, 1, 2147483647) or not options.permissions.isAdmin(source) then return nil, 'Se requiere ossecurity.admin.' end
        if not OSSecurity.Util.object(payload, { id = true, client = true, installer = true, radius = true, position = true, normal = true, site = true })
            or type(payload.id) ~= 'string' or not OSSecurity.Util.integer(payload.client, 1, 2147483647)
            or (payload.installer ~= nil and not OSSecurity.Util.integer(payload.installer, 1, 2147483647))
            or (payload.radius ~= nil and not OSSecurity.Util.finite(payload.radius))
            or not OSSecurity.InventoryState.vector(payload.position, 1000000) or not OSSecurity.InventoryState.vector(payload.normal, 1000) then
            return nil, 'Uso: /g6anchor <id> <idCliente> [idInstalador] [radio], apuntando a la pared.'
        end
        local site
        if payload.site ~= nil then
            site = OSSecurity.Util.object(payload.site, { kind = true, id = true }) and { kind = payload.site.kind, id = payload.site.id } or nil
            if not site or not OSSecurity.InventoryState.site(site) then return nil, 'Propiedad o negocio no valido.' end
            if not options.sites or not options.sites.get(site) then return nil, ('%s %d inexistente.'):format(OSSecurity.Sites.Labels[site.kind], site.id) end
        end
        local here, bucket = options.world(source)
        if not here then return nil, 'Posicion del administrador no disponible.' end
        local dx, dy, dz = payload.position.x - here.x, payload.position.y - here.y, payload.position.z - here.z
        if math.sqrt(dx * dx + dy * dy + dz * dz) > OSSecurity.GameplayConfig.AnchorAimDistance then return nil, 'El punto apuntado esta demasiado lejos.' end
        local result, err = createAnchor(payload.id, payload.client, payload.installer or source, payload.position, payload.normal, payload.radius or 0.75, bucket, site)
        if not result then return nil, err end
        local anchor = result.anchors[payload.id]
        return ('Montaje %s registrado en %.2f %.2f %.2f (bucket %d)%s.'):format(payload.id, anchor.position.x, anchor.position.y, anchor.position.z, anchor.bucket,
            site and (' para ' .. options.sites.label(site)) or '')
    end
    return { aimed = aimed }
end
