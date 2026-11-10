local util = OSSecurity.Util
OSSecurity.TabletService = {}

function OSSecurity.TabletService.new(options)
    local service = {}
    local config = OSSecurity.GameplayConfig
    -- Senal de una camara CCTV para verla en directo: instalada fisicamente, activa y con alimentacion y
    -- optica funcionando. Una optica gastada da imagen con ruido (0 limpia .. 0.75 casi perdida).
    local LIVE_STATES = { active = true, installed = true }
    local function signal(device, snapshot)
        if device.type ~= 'cctv_camera' then return nil, 'No es una camara.' end
        local installationId = device.metadata and device.metadata.installationId
        local installation = installationId and snapshot and snapshot.installations[installationId]
        if not installation or installation.status ~= 'committed' or installation.deviceId ~= device.id then
            return nil, 'Sin senal: la camara no esta instalada fisicamente.'
        end
        if not LIVE_STATES[device.state] then
            local label = OSSecurity.Brand.Text.states and OSSecurity.Brand.Text.states[device.state] or device.state
            return nil, ('Sin senal: camara en estado %s.'):format(label)
        end
        local noise = 0
        if device.schemaVersion == 2 then
            local parts = device.condition.components
            if parts.power and parts.power.health <= 0 then return nil, 'Sin senal: fallo de alimentacion.' end
            local optics = parts.optics
            if optics then
                if optics.health <= 0 then return nil, 'Sin senal: optica averiada.' end
                noise = optics.health >= 80 and 0 or optics.health >= 60 and 0.2 or optics.health >= 30 and 0.45 or 0.75
            end
        end
        local anchor = snapshot.anchors[installation.anchorId]
        return { installation = installation, noise = noise, normal = anchor and util.copy(anchor.normal) or nil }
    end
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
        local site = options.inventory.site(device.id)
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
            site = site and (options.sites and options.sites.label(site) or OSSecurity.Sites.Labels[site.kind] .. ' ' .. site.id) or nil,
            alarm = device.type == 'alarm_panel' and options.alarms and options.alarms.summary(device) or nil,
            removable = installation ~= nil and installation.status == 'committed' and installation.deviceId == device.id and device.state ~= 'retired'
                and (actor.kind == 'operations' and OSSecurity.GameplayConfig.Profiles[actor.role] and OSSecurity.GameplayConfig.Profiles[actor.role].install == true
                    and options.auth.access(actor, device, 'repair') == true or (actor.kind == 'client' and device.owner == actor.principal)),
            remoteVideo = false,
            live = device.type == 'cctv_camera' and signal(device, snapshot) ~= nil or nil,
            liveReason = device.type == 'cctv_camera' and select(2, signal(device, snapshot)) or nil }
    end
    function service.inventory(actor)
        local counts, err = options.holdings.list(actor)
        if not counts then return nil, err end
        local items = {}
        for id, count in pairs(counts) do
            local definition = OSSecurity.ItemCatalog[id]
            items[#items + 1] = { id = id, name = definition.name, category = definition.category, count = count,
                usable = definition.tablet ~= nil or definition.usable == 'placement' }
        end
        table.sort(items, function(a, b) return a.id < b.id end)
        return { items = items }
    end
    local ABILITY_ORDER = { 'view', 'inspect', 'repair', 'replace', 'provision', 'beginMaintenance', 'install' }
    function service.abilities(actor)
        local profile = actor.kind == 'operations' and OSSecurity.GameplayConfig.Profiles[actor.role] or nil
        local list = {}
        for _, ability in ipairs(ABILITY_ORDER) do if profile and profile[ability] then list[#list + 1] = ability end end
        return list
    end
    function service.session(session)
        return { token = session.token, sequence = session.sequence, expires = session.expires,
            kind = session.actor.kind, profile = OSSecurity.Brand.Profiles[session.actor.role],
            canInstall = session.actor.kind == 'operations' and OSSecurity.GameplayConfig.Profiles[session.actor.role].install == true,
            -- Solo presentacion: el servidor sigue comprobando cada accion contra el perfil y el dispositivo.
            role = session.actor.role, abilities = service.abilities(session.actor),
            employeeId = session.actor.kind == 'operations' and options.employeeId(session.actor.principal) or nil,
            brand = util.copy(OSSecurity.Brand), capabilities = util.copy(OSSecurity.IntegrationContracts.cctv) }
    end
    -- Dispositivos que el perfil puede consultar y que cumplen 'accept'.
    local function accessibleDevices(actor, accept)
        local page, err = options.registry.list(0, 0, 100)
        if not page then return nil, err end
        local accessible = {}
        for offset = 0, math.max(0, page.total - 1), 100 do
            local current = offset == 0 and page or options.registry.list(0, offset, 100)
            if not current then return nil, 'Registro no disponible.' end
            for _, entry in ipairs(current.items) do
                local device = options.registry.get(0, entry.id)
                if device and options.auth.access(actor, device, 'view') and accept(device) then accessible[#accessible + 1] = device end
            end
        end
        return accessible
    end
    -- Modulos que no son listas de dispositivos: tienen su propia accion.
    local OWN_ACTION = { locks = true, trackers = true, incidents = true, installations = true, inventory = true }
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
        if not enabled or OWN_ACTION[module] then return nil, 'Modulo no disponible.' end
        local accessible, err = accessibleDevices(actor, function(device)
            return (module ~= 'cctv' or device.type == 'cctv_camera') and (module ~= 'alarms' or device.type == 'alarm_panel')
        end)
        if not accessible then return nil, err end
        local items, offset = {}, args.offset or 0
        for index = offset + 1, math.min(offset + config.PageSize, #accessible) do items[#items + 1] = summary(actor, accessible[index]) end
        return { items = items, total = #accessible, offset = offset, limit = config.PageSize }
    end
    -- Vista en directo de una camara: encuadre (posicion, giro y normal del montaje), ruido segun la optica y
    -- las demas camaras con senal que el perfil puede ver, para cambiar sin volver a la tablet.
    function service.live(actor, args)
        if not util.object(args, { deviceId = true }) then return nil, 'Consulta no valida.' end
        local device, err = service.device(actor, args.deviceId)
        if not device then return nil, err end
        local snapshot = options.inventory.snapshot()
        local feed, reason = signal(device, snapshot)
        if not feed then return nil, reason end
        local cameras, index = {}, 1
        local accessible = accessibleDevices(actor, function(candidate) return signal(candidate, snapshot) ~= nil end) or {}
        table.sort(accessible, function(a, b) return a.id < b.id end)
        for _, camera in ipairs(accessible) do
            local site = options.inventory.site(camera.id)
            cameras[#cameras + 1] = { id = camera.id, site = site and options.sites and options.sites.label(site) or nil }
            if camera.id == device.id then index = #cameras end
        end
        local site = options.inventory.site(device.id)
        options.audit('live_view', actor.source, device.id)
        return { id = device.id, displayId = OSSecurity.Brand.DevicePrefix .. ' · ' .. device.id, model = device.model,
            site = site and options.sites and options.sites.label(site) or nil,
            position = util.copy(feed.installation.position), rotation = util.copy(feed.installation.rotation), normal = feed.normal,
            noise = feed.noise, cameras = cameras, index = index }
    end
    -- Tablet Client: puertas con cerradura de las propiedades y negocios del personaje activo.
    function service.doors(actor)
        if not options.locks or not options.locks.owned then return { items = {} } end
        return { items = options.locks.owned(actor.source) }
    end
    -- Tablet Client: vehiculos del personaje con cierre o alarma G6, y su posicion si estan en el mundo.
    function service.trackers(actor)
        if not options.cars or not options.cars.owned then return { items = {} } end
        return { items = options.cars.owned(actor.source) }
    end
    -- Tablet Client: ultimos sucesos de todas sus alarmas, del mas reciente al mas antiguo.
    function service.incidents(actor)
        if not options.alarms then return { items = {} } end
        local devices, err = accessibleDevices(actor, function(device) return device.type == 'alarm_panel' end)
        if not devices then return nil, err end
        local items = {}
        for _, device in ipairs(devices) do
            local site = options.inventory.site(device.id)
            local siteLabel = site and (options.sites and options.sites.label(site) or OSSecurity.Sites.Labels[site.kind] .. ' ' .. site.id) or nil
            for _, event in ipairs(options.alarms.summary(device).events or {}) do
                items[#items + 1] = { at = event.at, kind = event.kind, by = event.by, deviceId = device.id,
                    device = OSSecurity.Brand.DevicePrefix .. ' · ' .. device.id, site = siteLabel }
            end
        end
        table.sort(items, function(a, b) if a.at ~= b.at then return a.at > b.at end; return a.deviceId < b.deviceId end)
        while #items > 40 do items[#items] = nil end
        return { items = items }
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
    -- Alarma desde la tablet: armar, armar parcial, desarmar, codigo, chapa y revocar chapas.
    function service.alarm(actor, args)
        if not util.object(args, { deviceId = true, action = true, pin = true }) or not options.alarms then return nil, 'Operacion no valida.' end
        local device, err = service.device(actor, args.deviceId)
        if not device then return nil, err end
        local result, reason
        if args.action == 'pin' then result, reason = options.alarms.setPin(actor, device, args.pin)
        elseif args.action == 'tag' then result, reason = options.alarms.programTag(actor, device)
        elseif args.action == 'revoke' then result, reason = options.alarms.revokeTags(actor, device)
        else result, reason = options.alarms.remote(actor, device, args.action) end
        if not result then return nil, reason end
        local updated = summary(actor, device)
        updated.notice = result.message
        return updated
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
