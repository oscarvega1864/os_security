OSSecurity.DeviceCommands = {}

function OSSecurity.DeviceCommands.register(options)
    local registry = options.registry
    local usage = 'Uso: osdev list [offset] [limit] | create <type> | info <id> | state <id> <state> | remove <id>'
    options.register('osdev', function(source, args)
        if not options.permissions.isAdmin(source) then
            options.reply(source, 'Acceso denegado: se requiere ossecurity.admin.')
            return
        end
        local action, result, err = args[1]
        if action == 'list' and #args <= 3 then
            local offset = args[2] and tonumber(args[2]) or 0
            local limit = args[3] and tonumber(args[3]) or options.defaultPageSize
            if (args[2] and not tonumber(args[2])) or (args[3] and not tonumber(args[3])) then
                options.reply(source, 'Offset y limite deben ser numeros enteros.')
                return
            end
            result, err = registry.list(source, offset, limit)
            if result then
                options.reply(source, ('Dispositivos: %d | offset: %d | limite: %d'):format(result.total, result.offset, result.limit))
                for _, item in ipairs(result.items) do
                    options.reply(source, ('%s | %s | %s'):format(item.id, item.type, item.state))
                end
                return
            end
        elseif action == 'create' and #args == 2 then
            result, err = registry.create(source, { type = args[2] })
        elseif action == 'info' and #args == 2 then
            result, err = registry.get(source, args[2])
            if result then
                -- Resumen acotado; el historial completo permanece en el servidor.
                options.reply(source, ('%s | tipo=%s | modelo=%s | estado=%s | esquema=%d'):format(
                    result.id, result.type, result.model, result.state, result.schemaVersion))
                options.reply(source, ('creado=%d | actualizado=%d | eventos=%d | propietario=%s | propiedad=%s | vehiculo=%s'):format(
                    result.createdAt, result.updatedAt, #result.history,
                    result.owner or '-', result.propertyId or '-', result.vehicleId or '-'))
                options.reply(source, 'metadatos=' .. options.encode(result.metadata))
                return
            end
        elseif action == 'state' and #args == 3 then
            result, err = registry.setState(source, args[2], args[3])
        elseif action == 'remove' and #args == 2 then
            result, err = registry.retire(source, args[2])
        else
            options.reply(source, usage)
            return
        end
        if result then
            options.reply(source, ('Persistido: %s | %s | %s'):format(result.id, result.type, result.state))
        else
            options.reply(source, err or 'No se pudo completar la operacion.')
        end
    end, false) -- ACE propio validado antes de consultar o modificar datos.
end
