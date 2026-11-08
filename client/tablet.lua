-- Controlador compartido por inventario, G6 Client y G6 Operations.
OSSecurity.ClientTablet = {}

function OSSecurity.ClientTablet.new(options)
    local session, pending, requestId, epoch = nil, nil, 0, 0
    local controller = { visible = false, placing = false }
    local function hide()
        controller.visible = false
        options.hide()
    end
    local function showSession(newSession)
        session = newSession
        local public = {}
        for key, value in pairs(session) do if key ~= 'token' and key ~= 'sequence' then public[key] = value end end
        controller.visible = true
        options.show(public)
    end
    function controller.request(action, args, callback)
        if pending then callback({ ok = false, error = OSSecurity.Brand.Text.loading }); return end
        requestId = requestId + 1
        local packet = { id = requestId, action = action, args = args or {} }
        if action ~= 'open' and action ~= 'stream' then
            if not session then callback({ ok = false, error = 'Sesion cerrada.', close = true }); return end
            session.sequence = session.sequence + 1
            packet.token, packet.sequence = session.token, session.sequence
        end
        pending = { id = requestId, callback = callback, epoch = epoch }
        options.send(packet)
        options.timeout(function()
            if pending and pending.id == packet.id then
                local waiting = pending; pending = nil; session = nil
                hide(); controller.placing = false; options.cancelPlacement()
                waiting.callback({ ok = false, error = 'El servidor no responde.', close = true })
            end
        end)
    end
    function controller.response(id, response)
        if not pending or id ~= pending.id then return end
        local waiting = pending; pending = nil
        if waiting.epoch ~= epoch then return end
        if type(response) ~= 'table' or type(response.ok) ~= 'boolean' then response = { ok = false, error = OSSecurity.Brand.Text.failed, close = true } end
        if response.close then session = nil; hide(); controller.placing = false; options.cancelPlacement() end
        if response.expires and session then session.expires = response.expires; options.expiry(response.expires) end
        waiting.callback(response)
    end
    local function opened(response)
        if not response.ok then options.notify(response.error, 'error'); return end
        if response.session then
            local candidate = response.session
            if type(candidate) ~= 'table' or type(candidate.token) ~= 'string' or type(candidate.sequence) ~= 'number'
                or type(candidate.brand) ~= 'table' or not ({ inventory = true, client = true, operations = true })[candidate.kind] then
                controller.close(); options.notify(OSSecurity.Brand.Text.failed, 'error'); return
            end
            session = candidate
        end
        if response.placement then
            hide(); controller.placing = true
            options.beginPlacement(response.placement, function(proposal)
                controller.request(proposal and 'place_confirm' or 'place_cancel', proposal or {}, function(result)
                    controller.placing = false; options.cancelPlacement()
                    options.notify(result.ok and (result.data and result.data.id and ('CCTV registrado: ' .. result.data.id) or 'Colocacion cancelada.') or result.error,
                        result.ok and (result.data and result.data.id and 'success' or 'info') or 'error')
                    if result.ok then controller.stream() end
                end)
            end)
        elseif session then showSession(session) end
    end
    function controller.open(kind)
        if pending then options.notify(OSSecurity.Brand.Text.loading, 'warning'); return end
        epoch = epoch + 1; hide(); controller.placing = false; options.cancelPlacement()
        controller.request('open', { kind = kind }, opened)
    end
    function controller.use(item, callback)
        if pending then callback({ ok = false, error = OSSecurity.Brand.Text.loading }); return end
        hide()
        controller.request('use', { item = item }, function(response)
            callback({ ok = response.ok, error = response.error, close = response.close }); opened(response)
        end)
    end
    -- "Usar" desde un inventario externo: sesion de inventario sin mostrarla y despues 'use' del objeto,
    -- con la misma autorizacion del servidor que el boton de la tablet. Un rechazo cierra esa sesion.
    function controller.useItem(item)
        if pending then options.notify(OSSecurity.Brand.Text.loading, 'warning'); return end
        epoch = epoch + 1; hide(); controller.placing = false; options.cancelPlacement()
        controller.request('open', { kind = 'inventory' }, function(response)
            if not response.ok then options.notify(response.error, 'error'); return end
            local candidate = response.session
            if type(candidate) ~= 'table' or type(candidate.token) ~= 'string' or type(candidate.sequence) ~= 'number' then
                options.notify(OSSecurity.Brand.Text.failed, 'error'); return
            end
            session = candidate
            controller.request('use', { item = item }, function(result)
                if not result.ok then controller.close(); options.notify(result.error, 'error'); return end
                opened(result)
            end)
        end)
    end
    function controller.place(callback)
        controller.request('place_begin', {}, function(response)
            callback({ ok = response.ok, error = response.error, close = response.close })
            if response.ok then opened(response) end
        end)
    end
    function controller.close()
        local current = session
        hide(); controller.placing = false; options.cancelPlacement()
        if pending then
            local waiting = pending; pending = nil
            waiting.callback({ ok = false, error = 'Sesion cerrada.', close = true })
        end
        if current and not pending then controller.request('close', {}, function() end) end
        session = nil; epoch = epoch + 1
    end
    function controller.stream()
        if pending or controller.placing then return end
        controller.request('stream', {}, function(response)
            options.props(response.ok and response.props or {})
        end)
    end
    function controller.heartbeat()
        if controller.visible and not pending then
            controller.request('inventory', {}, function(response)
                if not response.ok then controller.close(); options.notify(response.error, 'error') end
            end)
        end
    end
    function controller.stop()
        epoch = epoch + 1; hide(); controller.placing = false; options.cancelPlacement(); session = nil
        if pending then local waiting = pending; pending = nil; waiting.callback({ ok = false, error = 'Recurso detenido.', close = true }) end
    end
    return controller
end
