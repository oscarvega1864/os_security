local view, placement, props = OSSecurity.ClientView.new(), OSSecurity.ClientPlacement.new(), OSSecurity.ClientProps.new()
local lastUiAlive = GetGameTimer()
local controller = OSSecurity.ClientTablet.new({
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

-- /g6anchor <id> <idCliente> [idInstalador] [radio]: registra un montaje en el punto de la pared al que se apunta.
-- Solo propone punto y normal; el servidor exige ossecurity.admin y revalida distancia, identidades y datos.
RegisterCommand('g6anchor', function(_, args)
    local client, installer, radius = tonumber(args[2]), args[3] and tonumber(args[3]) or nil, args[4] and tonumber(args[4]) or nil
    if not args[1] or not client or (args[3] and not installer) or (args[4] and not radius) then
        OSSecurity.Notify('Uso: /g6anchor <id> <idCliente> [idInstalador] [radio], apuntando a la pared.', 'warning'); return
    end
    local camera, rotation = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw, distance = math.rad(rotation.x), math.rad(rotation.z), 8.0
    local horizontal = math.abs(math.cos(pitch))
    local handle = StartExpensiveSynchronousShapeTestLosProbe(camera.x, camera.y, camera.z,
        camera.x - math.sin(yaw) * horizontal * distance, camera.y + math.cos(yaw) * horizontal * distance,
        camera.z + math.sin(pitch) * distance, 1, PlayerPedId(), 7)
    local _, hit, point, normal = GetShapeTestResult(handle)
    if hit ~= 1 and hit ~= true then OSSecurity.Notify('Apunta a una pared o superficie a menos de 8 m.', 'warning'); return end
    TriggerServerEvent('os_security:g6:anchorAim', { id = args[1], client = math.floor(client),
        installer = installer and math.floor(installer) or nil, radius = radius,
        position = { x = point.x, y = point.y, z = point.z }, normal = { x = normal.x, y = normal.y, z = normal.z } })
end, false)

RegisterNetEvent('os_security:g6:anchorResult', function(ok, message)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or 'error')
end)

RegisterCommand('g6inventory', function() controller.open('inventory') end, false)
RegisterCommand('g6client', function() controller.open('client') end, false)
RegisterCommand('g6operations', function() controller.open('operations') end, false)

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
        if (controller.visible or controller.placing) and IsEntityDead(PlayerPedId()) then controller.close() end
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
    controller.stop(); placement.cancel(); props.clear(); view.hide()
end)
