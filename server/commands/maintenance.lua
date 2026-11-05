OSSecurity.MaintenanceCommands = {}

function OSSecurity.MaintenanceCommands.register(options)
    local registry = options.registry
    local usage = 'Uso: osmaint list|inspect|diagnose|provision <id> | simulate <id> <horas> | repair <id> <slot> | replace <id> <slot> [modelo] | history <id> [offset] [limit]'
    local function report(source, device)
        if device.schemaVersion ~= 2 then
            options.reply(source, 'Dispositivo v1: datos conservados. Equipar con osmaint provision <id>.')
            return
        end
        local diagnosis = OSSecurity.ComponentLifecycle.diagnose(device)
        options.reply(source, ('%s | administrativo=%s | salud=%.3f | condicion=%s'):format(
            device.id, device.state, diagnosis.health, diagnosis.state))
        local slots = {}
        for slot in pairs(device.condition.components) do slots[#slots + 1] = slot end
        table.sort(slots)
        for _, slot in ipairs(slots) do
            local component = device.condition.components[slot]
            local info = diagnosis.components[slot]
            options.reply(source, ('%s | %s | %s/%s | salud=%.3f (%s) | horas=%.3f | perdida/h=%.6f | descartadas=%.3f'):format(
                slot, component.id, component.type, component.model, component.health, component.state,
                info.operatingHours, info.ratePerHour, info.discardedHours))
            options.reply(source, ('instalado=%d | mantenimiento=%s | causas=%s'):format(
                component.installedAt, component.lastMaintenanceAt or '-', table.concat(info.causes, ',')))
        end
    end

    options.register('osmaint', function(source, args)
        if not options.permissions.isAdmin(source) then
            options.reply(source, 'Acceso denegado: se requiere ossecurity.admin.')
            return
        end
        local action, id, result, err = args[1], args[2]
        if action == 'list' and #args == 2 then
            result, err = registry.get(source, id)
        elseif (action == 'inspect' or action == 'diagnose' or action == 'provision') and #args == 2 then
            result, err = registry.service(source, id, action == 'diagnose' and 'inspect' or action, {})
        elseif action == 'simulate' and #args == 3 then
            result, err = registry.service(source, id, 'simulate', { hours = tonumber(args[3]) })
        elseif action == 'repair' and #args == 3 then
            result, err = registry.service(source, id, 'repair', { slot = args[3] })
        elseif action == 'replace' and (#args == 3 or #args == 4) then
            result, err = registry.service(source, id, 'replace', { slot = args[3], model = args[4] })
        elseif action == 'history' and #args >= 2 and #args <= 4 then
            local offset = args[3] and tonumber(args[3]) or 0
            local limit = args[4] and tonumber(args[4]) or options.defaultPageSize
            if (args[3] and not tonumber(args[3])) or (args[4] and not tonumber(args[4])) then
                options.reply(source, 'Offset y limite deben ser numeros enteros.')
                return
            end
            result, err = registry.serviceHistory(source, id, offset, limit)
            if result then
                options.reply(source, ('Intervenciones=%d | heredadas=%d | offset=%d'):format(result.total, result.legacyEvents, result.offset))
                for _, event in ipairs(result.items) do
                    local changes = {}
                    if event.changes then
                        for slot, change in pairs(event.changes) do
                            changes[#changes + 1] = ('%s %s -> %s salud %.3f -> %.3f'):format(slot,
                                change.before and change.before.id or '-', change.after.id,
                                change.before and change.before.health or 100, change.after.health)
                        end
                        table.sort(changes)
                    elseif event.legacy then
                        changes[1] = 'legacy component=' .. event.componentId
                    end
                    options.reply(source, ('%s | at=%d | %s'):format(event.kind, event.at, table.concat(changes, '; ')))
                end
                return
            end
        else
            options.reply(source, usage)
            return
        end
        if result then report(source, result) else options.reply(source, err or 'No se pudo completar el mantenimiento.') end
    end, false)
end
