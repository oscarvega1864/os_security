local view, placement, props = OSSecurity.ClientView.new(), OSSecurity.ClientPlacement.new(), OSSecurity.ClientProps.new()
local lastUiAlive = GetGameTimer()
local minigameFx = OSSecurity.MinigameFx.new()
local minigame = OSSecurity.ClientMinigame.new({
    send = SendNUIMessage,
    focus = function(value) SetNuiFocus(value, value) end,
    timeout = function(callback) SetTimeout(120000, callback) end,
    animate = function(value) if value then minigameFx.start() else minigameFx.stop() end end
})
local controller = OSSecurity.ClientTablet.new({
    minigame = minigame.run,
    show = function(session) lastUiAlive = GetGameTimer(); view.show(session) end,
    hide = view.hide, cancelPlacement = placement.cancel, beginPlacement = placement.begin, props = props.sync,
    send = function(packet) TriggerServerEvent('os_security:g6:request', packet) end,
    timeout = function(callback) SetTimeout(8000, callback) end,
    expiry = function(expires) SendNUIMessage({ type = 'expiry', expires = expires }) end,
    notify = function(message, kind) OSSecurity.Notify(message or OSSecurity.Brand.Text.failed, kind) end
})

RegisterNetEvent('os_security:g6:response', function(id, response)
    if source ~= 65535 then return end
    controller.response(id, response)
end)

-- Apertura pedida por el servidor al "Usar" la tablet en el inventario externo; la sesion se autoriza de nuevo.
RegisterNetEvent('os_security:g6:openTablet', function(kind)
    if source ~= 65535 or (kind ~= 'client' and kind ~= 'operations') then return end
    controller.open(kind)
end)

-- "Usar" el kit CCTV en el inventario externo: inicia la colocacion si el servidor la autoriza.
RegisterNetEvent('os_security:g6:useItem', function(item)
    if source ~= 65535 or item ~= 'os_cctv_kit' then return end
    controller.useItem(item)
end)

-- /g6anchor: editor de zona de montaje (client/anchor.lua); el servidor revalida todo.
RegisterCommand('g6anchor', function(_, args)
    if controller.placing then return end
    OSSecurity.ClientAnchor.begin(args, function(payload) TriggerServerEvent('os_security:g6:anchorAim', payload) end, OSSecurity.Notify)
end, false)

RegisterNetEvent('os_security:g6:anchorResult', function(ok, message)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or 'error')
end)

RegisterCommand('g6inventory', function() controller.open('inventory') end, false)
RegisterCommand('g6client', function() controller.open('client') end, false)
RegisterCommand('g6operations', function() controller.open('operations') end, false)

RegisterNUICallback('minigame', function(body, callback) minigame.finish(body); callback({ ok = true }) end)
-- Efectos por fase (herramienta, animacion y sonidos); solo visuales y solo durante el minijuego.
RegisterNUICallback('minigameFx', function(body, callback)
    callback({ ok = true })
    if not minigame.active() or type(body) ~= 'table' then return end
    if type(body.phase) == 'string' then minigameFx.phase(body.phase) end
    if type(body.drilling) == 'boolean' then minigameFx.drilling(body.drilling) end
    if type(body.cue) == 'string' then minigameFx.cue(body.cue) end
end)
RegisterNUICallback('close', function(_, callback) controller.close(); callback({ ok = true }) end)
RegisterNUICallback('alive', function(body, callback)
    lastUiAlive = GetGameTimer()
    if controller.visible and type(body) == 'table' and body.visible == false then controller.close() end
    callback({ ok = true })
end)
RegisterNUICallback('request', function(body, callback)
    if type(body) ~= 'table' or type(body.action) ~= 'string' or type(body.args) ~= 'table' then callback({ ok = false }); return end
    if body.action == 'use' then controller.use(body.args.item, callback)
    elseif body.action == 'place_begin' then controller.place(callback)
    elseif ({ inventory = true, devices = true, device = true, maintain = true })[body.action] then controller.request(body.action, body.args, callback)
    else callback({ ok = false, error = OSSecurity.Brand.Text.unavailable }) end
end)

CreateThread(function()
    local lastHeartbeat = GetGameTimer()
    while true do
        Wait(1000)
        if (controller.visible or controller.placing) and IsEntityDead(PlayerPedId()) then minigame.cancel(); controller.close() end
        if controller.visible then
            if GetGameTimer() - lastUiAlive > 12000 then controller.close()
            else SendNUIMessage({ type = 'ping' }) end
        end
        if GetGameTimer() - lastHeartbeat >= 30000 then lastHeartbeat = GetGameTimer(); controller.heartbeat() end
    end
end)
CreateThread(function()
    while true do Wait(5000); if NetworkIsPlayerActive(PlayerId()) then controller.stream() else props.clear() end end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    minigame.cancel(); controller.stop(); placement.cancel(); props.clear(); view.hide()
end)
