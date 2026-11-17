-- Rondas de vigilancia Gruppe Sechs.
-- Supervisor o administrador (G6 Operations > Rondas): crea una ruta (opcionalmente para la propiedad de un cliente
-- con contrato) y le anade puntos de control donde esta en ese momento. Cualquier perfil de Operations la recorre:
-- empieza la ronda y ficha en cada punto, en orden; el servidor comprueba que esta junto al punto. Al terminar se
-- guarda en el registro de la ruta (ultimas MaxLogs) y el cliente de esa propiedad lo ve en su contrato.
-- Las rondas en curso viven en memoria: desconectarse o reiniciar las abandona sin registrar nada.
local util = OSSecurity.Util
OSSecurity.PatrolService = {}

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

function OSSecurity.PatrolService.new(options)
    local config = OSSecurity.GameplayConfig.Patrols
    local T = OSSecurity.Brand.Text.patrols
    local service = {}
    local runs = {} -- vigilante -> { routeId, next, startedAt }

    local function all() return options.inventory.patrols() or {} end
    local function save(route)
        route.updatedAt = options.now()
        return options.inventory.apply({ kind = 'patrol', patrolId = route.id, patrol = route })
    end
    local clean = util.clean
    local function name(source) return clean(options.playerName and options.playerName(source), 64) or ('Jugador ' .. tostring(source)) end
    local function nextId(list) return util.nextId(list, 'rd') end
    local function canManage(actor) return actor.kind == 'operations' and (actor.role == 'supervisor' or actor.role == 'admin') end
    local function route(id) return OSSecurity.InventoryState.patrolId(id) and all()[id] or nil end
    local function point(position) return { x = util.round(position.x, 2), y = util.round(position.y, 2), z = util.round(position.z, 2) } end
    local function public(entry, viewer)
        local last = entry.logs[#entry.logs]
        local run = viewer and runs[viewer]
        return { id = entry.id, name = entry.name, place = entry.place, points = #entry.points, rounds = #entry.logs,
            last = last and { guardName = last.guardName, finishedAt = last.finishedAt, minutes = math.max(1, math.floor((last.finishedAt - last.startedAt) / 60 + 0.5)) } or nil,
            running = run and run.routeId == entry.id and { next = run.next, total = #entry.points } or nil }
    end
    local function sendRun(source)
        local run = runs[source]
        local entry = run and all()[run.routeId]
        if not run or not entry then options.send(source, 'patrolRun', false); return end
        options.send(source, 'patrolRun', { name = entry.name, next = run.next, total = #entry.points, point = util.copy(entry.points[run.next]) })
    end

    function service.staffList(actor)
        local items = {}
        for _, entry in pairs(all()) do items[#items + 1] = public(entry, actor.source) end
        table.sort(items, function(a, b) return a.id < b.id end)
        local sites = {}
        if canManage(actor) and options.contracts then
            for _, contract in ipairs(options.contracts.staffList(actor).items) do
                if contract.status ~= 'cancelled' then sites[#sites + 1] = { value = contract.id, label = contract.place or contract.id } end
            end
        end
        return { items = items, canManage = canManage(actor), sites = sites, maxPoints = config.MaxPoints, nameLength = config.NameLength }
    end
    -- Ruta nueva: nombre y, opcionalmente, el contrato de la propiedad que vigila.
    function service.create(actor, args)
        if not canManage(actor) then return nil, T.noAccess end
        if not util.object(args, { name = true, contractId = true }) then return nil, T.invalid end
        local title = clean(args.name, config.NameLength)
        if not title then return nil, T.needName end
        local list = all()
        local entry = { id = nextId(list), name = title, points = {}, logs = {}, createdBy = actor.principal, createdAt = options.now(), updatedAt = options.now() }
        if args.contractId ~= nil then
            local contract = options.contracts and OSSecurity.InventoryState.contractId(args.contractId) and options.inventory.contracts()[args.contractId]
            if not contract or contract.status == 'cancelled' then return nil, T.noContract end
            entry.site, entry.place, entry.owner = util.copy(contract.site), contract.place, contract.client
        end
        local saved, err = save(entry)
        if not saved then return nil, err end
        options.audit('patrol_created', actor.source, entry.id)
        return { id = entry.id, message = T.created:format(title) }
    end
    -- Punto de control donde esta el supervisor ahora (posicion del servidor).
    function service.addPoint(actor, args)
        if not canManage(actor) then return nil, T.noAccess end
        if not util.object(args, { routeId = true }) then return nil, T.invalid end
        local entry = route(args.routeId)
        if not entry then return nil, T.notFound end
        if #entry.points >= config.MaxPoints then return nil, T.full:format(config.MaxPoints) end
        local here = options.world(actor.source)
        if not here then return nil, T.noPosition end
        for _, existing in ipairs(entry.points) do
            if distance(existing, here) < config.MinPointGap then return nil, T.tooClose:format(config.MinPointGap) end
        end
        entry.points[#entry.points + 1] = point(here)
        local saved, err = save(entry)
        if not saved then return nil, err end
        return { message = T.pointAdded:format(#entry.points, entry.name) }
    end
    function service.delete(actor, args)
        if not canManage(actor) then return nil, T.noAccess end
        if not util.object(args, { routeId = true }) then return nil, T.invalid end
        local entry = route(args.routeId)
        if not entry then return nil, T.notFound end
        for guard, run in pairs(runs) do if run.routeId == entry.id then runs[guard] = nil; options.send(guard, 'patrolRun', false) end end
        local saved, err = options.inventory.apply({ kind = 'patrol', patrolId = entry.id })
        if not saved then return nil, err end
        options.audit('patrol_deleted', actor.source, entry.id)
        return { message = T.deleted:format(entry.name) }
    end
    -- Recorrer una ruta.
    function service.start(actor, args)
        if actor.kind ~= 'operations' then return nil, T.noAccess end
        if not util.object(args, { routeId = true }) then return nil, T.invalid end
        local entry = route(args.routeId)
        if not entry then return nil, T.notFound end
        if #entry.points < 2 then return nil, T.needPoints end
        runs[actor.source] = { routeId = entry.id, next = 1, startedAt = options.now() }
        sendRun(actor.source)
        return { message = T.started:format(entry.name, #entry.points) }
    end
    function service.cancel(source)
        if not runs[source] then return nil, T.noRun end
        runs[source] = nil
        options.send(source, 'patrolRun', false)
        return { message = T.abandoned }
    end
    -- Fichar en el siguiente punto: el servidor comprueba la distancia con su propia posicion del jugador.
    function service.check(source)
        local run = runs[source]
        if not run then return nil, T.noRun end
        local entry = all()[run.routeId]
        if not entry then runs[source] = nil; return nil, T.notFound end
        if options.now() - run.startedAt > config.MaxRoundSeconds then runs[source] = nil; options.send(source, 'patrolRun', false); return nil, T.expired end
        local here = options.world(source)
        local target = entry.points[run.next]
        if not here or not target or distance(here, target) > config.CheckDistance then return nil, T.tooFar end
        if run.next < #entry.points then
            run.next = run.next + 1
            sendRun(source)
            return { message = T.checked:format(run.next - 1, #entry.points) }
        end
        runs[source] = nil
        options.send(source, 'patrolRun', false)
        entry.logs[#entry.logs + 1] = { guardName = name(source), startedAt = run.startedAt, finishedAt = options.now() }
        while #entry.logs > config.MaxLogs do table.remove(entry.logs, 1) end
        local saved, err = save(entry)
        if not saved then return nil, err end
        options.audit('patrol_done', source, entry.id)
        return { message = T.finished:format(entry.name), done = true }
    end
    -- Para el contrato del cliente: rondas hechas en esa propiedad (las rutas con ese titular y propiedad).
    function service.forSite(principal, site)
        local count, last = 0, nil
        for _, entry in pairs(all()) do
            if entry.owner == principal and entry.site and site and entry.site.kind == site.kind and entry.site.id == site.id then
                for _, log in ipairs(entry.logs) do
                    count = count + 1
                    if not last or log.finishedAt > last.finishedAt then last = { finishedAt = log.finishedAt, guardName = log.guardName, route = entry.name } end
                end
            end
        end
        return count > 0 and { count = count, last = last } or nil
    end
    function service.forget(source) runs[source] = nil end
    return service
end
