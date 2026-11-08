local util = OSSecurity.Util
OSSecurity.TabletController = {}

function OSSecurity.TabletController.new(options)
    local controller = {}
    local function failure(err, close)
        return { ok = false, error = err or 'Solicitud no disponible.', close = close == true }
    end
    function controller.handle(source, request)
        if not util.object(request, { id = true, action = true, token = true, sequence = true, args = true })
            or not util.integer(request.id, 1, 2147483647) or not util.text(request.action, 32)
            or not util.object(request.args) then return failure('Solicitud no valida.') end
        if request.action == 'open' then
            if not options.sessions.rate(source, false) or not util.object(request.args, { kind = true })
                or not ({ inventory = true, client = true, operations = true })[request.args.kind] then return failure('Apertura no valida.') end
            options.placement.cancel(source)
            local session, err = options.sessions.open(source, request.args.kind)
            if not session then return failure(err, true) end
            options.audit('session_open', source)
            return { ok = true, session = options.service.session(session) }
        end
        if request.action == 'stream' then
            if not options.sessions.rate(source, false) or not options.identity.resolve(source) or next(request.args) then return failure('Sin acceso al streaming de props.') end
            local props, err = options.placement.stream(source)
            return props and { ok = true, props = props } or failure(err)
        end
        local session, err = options.sessions.check(source, request.token, request.sequence)
        if not session then options.placement.cancel(source); return failure(err, true) end
        local actor, result, reason = session.actor
        if request.action == 'close' and next(request.args) == nil then
            options.sessions.close(source); options.placement.cancel(source)
            return { ok = true, closed = true }
        elseif request.action == 'inventory' and next(request.args) == nil then
            result, reason = options.service.inventory(actor)
        elseif request.action == 'use' and util.object(request.args, { item = true }) then
            local item = request.args.item
            local definition = type(item) == 'string' and OSSecurity.ItemCatalog[item]
            if not definition or not options.holdings.has(actor, item, 1) then return failure('No posee ese item.') end
            if definition.tablet then
                options.placement.cancel(source)
                local opened, openError = options.sessions.open(source, definition.tablet)
                if not opened then return failure(openError, true) end
                options.audit('tablet_use', source)
                return { ok = true, session = options.service.session(opened) }
            elseif definition.usable == 'placement' then
                local opened, openError = options.sessions.open(source, 'operations')
                if not opened then return failure(openError, true) end
                local placement, placementError = options.placement.begin(source, opened)
                if not placement then options.sessions.close(source); return failure(placementError, true) end
                return { ok = true, session = options.service.session(opened), placement = placement }
            else return failure('Este articulo no tiene una funcion implementada.') end
        elseif actor.kind ~= 'inventory' and request.action == 'devices' then
            result, reason = options.service.list(actor, request.args)
        elseif actor.kind ~= 'inventory' and request.action == 'device' then
            result, reason = options.service.get(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'maintain' then
            result, reason = options.service.maintain(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'place_begin' and next(request.args) == nil then
            result, reason = options.placement.begin(source, session)
            if result then return { ok = true, placement = result } end
        elseif actor.kind == 'operations' and request.action == 'place_confirm' then
            result, reason = options.placement.confirm(source, session, request.args)
        elseif request.action == 'place_cancel' and next(request.args) == nil then
            options.placement.cancel(source); result = { cancelled = true }
        else return failure('Accion no disponible para esta sesion.') end
        options.audit(result and 'access_allowed' or 'access_denied', source, request.args.deviceId)
        if not result then return failure(reason) end
        return { ok = true, data = result, expires = session.expires }
    end
    function controller.drop(source) options.sessions.drop(source); options.placement.cancel(source) end
    function controller.clear() options.sessions.clear(); options.placement.clear() end
    return controller
end
