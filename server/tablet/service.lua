local util = OSSecurity.Util
OSSecurity.TabletService = {}

function OSSecurity.TabletService.new(options)
    local service = {}
    local config = OSSecurity.GameplayConfig
    local function summary(actor, device)
        local diagnosis = OSSecurity.ComponentLifecycle.diagnose(device)
        local components = {}
        if device.schemaVersion == 2 then
            for slot, component in pairs(device.condition.components) do
                components[#components + 1] = { slot = slot, id = component.id, type = component.type, model = component.model,
                    health = component.health, state = component.state, installedAt = component.installedAt,
                    lastMaintenanceAt = component.lastMaintenanceAt, operatingHours = component.wear.operatingHours }
            end
        end
        table.sort(components, function(a, b) return a.slot < b.slot end)
        local actions = {}
        for _, action in ipairs({ 'inspect', 'repair', 'replace', 'provision', 'beginMaintenance' }) do
            actions[action] = options.auth.access(actor, device, action)
        end
        local snapshot = options.inventory.snapshot()
        local installation = device.metadata.installationId and snapshot and snapshot.installations[device.metadata.installationId]
        local history = options.registry.serviceHistory(0, device.id, 0, 100)
        local latest
        if history and history.total > 0 then
            local page = options.registry.serviceHistory(0, device.id, history.total - 1, 1)
            if page and page.items[1] then latest = { kind = page.items[1].kind, at = page.items[1].at } end
        end
        return { id = device.id, displayId = OSSecurity.Brand.DevicePrefix .. ' · ' .. device.id, type = device.type,
            model = device.model, state = device.state, schemaVersion = device.schemaVersion, updatedAt = device.updatedAt,
            health = diagnosis.health, components = components, lastIntervention = latest, actions = actions,
            physical = installation ~= nil and installation.status == 'committed' and installation.deviceId == device.id,
            remoteVideo = false }
    end
    function service.inventory(actor)
        local account, err = options.inventory.get(actor.principal)
        if not account then return nil, err end
        local items = {}
        for id, entry in pairs(account.items) do
            local definition = OSSecurity.ItemCatalog[id]
            items[#items + 1] = { id = id, name = definition.name, category = definition.category, count = entry.count,
                usable = definition.tablet ~= nil or definition.usable == 'placement' }
        end
        table.sort(items, function(a, b) return a.id < b.id end)
        return { items = items }
    end
    function service.session(session)
        return { token = session.token, sequence = session.sequence, expires = session.expires,
            kind = session.actor.kind, profile = OSSecurity.Brand.Profiles[session.actor.role],
            canInstall = session.actor.kind == 'operations' and OSSecurity.GameplayConfig.Profiles[session.actor.role].install == true,
            employeeId = session.actor.kind == 'operations' and options.employeeId(session.actor.principal) or nil,
            brand = util.copy(OSSecurity.Brand), capabilities = util.copy(OSSecurity.IntegrationContracts.cctv) }
    end
    function service.list(actor, args)
        if not util.object(args, { offset = true, module = true })
            or (args.offset ~= nil and not util.integer(args.offset, 0, OSSecurity.ServerConfig.MaxDevices)) then
            return nil, 'Paginacion no valida.'
        end
        local module = args.module or 'overview'
        local enabled = false
        for _, definition in ipairs(OSSecurity.Brand.Modules[actor.kind] or {}) do
            if definition.id == module and definition.implemented then enabled = true end
        end
        if not enabled or module == 'inventory' then return nil, 'Modulo no disponible.' end
        local page, err = options.registry.list(0, 0, 100)
        if not page then return nil, err end
        local accessible = {}
        for offset = 0, math.max(0, page.total - 1), 100 do
            local current = offset == 0 and page or options.registry.list(0, offset, 100)
            if not current then return nil, 'Registro no disponible.' end
            for _, entry in ipairs(current.items) do
                local device = options.registry.get(0, entry.id)
                if device and options.auth.access(actor, device, 'view') and (module ~= 'cctv' or device.type == 'cctv_camera') then
                    accessible[#accessible + 1] = device
                end
            end
        end
        local items, offset = {}, args.offset or 0
        for index = offset + 1, math.min(offset + config.PageSize, #accessible) do items[#items + 1] = summary(actor, accessible[index]) end
        return { items = items, total = #accessible, offset = offset, limit = config.PageSize }
    end
    function service.device(actor, id)
        if not OSSecurity.DeviceValidation.id(id) then return nil, 'Dispositivo no accesible.' end
        local device = options.registry.get(0, id)
        if not device or not options.auth.access(actor, device, 'view') then return nil, 'Dispositivo no accesible.' end
        return device
    end
    function service.get(actor, args)
        if not util.object(args, { deviceId = true }) then return nil, 'Consulta no valida.' end
        local device, err = service.device(actor, args.deviceId)
        if not device then return nil, err end
        return summary(actor, device)
    end
    function service.maintain(actor, args)
        if not util.object(args, { deviceId = true, action = true, slot = true }) then return nil, 'Operacion no valida.' end
        local device, err = service.device(actor, args.deviceId)
        if not device then return nil, err end
        local action = args.action
        if type(action) ~= 'string' or not ({ inspect = true, repair = true, replace = true, provision = true, beginMaintenance = true })[action]
            or not options.auth.access(actor, device, action) then return nil, 'Perfil o alcance insuficiente.' end
        local updated, reason
        if action == 'beginMaintenance' then updated, reason = options.registry.setState(0, device.id, 'maintenance')
        else
            local arguments = {}
            if action == 'repair' or action == 'replace' then arguments.slot = args.slot end
            updated, reason = options.registry.service(0, device.id, action, arguments)
        end
        if not updated then return nil, reason end
        return summary(actor, updated)
    end
    return service
end
