local view, placement, props = OSSecurity.ClientView.new(), OSSecurity.ClientPlacement.new(), OSSecurity.ClientProps.new()
local alarms = OSSecurity.ClientAlarms.new()
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
    hide = view.hide, cancelPlacement = placement.cancel, beginPlacement = placement.begin, props = function(list) props.sync(list); alarms.sync(list) end,
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
    local definition = OSSecurity.ItemCatalog[item]
    if source ~= 65535 or not definition or definition.usable ~= 'placement' then return end
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
    elseif ({ inventory = true, devices = true, device = true, maintain = true, alarm = true })[body.action] then controller.request(body.action, body.args, callback)
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

-- Alarmas: teclado junto al dispositivo, aviso de entrada, sirena y avisos.
RegisterNetEvent('os_security:alarm:panelData', function(data, err) if source == 65535 then alarms.show(data, err) end end)
RegisterNetEvent('os_security:alarm:result', function(result, err, panel) if source == 65535 then alarms.result(result, err, panel) end end)
RegisterNetEvent('os_security:alarm:entry', function(_, seconds) if source == 65535 and type(seconds) == 'number' then alarms.entry(seconds) end end)
RegisterNetEvent('os_security:alarm:siren', function(deviceId, position, name, set) if source == 65535 then alarms.siren(deviceId, position, name, set) end end)
RegisterNetEvent('os_security:alarm:alert', function(text, kind, position) if source == 65535 and type(text) == 'string' then alarms.alert(text, kind, position) end end)
RegisterNUICallback('pinpad', function(body, callback)
    callback({ ok = true })
    if not alarms.open or type(body) ~= 'table' then return end
    if body.action == 'tag' then TriggerServerEvent('os_security:alarm:tag', alarms.open)
    elseif ({ arm = true, partial = true, disarm = true })[body.action] then TriggerServerEvent('os_security:alarm:keypad', alarms.open, body.action, type(body.pin) == 'string' and body.pin or '') end
end)
RegisterNUICallback('pinpadKey', function(_, callback) callback({ ok = true }); PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end)
RegisterNUICallback('pinpadClose', function(_, callback) callback({ ok = true }); alarms.close() end)
CreateThread(function()
    while true do
        local sleep = 500
        if not alarms.open and not controller.visible and not controller.placing then
            local ped = PlayerPedId()
            local keypad = not IsPedInAnyVehicle(ped, false) and alarms.nearest(GetEntityCoords(ped), 1.6)
            if keypad then
                sleep = 0
                BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(OSSecurity.Brand.Text.alarm.keypadHint); EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustPressed(0, 38) then TriggerServerEvent('os_security:alarm:panel', keypad.id) end
            end
        end
        Wait(sleep)
    end
end)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then alarms.clear() end end)
