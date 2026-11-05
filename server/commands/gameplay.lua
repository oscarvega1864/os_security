OSSecurity.GameplayCommands = {}

function OSSecurity.GameplayCommands.register(options)
    local usage = 'osg6 give <jugador> <item> <cantidad> | inventory <jugador> | access <jugador> <dispositivo> <client|technician|supervisor|none> | anchor <id> <cliente> <instalador> <x> <y> <z> <nx> <ny> <nz> [radio] | installations | diagnose'
    options.register('osg6', function(source, args)
        if not options.permissions.isAdmin(source) then options.reply(source, 'Se requiere ossecurity.admin.'); return end
        local action, result, err = args[1]
        if action == 'give' and #args == 4 then
            local principal, identityError = options.identity.resolve(tonumber(args[2]))
            if not principal then options.reply(source, identityError); return end
            result, err = options.inventory.apply({ kind = 'grant', principal = principal, item = args[3], amount = tonumber(args[4]) })
        elseif action == 'inventory' and #args == 2 then
            local principal, identityError = options.identity.resolve(tonumber(args[2]))
            if not principal then options.reply(source, identityError); return end
            local account, reason = options.inventory.get(principal)
            if not account then options.reply(source, reason); return end
            local items = {}
            for item, entry in pairs(account.items) do items[#items + 1] = ('%s=%d'):format(item, entry.count) end
            table.sort(items); options.reply(source, #items > 0 and table.concat(items, ' | ') or OSSecurity.Brand.Text.noInventory)
            return
        elseif action == 'access' and #args == 4 then
            local principal, identityError = options.identity.resolve(tonumber(args[2]))
            if not principal then options.reply(source, identityError); return end
            if not options.registry.get(0, args[3]) then options.reply(source, 'Dispositivo no disponible.'); return end
            result, err = options.inventory.apply({ kind = 'access', principal = principal, deviceId = args[3], role = args[4] })
        elseif action == 'anchor' and (#args == 10 or #args == 11) then
            local owner = options.identity.resolve(tonumber(args[3]))
            local installer = options.identity.resolve(tonumber(args[4]))
            local position = { x = tonumber(args[5]), y = tonumber(args[6]), z = tonumber(args[7]) }
            local normal = { x = tonumber(args[8]), y = tonumber(args[9]), z = tonumber(args[10]) }
            local radius = args[11] and tonumber(args[11]) or 0.75
            if not owner or not installer or not OSSecurity.InventoryState.vector(position, 1000000)
                or not OSSecurity.InventoryState.vector(normal, 1000) or (args[11] and not tonumber(args[11])) then
                options.reply(source, 'Identidades o coordenadas de montaje invalidas.'); return
            end
            local length = math.sqrt(normal.x^2 + normal.y^2 + normal.z^2)
            if length < 0.001 then options.reply(source, 'La normal no puede ser cero.'); return end
            for _, axis in ipairs({ 'x', 'y', 'z' }) do
                normal[axis] = OSSecurity.ComponentWear.number(normal[axis] / length)
                position[axis] = OSSecurity.ComponentWear.number(position[axis])
            end
            local _, bucket = options.world(tonumber(args[4]))
            result, err = options.inventory.apply({ kind = 'anchor', anchor = { id = args[2], owner = owner, installer = installer,
                position = position, normal = normal, radius = OSSecurity.ComponentWear.number(radius), bucket = bucket } })
        elseif action == 'installations' and #args == 1 then
            local snapshot, reason = options.inventory.snapshot()
            if not snapshot then options.reply(source, reason); return end
            local ids = {}; for id in pairs(snapshot.installations) do ids[#ids + 1] = id end; table.sort(ids)
            for _, id in ipairs(ids) do
                local installation = snapshot.installations[id]
                options.reply(source, ('%s | %s | %s'):format(id, installation.status, installation.deviceId or '-'))
            end
            options.reply(source, ('Instalaciones: %d'):format(#ids)); return
        elseif action == 'diagnose' and #args == 1 then
            options.reply(source, ('Device Core=%s | Inventario=%s | Flujo G6=%s'):format(
                tostring(options.registry.status()), tostring(options.inventory.status()), tostring(options.ready())))
            return
        else options.reply(source, usage); return end
        options.reply(source, result and 'Operacion Gruppe Sechs persistida.' or (err or 'Operacion rechazada.'))
    end, false)
end
