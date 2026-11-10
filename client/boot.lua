local view, placement, props = OSSecurity.ClientView.new(), OSSecurity.ClientPlacement.new(), OSSecurity.ClientProps.new()
local alarms = OSSecurity.ClientAlarms.new()
local locks = OSSecurity.ClientLocks.new({ detectRadius = 15.0, scanRange = 25.0,
    report = function(report) TriggerServerEvent('os_security:locks:report', report) end })
local cylinderOpen = false
-- Generacion de cada minijuego con temporizador: un SetTimeout de una sesion anterior no cierra la nueva.
local sessions = { cylinder = 0, carwire = 0, hotwire = 0 }
local function session(name) sessions[name] = sessions[name] + 1; return sessions[name] end
local cars = OSSecurity.ClientCars.new({ notify = OSSecurity.Notify })
local carwireOpen = false
local lastUiAlive = GetGameTimer()
local minigameFx = OSSecurity.MinigameFx.new()
local minigame = OSSecurity.ClientMinigame.new({
    send = SendNUIMessage,
    focus = function(value) SetNuiFocus(value, value) end,
    timeout = function(callback) SetTimeout(120000, callback) end,
    animate = function(value) if value then minigameFx.start() else minigameFx.stop() end end
})
local liveView -- vista en directo de camaras (client/live.lua), creada tras el controlador
local controller = OSSecurity.ClientTablet.new({
    minigame = minigame.run,
    live = { start = function(feed) liveView.start(feed) end },
    show = function(session) lastUiAlive = GetGameTimer(); view.show(session) end,
    hide = view.hide, cancelPlacement = placement.cancel, beginPlacement = placement.begin, props = function(list) props.sync(list); alarms.sync(list) end,
    send = function(packet) TriggerServerEvent('os_security:g6:request', packet) end,
    timeout = function(callback) SetTimeout(8000, callback) end,
    expiry = function(expires) SendNUIMessage({ type = 'expiry', expires = expires }) end,
    notify = function(message, kind) OSSecurity.Notify(message or OSSecurity.Brand.Text.failed, kind) end
})

liveView = OSSecurity.ClientLive.new({
    send = SendNUIMessage,
    request = function(deviceId, callback) controller.liveFeed(deviceId, callback) end,
    exit = function() controller.liveEnd() end
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

-- Editor de zona abierto desde el panel F10 (os_admin): mismo editor y misma validacion del servidor.
RegisterNetEvent('os_security:g6:anchorEditor', function(payload)
    if source ~= 65535 or type(payload) ~= 'table' or type(payload.id) ~= 'string' or controller.placing then return end
    local args = { payload.id, tostring(payload.client), payload.installer and tostring(payload.installer) or nil }
    OSSecurity.ClientAnchor.begin(args, function(aimed)
        aimed.site = payload.site
        TriggerServerEvent('os_security:g6:anchorAim', aimed)
    end, OSSecurity.Notify)
end)

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
-- Visor de camara para marcar una zona desde la tablet (seccion Instalaciones). E hace la "foto" y el
-- servidor registra la zona; al terminar (o al cancelar) se vuelve a la tablet en Instalaciones.
local function startViewfinder(data)
    SendNUIMessage({ type = 'viewfinder', action = 'show', info = { id = data.id, client = data.client, site = data.site } })
    OSSecurity.ClientAnchor.begin({ data.id }, function(payload)
        TriggerServerEvent('os_security:g6:zoneAim', payload)
    end, OSSecurity.Notify, {
        update = function(state) SendNUIMessage({ type = 'viewfinder', action = 'update', state = state }) end,
        finish = function(shot)
            SendNUIMessage({ type = 'viewfinder', action = shot and 'shot' or 'hide' })
            if not shot then SetTimeout(300, function() controller.open('operations', 'installations') end) end
        end
    })
end
RegisterNetEvent('os_security:g6:zoneResult', function(ok, message)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or 'error')
    SetTimeout(900, function() controller.open('operations', 'installations') end)
end)
-- Localizadores: marcar en el GPS la posicion que el servidor ha dado para un vehiculo propio.
RegisterNUICallback('waypoint', function(body, callback)
    callback({ ok = true })
    if type(body) == 'table' and type(body.x) == 'number' and type(body.y) == 'number' then
        SetNewWaypoint(body.x + 0.0, body.y + 0.0)
        OSSecurity.Notify('Vehiculo marcado en el GPS.', 'info')
    end
end)

RegisterNUICallback('request', function(body, callback)
    if type(body) ~= 'table' or type(body.action) ~= 'string' or type(body.args) ~= 'table' then callback({ ok = false }); return end
    if body.action == 'use' then controller.use(body.args.item, callback)
    elseif body.action == 'place_begin' then controller.place(callback)
    elseif body.action == 'remove' and type(body.args.deviceId) == 'string' then controller.remove(body.args.deviceId, callback)
    elseif body.action == 'zone_begin' then controller.markZone(body.args, callback, startViewfinder)
    elseif body.action == 'zone_install' then controller.installZone(body.args, callback)
    elseif body.action == 'live' and type(body.args.deviceId) == 'string' then controller.live(body.args.deviceId, callback)
    elseif ({ inventory = true, devices = true, device = true, maintain = true, alarm = true, doors = true, trackers = true, incidents = true,
        zones = true, zone_delete = true, requests = true, request_create = true, request_cancel = true, request_pay = true,
        orders = true, order_accept = true, order_release = true, order_bill = true })[body.action] then controller.request(body.action, body.args, callback)
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
RegisterNetEvent('os_security:alarm:entry', function(deviceId, seconds) if source == 65535 and type(seconds) == 'number' then alarms.entry(deviceId, seconds) end end)
RegisterNetEvent('os_security:alarm:siren', function(deviceId, position) if source == 65535 then alarms.siren(deviceId, position) end end)
RegisterNetEvent('os_security:alarm:alert', function(text, kind, position) if source == 65535 and type(text) == 'string' then alarms.alert(text, kind, position) end end)
RegisterNUICallback('pinpad', function(body, callback)
    callback({ ok = true })
    if not alarms.open or type(body) ~= 'table' then return end
    if body.action == 'tag' then TriggerServerEvent('os_security:alarm:tag', alarms.open)
    elseif ({ arm = true, partial = true, disarm = true })[body.action] then TriggerServerEvent('os_security:alarm:keypad', alarms.open, body.action, type(body.pin) == 'string' and body.pin or '') end
end)
RegisterNUICallback('pinpadKey', function(_, callback) callback({ ok = true }) end)
RegisterNUICallback('pinpadClose', function(_, callback) callback({ ok = true }); alarms.close() end)
CreateThread(function()
    while true do
        local sleep = 500
        if not alarms.open and not controller.visible and not controller.placing then
            local ped = PlayerPedId()
            local here = GetEntityCoords(ped)
            local onFoot = not IsPedInAnyVehicle(ped, false) and not cylinderOpen
            local keypad = onFoot and alarms.nearest(here, 1.6)
            local door = onFoot and not keypad and locks.nearest(here, 1.8)
            if keypad then
                sleep = 0
                BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(OSSecurity.Brand.Text.alarm.keypadHint); EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustPressed(0, 38) then TriggerServerEvent('os_security:alarm:panel', keypad.id)
                elseif IsControlJustPressed(0, 47) then TriggerServerEvent('os_security:alarm:tag', keypad.id) end -- G: acercar chapa
            elseif door then
                sleep = 0
                local L = OSSecurity.Brand.Text.locks
                BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(door.locked and L.unlockHint or L.lockHint); EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustPressed(0, 38) then
                    -- Gesto de girar la llave; el servidor decide si se tiene la llave.
                    RequestAnimDict('anim@heists@keycard@')
                    local deadline = GetGameTimer() + 500
                    while not HasAnimDictLoaded('anim@heists@keycard@') and GetGameTimer() < deadline do Wait(0) end
                    if HasAnimDictLoaded('anim@heists@keycard@') then TaskPlayAnim(ped, 'anim@heists@keycard@', 'exit', 8.0, -8.0, 900, 48, 0, false, false, false) end
                    TriggerServerEvent('os_security:locks:toggle', door.id)
                    sleep = 600
                end
            end
        end
        Wait(sleep)
    end
end)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then alarms.clear() end end)

-- Cerraduras: estado de las puertas, propiedades donde detectarlas, resultados y cambio de bombin.
RegisterNetEvent('os_security:locks:doors', function(list, targets)
    if source ~= 65535 then return end
    locks.apply(list)
    if targets then locks.setTargets(targets) end
end)
RegisterNetEvent('os_security:locks:result', function(ok, message)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or 'error')
end)
CreateThread(function() -- los titulares cambian en os_devtools sin aviso: se resincroniza cada minuto
    while not NetworkIsPlayerActive(PlayerId()) do Wait(1000) end
    while true do TriggerServerEvent('os_security:locks:sync'); Wait(60000) end
end)
local function cylinderClose(success)
    if not cylinderOpen then return end
    cylinderOpen = false
    SetNuiFocus(false, false); minigameFx.stop()
    SendNUIMessage({ type = 'cylinderClose' })
    TriggerServerEvent('os_security:locks:changeFinish', success == true)
end
RegisterNetEvent('os_security:locks:change', function(data)
    if source ~= 65535 or type(data) ~= 'table' or cylinderOpen or minigame.active() or controller.visible then
        if source == 65535 and not cylinderOpen then TriggerServerEvent('os_security:locks:changeFinish', false) end
        return
    end
    cylinderOpen = true
    minigameFx.phase('screw')
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'cylinder', data = { from = data.from, to = data.to, tier = data.tier }, text = OSSecurity.Brand.Text.locks.minigame })
    local mine = session('cylinder')
    SetTimeout(170000, function() if cylinderOpen and sessions.cylinder == mine then cylinderClose(false) end end)
end)
RegisterNUICallback('cylinder', function(body, callback)
    callback({ ok = true })
    cylinderClose(type(body) == 'table' and body.ok == true)
end)
RegisterNUICallback('cylinderFx', function(body, callback)
    callback({ ok = true })
    if not cylinderOpen or type(body) ~= 'table' then return end
    if type(body.phase) == 'string' then minigameFx.phase(body.phase) end
    if type(body.cue) == 'string' then minigameFx.cue(body.cue) end
end)
-- Vehiculos: mando (L por defecto, configurable en Ajustes > Teclas > FiveM), efectos e instalacion.
RegisterCommand('g6mando', function() if not carwireOpen and not cylinderOpen then cars.key() end end, false)
RegisterKeyMapping('g6mando', 'Llave del vehiculo: abrir / cerrar (Gruppe Sechs)', 'keyboard', 'L')
RegisterNetEvent('os_security:car:fx', function(netId, locked, remote) if source == 65535 and type(netId) == 'number' then cars.fx(netId, locked == true, remote == true) end end)
-- Motor: Y por defecto. Solo en vehiculos con matricula OS hace falta la llave.
RegisterCommand('g6motor', function() if not carwireOpen and not cylinderOpen then cars.engine() end end, false)
RegisterKeyMapping('g6motor', 'Arrancar / apagar el motor (Gruppe Sechs)', 'keyboard', 'Y')
RegisterNetEvent('os_security:car:engineResult', function(ok, message, canHotwire) if source == 65535 then cars.engineResult(ok == true, message, canHotwire == true) end end)
-- Puente: minijuego del vehiculo en modo puente; el servidor valida y, si sale, el motor arranca.
local hotwireOpen = false
RegisterNetEvent('os_security:car:hotwireStart', function(data)
    if source ~= 65535 or type(data) ~= 'table' or hotwireOpen or carwireOpen or cylinderOpen or minigame.active() or controller.visible then return end
    hotwireOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'carwire', data = { kind = 'hotwire', plate = data.plate, decoys = data.decoys, band = data.band }, text = OSSecurity.Brand.Text.cars.minigame })
    local mine = session('hotwire')
    SetTimeout(115000, function()
        if hotwireOpen and sessions.hotwire == mine then
            hotwireOpen = false; SetNuiFocus(false, false); SendNUIMessage({ type = 'carwireClose' }); TriggerServerEvent('os_security:car:hotwireFinish', false)
        end
    end)
end)
RegisterNUICallback('hotwire', function(body, callback)
    callback({ ok = true })
    if not hotwireOpen then return end
    hotwireOpen = false; SetNuiFocus(false, false)
    TriggerServerEvent('os_security:car:hotwireFinish', type(body) == 'table' and body.ok == true)
end)
RegisterNetEvent('os_security:car:hotwireResult', function(ok, message)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or 'error')
    if ok then cars.hotwired() end
end)
RegisterNetEvent('os_security:car:alarm', function(netId, seconds)
    if source == 65535 and type(netId) == 'number' and type(seconds) == 'number' then cars.alarm(netId, seconds) end
end)
RegisterNetEvent('os_security:car:result', function(ok, message)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or 'error')
end)
local function carwireClose(success)
    if not carwireOpen then return end
    carwireOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'carwireClose' })
    TriggerServerEvent('os_security:car:installFinish', success == true)
end
RegisterNetEvent('os_security:car:install', function(data)
    if source ~= 65535 then return end
    if type(data) ~= 'table' or carwireOpen or cylinderOpen or minigame.active() or controller.visible then
        TriggerServerEvent('os_security:car:installFinish', false); return
    end
    carwireOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'carwire', data = { kind = data.kind, plate = data.plate }, text = OSSecurity.Brand.Text.cars.minigame })
    local mine = session('carwire')
    SetTimeout(170000, function() if carwireOpen and sessions.carwire == mine then carwireClose(false) end end)
end)
RegisterNUICallback('carwire', function(body, callback)
    callback({ ok = true })
    carwireClose(type(body) == 'table' and body.ok == true)
end)

-- Ganzua: minijuego de pines; el servidor ya ha elegido la puerta o el vehiculo y valida el resultado.
local lockpickOpen = false
RegisterNetEvent('os_security:lockpick:start', function(challenge)
    if source ~= 65535 or type(challenge) ~= 'table' or lockpickOpen or carwireOpen or cylinderOpen or minigame.active() or controller.visible then return end
    lockpickOpen = true
    minigameFx.phase('cables')
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'lockpick', data = { kind = challenge.kind, tier = challenge.tier, pins = challenge.pins, zone = challenge.zone,
        speed = challenge.speed, seconds = challenge.seconds }, text = OSSecurity.Brand.Text.lockpick })
end)
RegisterNUICallback('lockpick', function(body, callback)
    callback({ ok = true })
    if not lockpickOpen then return end
    lockpickOpen = false
    SetNuiFocus(false, false); minigameFx.stop()
    local result = type(body) == 'table' and (body.cancel == true and 'cancel' or body.ok == true) or false
    TriggerServerEvent('os_security:lockpick:finish', result)
end)
RegisterNetEvent('os_security:lockpick:result', function(ok, message, broken)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or (broken and 'error' or 'warning'))
end)

-- Tienda G6: mostrador con E; catalogo, compra y saldo los da el servidor.
local shopOpen = false
local shop = OSSecurity.ClientShop.new({ busy = function()
    return shopOpen or controller.visible or controller.placing or controller.watching or lockpickOpen or carwireOpen or cylinderOpen or minigame.active()
end })
RegisterNetEvent('os_security:shop:locations', function(list) if source == 65535 then shop.setLocations(list) end end)
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(1000) end
    TriggerServerEvent('os_security:shop:locations')
end)
-- F10 > Tienda en la calle: carretera mas cercana a Union Depository, igual que el furgon de las misiones.
RegisterNetEvent('os_security:shop:findRoad', function(around)
    if source ~= 65535 or type(around) ~= 'table' then return end
    local ok, position = GetClosestVehicleNodeWithHeading(around.x + 0.0, around.y + 0.0, around.z + 0.0, 1, 3.0, 0)
    if not ok or ok == 0 then OSSecurity.Notify('No hay carretera cargada cerca: acercate a Union Depository y repite.', 'error'); return end
    TriggerServerEvent('os_security:shop:roadPoint', { x = position.x, y = position.y, z = position.z })
end)
RegisterNetEvent('os_security:shop:moved', function(ok, message)
    if source ~= 65535 or type(message) ~= 'string' then return end
    OSSecurity.Notify(message, ok and 'success' or 'error')
end)
RegisterNetEvent('os_security:shop:catalog', function(ok, data)
    if source ~= 65535 then return end
    if not ok or type(data) ~= 'table' then OSSecurity.Notify(type(data) == 'string' and data or OSSecurity.Brand.Text.failed, 'error'); return end
    if shopOpen or controller.visible or minigame.active() then return end
    shopOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'shop', data = data, text = OSSecurity.Brand.Text.shop })
end)
RegisterNUICallback('shopBuy', function(body, callback)
    callback({ ok = true })
    if not shopOpen or type(body) ~= 'table' or type(body.cart) ~= 'table' then return end
    TriggerServerEvent('os_security:shop:buy', body.cart, body.account)
end)
RegisterNetEvent('os_security:shop:result', function(ok, data)
    if source ~= 65535 then return end
    local text = ok and type(data) == 'table' and data.message or data
    if type(text) == 'string' then OSSecurity.Notify(text, ok and (data.partial and 'warning' or 'success') or 'error') end
    if shopOpen then SendNUIMessage({ type = 'shopResult', ok = ok == true, data = data }) end
end)
RegisterNUICallback('shopClose', function(_, callback)
    callback({ ok = true })
    shopOpen = false
    SetNuiFocus(false, false)
end)
CreateThread(function()
    while true do
        Wait(1000)
        if shopOpen and IsEntityDead(PlayerPedId()) then shopOpen = false; SetNuiFocus(false, false); SendNUIMessage({ type = 'shopClose' }) end
    end
end)

-- Puerta apuntada desde el panel F10: E sobre la puerta la registra; Retroceso o Esc sale.
local aimingDoor = 0
RegisterNetEvent('os_security:locks:aimDoor', function(site)
    if source ~= 65535 or type(site) ~= 'table' then return end
    aimingDoor = aimingDoor + 1
    local mine = aimingDoor
    CreateThread(function()
        local deadline = GetGameTimer() + 60000
        while mine == aimingDoor and GetGameTimer() < deadline do
            Wait(0)
            DisableControlAction(0, 38, true)
            local entity = locks.aimed(8.0)
            local text = entity and '~INPUT_CONTEXT~ registrar esta puerta   ~INPUT_FRONTEND_RRIGHT~ salir' or 'Apunta a la puerta   ~INPUT_FRONTEND_RRIGHT~ salir'
            BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayHelp(0, false, false, -1)
            if entity then
                local p = GetEntityCoords(entity)
                DrawMarker(0, p.x, p.y, p.z + 1.2, 0, 0, 0, 0, 0, 0, 0.3, 0.3, 0.3, 230, 200, 60, 200, true, true, 2, false, nil, nil, false)
                if IsDisabledControlJustPressed(0, 38) then
                    TriggerServerEvent('os_security:locks:register', { kind = site.kind, id = site.id, model = GetEntityModel(entity),
                        position = { x = p.x, y = p.y, z = p.z } })
                    return
                end
            end
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 200) then OSSecurity.Notify('Registro de puerta cancelado.', 'info'); return end
        end
    end)
end)

-- /g6puerta <propiedad|negocio> <id> | borrar: apano manual para una puerta que no se detecte sola.
RegisterCommand('g6puerta', function(_, args)
    if args[1] == 'borrar' then TriggerServerEvent('os_security:locks:register', { remove = true }); return end
    local entity = locks.aimed(8.0)
    if not entity then OSSecurity.Notify('Apunta a la puerta: /g6puerta <propiedad|negocio> <id> (o /g6puerta borrar junto a ella).', 'warning'); return end
    local p = GetEntityCoords(entity)
    TriggerServerEvent('os_security:locks:register', { kind = args[1], id = tonumber(args[2]), model = GetEntityModel(entity),
        position = { x = p.x, y = p.y, z = p.z } })
end, false)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if cylinderOpen then cylinderOpen = false; SetNuiFocus(false, false); minigameFx.stop() end
    if carwireOpen then carwireOpen = false; SetNuiFocus(false, false) end
    if lockpickOpen then lockpickOpen = false; SetNuiFocus(false, false) end
    if hotwireOpen then hotwireOpen = false; SetNuiFocus(false, false) end
    if shopOpen then shopOpen = false; SetNuiFocus(false, false) end
    if liveView and liveView.active then liveView.stop() end
    shop.clear()
    locks.clear()
end)
