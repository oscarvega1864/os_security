-- Contratos de seguridad Gruppe Sechs.
-- Cliente (G6 Client > Contratos): contrata un plan para una de sus propiedades o negocios; paga la cuota al
-- contratar y despues cada periodo desde su banco (cuando esta conectado). Puede darlo de baja.
-- Ventajas mientras esta activo: sus avisos salen primero en la central (planes con prioridad) y las ordenes de
-- trabajo de esa propiedad llevan descuento. Personal G6 (G6 Operations > Contratos): ve la cartera.
-- Todo se valida aqui; la identidad, el dinero y las propiedades llegan por 'options'.
local util = OSSecurity.Util
OSSecurity.ContractService = {}

function OSSecurity.ContractService.new(options)
    local config = OSSecurity.GameplayConfig.Contracts
    local T = OSSecurity.Brand.Text.contracts
    local service = {}

    local function all() return options.inventory.contracts() or {} end
    local function save(contract)
        contract.updatedAt = options.now()
        return options.inventory.apply({ kind = 'contract', contractId = contract.id, contract = contract })
    end
    local function clean(text, size)
        if type(text) ~= 'string' then return nil end
        text = text:gsub('[%c<>]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, size)
        return text ~= '' and text or nil
    end
    local function name(source) return clean(options.playerName and options.playerName(source), 64) or ('Jugador ' .. tostring(source)) end
    local function nextId(list)
        local highest = 0
        for id in pairs(list) do highest = math.max(highest, tonumber(id:sub(4)) or 0) end
        return ('ct_%06d'):format(highest + 1)
    end
    local function sourceOf(principal)
        for _, player in ipairs(options.players and options.players() or {}) do
            if options.identity.resolve(player) == principal then return player end
        end
    end
    local function notify(source, text, kind) if source and options.notify then options.notify(source, text, kind or 'info') end end
    local function siteKey(site) return type(site) == 'table' and ('%s:%s'):format(site.kind, tostring(site.id)) or nil end
    local function planLabel(plan) return T.plans[plan] and T.plans[plan].name or plan end
    -- Propiedades y negocios del personaje activo.
    local function ownedSites(source)
        local alias = options.alias and options.alias(source)
        local result = {}
        if not alias or not options.sites or not options.sites.owned then return result end
        for _, site in ipairs(options.sites.owned()) do
            if site.owner == alias then
                result[#result + 1] = { value = ('site:%s:%d'):format(site.kind, site.id), label = options.sites.label({ kind = site.kind, id = site.id }),
                    site = { kind = site.kind, id = site.id }, position = util.copy(site.position) }
            end
        end
        return result
    end
    local function public(contract)
        local plan = config.Plans[contract.plan]
        return { id = contract.id, plan = contract.plan, planName = planLabel(contract.plan), fee = contract.fee, status = contract.status,
            place = contract.place, clientName = contract.clientName, nextCharge = contract.nextCharge, paidTotal = contract.paidTotal,
            failures = contract.failures, createdAt = contract.createdAt, priority = plan.priority == true, discount = plan.discount,
            position = util.copy(contract.position), rounds = options.rounds and options.rounds(contract.client, contract.site) or nil }
    end
    local function sorted(list, accept)
        local result = {}
        for _, contract in pairs(list) do if accept(contract) then result[#result + 1] = public(contract) end end
        local order = { active = 1, suspended = 2, cancelled = 3 }
        table.sort(result, function(a, b)
            if a.status ~= b.status then return order[a.status] < order[b.status] end
            return a.id > b.id
        end)
        return result
    end
    local function plans()
        local list = {}
        for _, id in ipairs(config.PlanOrder) do
            local plan, text = config.Plans[id], T.plans[id] or {}
            list[#list + 1] = { value = id, name = text.name or id, description = text.description, fee = plan.fee,
                priority = plan.priority == true, discount = plan.discount }
        end
        return list
    end
    -- Limpieza: cancelados mas antiguos que KeepDays.
    local function prune(list)
        local limit = options.now() - config.KeepDays * 86400
        for id, contract in pairs(list) do
            if contract.status == 'cancelled' and contract.updatedAt < limit then
                if options.inventory.apply({ kind = 'contract', contractId = id }) then list[id] = nil end
            end
        end
    end

    -- Ventajas ------------------------------------------------------------------------------------------
    -- Contrato activo de ese cliente para esa propiedad (site = { kind, id }), o el mejor de todos si no hay site.
    function service.coverage(principal, site)
        local key, best = siteKey(site), nil
        for _, contract in pairs(all()) do
            if contract.client == principal and contract.status == 'active' and (not key or siteKey(contract.site) == key) then
                local plan = config.Plans[contract.plan]
                if not best or plan.discount > best.discount or (plan.priority and not best.priority) then
                    best = { id = contract.id, plan = contract.plan, priority = plan.priority == true, discount = plan.discount }
                end
            end
        end
        return best
    end

    -- Cliente -------------------------------------------------------------------------------------------
    function service.clientList(actor)
        local list = all()
        local items = sorted(list, function(contract) return contract.client == actor.principal end)
        local taken = {}
        for _, contract in pairs(list) do
            if contract.client == actor.principal and contract.status ~= 'cancelled' then taken[siteKey(contract.site)] = true end
        end
        local places = {}
        for _, owned in ipairs(ownedSites(actor.source)) do
            if not taken[siteKey(owned.site)] then places[#places + 1] = { value = owned.value, label = owned.label } end
        end
        return { items = items, plans = plans(), places = places, period = config.PeriodSeconds }
    end
    function service.create(actor, args)
        if not util.object(args, { place = true, plan = true }) or type(args.place) ~= 'string' or type(args.plan) ~= 'string'
            or not config.Plans[args.plan] then return nil, T.choosePlan end
        local chosen
        for _, owned in ipairs(ownedSites(actor.source)) do if owned.value == args.place then chosen = owned end end
        if not chosen then return nil, T.notYours end
        local list = all()
        for _, contract in pairs(list) do
            if contract.client == actor.principal and contract.status ~= 'cancelled' and siteKey(contract.site) == siteKey(chosen.site) then
                return nil, T.already
            end
        end
        prune(list)
        if not options.money.available() then return nil, T.noPayments end
        local plan = config.Plans[args.plan]
        local id, now = nextId(list), options.now()
        local reference = ('%s@%d:fee1'):format(id, now)
        local charged, why = options.money.charge(actor.source, plan.fee, config.PayAccount, reference)
        if not charged then return nil, why == 'insufficient_funds' and T.noFunds or T.payRejected end
        local contract = { id = id, client = actor.principal, clientName = name(actor.source), site = util.copy(chosen.site),
            place = clean(chosen.label, 80), position = { x = util.round(chosen.position.x, 2), y = util.round(chosen.position.y, 2), z = util.round(chosen.position.z, 2) },
            plan = args.plan, fee = plan.fee, status = 'active', failures = 0, nextCharge = now + config.PeriodSeconds,
            paidTotal = plan.fee, createdAt = now, updatedAt = now }
        local saved, err = save(contract)
        if not saved then
            options.money.refund(actor.source, plan.fee, config.PayAccount, reference)
            return nil, err
        end
        options.audit('contract_created', actor.source, id)
        return { id = id, message = T.created:format(planLabel(args.plan), contract.place or id, plan.fee) }
    end
    function service.cancel(actor, args)
        if not util.object(args, { contractId = true }) or not OSSecurity.InventoryState.contractId(args.contractId) then return nil, T.notFound end
        local contract = all()[args.contractId]
        if not contract or contract.client ~= actor.principal then return nil, T.notFound end
        if contract.status == 'cancelled' then return nil, T.alreadyCancelled end
        contract.status = 'cancelled'
        local saved, err = save(contract)
        if not saved then return nil, err end
        options.audit('contract_cancelled', actor.source, contract.id)
        return { message = T.cancelled:format(contract.place or contract.id) }
    end

    -- Personal G6 ---------------------------------------------------------------------------------------
    function service.staffList(actor)
        local items = sorted(all(), function() return true end)
        local summary = { active = 0, suspended = 0, income = 0 }
        for _, item in ipairs(items) do
            if item.status == 'active' then summary.active = summary.active + 1; summary.income = summary.income + item.fee
            elseif item.status == 'suspended' then summary.suspended = summary.suspended + 1 end
        end
        return { items = items, summary = summary, period = config.PeriodSeconds }
    end

    -- Cobro periodico: con el cliente conectado; si falla, suspendido y reintento; tras MaxFailures, cancelado.
    function service.tick()
        local now = options.now()
        if not options.money.available() then return end
        for _, contract in pairs(all()) do
            if contract.status ~= 'cancelled' and contract.nextCharge <= now then
                local player = sourceOf(contract.client)
                if player then
                    local reference = ('%s@%d:fee%d'):format(contract.id, contract.createdAt, contract.nextCharge)
                    local charged = options.money.charge(player, contract.fee, config.PayAccount, reference)
                    if charged then
                        contract.status, contract.failures = 'active', 0
                        contract.paidTotal = math.min(2000000000, contract.paidTotal + contract.fee)
                        contract.nextCharge = now + config.PeriodSeconds
                        if save(contract) then notify(player, T.charged:format(contract.fee, contract.place or contract.id), 'info') end
                    else
                        contract.failures = contract.failures + 1
                        contract.nextCharge = now + config.RetrySeconds
                        if contract.failures >= config.MaxFailures then
                            contract.status = 'cancelled'
                            if save(contract) then notify(player, T.cancelledUnpaid:format(contract.place or contract.id), 'error') end
                        else
                            contract.status = 'suspended'
                            if save(contract) then notify(player, T.suspended:format(contract.place or contract.id, contract.fee), 'warning') end
                        end
                    end
                end
            end
        end
    end
    return service
end
