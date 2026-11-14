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
                local placement, placementError = options.placement.begin(source, opened, request.args.item)
                if not placement then options.sessions.close(source); return failure(placementError, true) end
                return { ok = true, session = options.service.session(opened), placement = placement }
            else return failure('Este articulo no tiene una funcion implementada.') end
        elseif actor.kind ~= 'inventory' and request.action == 'home' and next(request.args) == nil and options.home then
            result, reason = options.home.summary(actor)
        elseif actor.kind ~= 'inventory' and request.action == 'search' and options.home then
            result, reason = options.home.search(actor, request.args)
        elseif actor.kind ~= 'inventory' and request.action == 'devices' then
            result, reason = options.service.list(actor, request.args)
        elseif actor.kind ~= 'inventory' and request.action == 'device' then
            result, reason = options.service.get(actor, request.args)
        elseif actor.kind ~= 'inventory' and request.action == 'alarm' then
            result, reason = options.service.alarm(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'maintain' then
            result, reason = options.service.maintain(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'place_begin' and next(request.args) == nil then
            result, reason = options.placement.begin(source, session)
            if result then return { ok = true, placement = result } end
        elseif actor.kind ~= 'inventory' and request.action == 'live' and util.object(request.args, { deviceId = true }) then
            result, reason = options.service.live(actor, request.args)
        elseif actor.kind == 'client' and request.action == 'requests' and next(request.args) == nil then
            result, reason = options.orders.clientList(actor)
        elseif actor.kind == 'client' and request.action == 'request_create' then
            result, reason = options.orders.create(actor, request.args)
        elseif actor.kind == 'client' and request.action == 'request_cancel' then
            result, reason = options.orders.cancel(actor, request.args)
        elseif actor.kind == 'client' and request.action == 'request_pay' then
            result, reason = options.orders.pay(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'orders' and next(request.args) == nil then
            result, reason = options.orders.staffList(actor)
        elseif actor.kind == 'operations' and request.action == 'order_accept' then
            result, reason = options.orders.accept(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'order_release' then
            result, reason = options.orders.release(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'order_bill' then
            result, reason = options.orders.bill(actor, request.args)
        elseif actor.kind == 'client' and request.action == 'emergencies' and next(request.args) == nil then
            result, reason = options.dispatch.clientList(actor)
        elseif actor.kind == 'client' and request.action == 'panic' then
            result, reason = options.dispatch.panic(actor, request.args)
        elseif actor.kind == 'client' and request.action == 'panic_cancel' then
            result, reason = options.dispatch.cancel(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'dispatch' and next(request.args) == nil then
            result, reason = options.dispatch.staffList(actor)
        elseif actor.kind == 'operations' and request.action == 'call_take' then
            result, reason = options.dispatch.take(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'call_assign' then
            result, reason = options.dispatch.assign(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'call_release' then
            result, reason = options.dispatch.release(actor, request.args)
        elseif actor.kind == 'operations' and request.action == 'call_resolve' then
            result, reason = options.dispatch.resolve(actor, request.args)
        elseif actor.kind == 'client' and request.action == 'doors' and next(request.args) == nil then
            result, reason = options.service.doors(actor)
        elseif actor.kind == 'client' and request.action == 'trackers' and next(request.args) == nil then
            result, reason = options.service.trackers(actor)
        elseif actor.kind == 'client' and request.action == 'incidents' and next(request.args) == nil then
            result, reason = options.service.incidents(actor)
        elseif actor.kind == 'operations' and request.action == 'zones' and next(request.args) == nil then
            result, reason = options.zones.list(source, session)
        elseif actor.kind == 'operations' and request.action == 'zone_begin' and util.object(request.args, { client = true }) then
            result, reason = options.zones.begin(source, session, request.args.client)
            -- La tablet se cierra para marcar con el visor; la sesion termina aqui.
            if result then options.sessions.close(source); options.placement.cancel(source); return { ok = true, data = result } end
        elseif actor.kind == 'operations' and request.action == 'zone_delete' and util.object(request.args, { anchorId = true }) then
            result, reason = options.zones.delete(source, session, request.args.anchorId)
        elseif actor.kind == 'operations' and request.action == 'zone_install' and util.object(request.args, { anchorId = true, kit = true }) then
            local kit = request.args.kit
            if type(kit) ~= 'string' or not OSSecurity.GameplayConfig.Products[kit] or type(request.args.anchorId) ~= 'string' then return failure('Kit o zona no validos.') end
            if not options.holdings.has(actor, kit, 1) then return failure('No tienes ese kit.') end
            result, reason = options.placement.begin(source, session, kit, request.args.anchorId)
            if result then return { ok = true, placement = result } end
        elseif actor.kind == 'operations' and request.action == 'place_confirm' then
            result, reason = options.placement.confirm(source, session, request.args)
        elseif actor.kind ~= 'inventory' and request.action == 'remove_begin' and util.object(request.args, { deviceId = true }) then
            result, reason = options.placement.removeBegin(source, session, request.args.deviceId)
            if result then return { ok = true, removal = result, expires = session.expires } end
        elseif actor.kind ~= 'inventory' and request.action == 'remove_confirm' and util.object(request.args, { deviceId = true }) then
            result, reason = options.placement.removeConfirm(source, session, request.args.deviceId)
        elseif request.action == 'remove_cancel' and next(request.args) == nil then
            options.placement.removeCancel(source); result = { cancelled = true }
        elseif request.action == 'place_cancel' and next(request.args) == nil then
            options.placement.cancel(source); result = { cancelled = true }
        else return failure('Accion no disponible para esta sesion.') end
        options.audit(result and 'access_allowed' or 'access_denied', source, request.args.deviceId)
        if not result then return failure(reason) end
        return { ok = true, data = result, expires = session.expires }
    end
    function controller.drop(source) options.sessions.drop(source); options.placement.cancel(source); if options.zones then options.zones.cancel(source) end end
    function controller.clear() options.sessions.clear(); options.placement.clear(); if options.zones then options.zones.clear() end end
    return controller
end
