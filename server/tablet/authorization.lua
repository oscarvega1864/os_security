OSSecurity.TabletAuthorization = {}

function OSSecurity.TabletAuthorization.new(options)
    local auth = {}
    local config = OSSecurity.GameplayConfig
    function auth.profile(source, kind)
        local principal, err = options.identity.resolve(source)
        if not principal then return nil, err end
        if not options.inventory.status() then return nil, 'Inventario no disponible.' end
        -- Con proveedor externo, los objetos pertenecen al personaje activo (holder) de esta sesion.
        local holder
        if options.holdings.external() then
            local resolved, holderError = options.holdings.holder(source)
            if not resolved then return nil, holderError end
            holder = resolved
        end
        if kind == 'inventory' then return { principal = principal, holder = holder, role = 'inventory', kind = kind } end
        local tablet = OSSecurity.Brand.Tablets[kind]
        if not tablet or not options.holdings.has({ principal = principal, holder = holder }, tablet.item, 1) then return nil, 'No posee la tablet correspondiente.' end
        local jobRole = kind == 'operations' and options.employment and options.employment(source, holder) or nil
        if not options.ace(source, config.Ace[kind]) and not jobRole then return nil, 'Tablet no autorizada para este perfil.' end
        if kind == 'client' then return { principal = principal, holder = holder, role = 'client', kind = kind } end
        local role
        if options.ace(source, config.Ace.admin) then role = 'admin'
        elseif options.ace(source, config.Ace.supervisor) then role = 'supervisor'
        elseif options.ace(source, config.Ace.technician) then role = 'technician'
        else role = jobRole end
        if not role then return nil, 'No tiene un perfil profesional verificable.' end
        return { principal = principal, holder = holder, role = role, kind = kind }
    end

    function auth.access(actor, device, action)
        if not actor or not OSSecurity.GameplayConfig.Profiles[actor.role]
            or not OSSecurity.GameplayConfig.Profiles[actor.role][action] then return false end
        if actor.kind == 'operations' and actor.role == 'admin' then return true end
        local account = options.inventory.get(actor.principal)
        if not account then return false end
        local grant = account.grants[device.id]
        if device.owner == actor.principal then return true end
        if action == 'view' then return grant ~= nil end
        return (grant == 'technician' and ({ inspect = true, repair = true, replace = true, provision = true })[action] == true)
            or (grant == 'supervisor' and ({ inspect = true, beginMaintenance = true })[action] == true)
    end
    return auth
end
