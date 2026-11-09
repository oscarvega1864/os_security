-- Vehiculos en el cliente: mando (tecla L por defecto), destellos y pitido al abrir o cerrar, alarma y
-- aviso al servidor cuando alguien intenta entrar en un vehiculo cerrado. El servidor decide todo; el
-- estado de cada vehiculo llega en su state bag 'g6car' = { locked, alarm }.
OSSecurity.ClientCars = {}

function OSSecurity.ClientCars.new(options)
    local cars = {}
    local function state(vehicle) local value = Entity(vehicle).state.g6car; return type(value) == 'table' and value or nil end
    -- Matricula de os_devtools (OS + cifras): esos vehiculos tienen llave.
    local function owned(vehicle) return vehicle ~= 0 and GetVehicleNumberPlateText(vehicle):gsub('%s+', ''):match('^OS%d+$') ~= nil end
    cars.owned = owned
    -- Vehiculo para la llave: en el que vas; si no, el mas cercano con matricula OS a mano (3,5 m) o, con
    -- cierre centralizado (state bag), a distancia de mando.
    function cars.target(reach, manual)
        local ped = PlayerPedId()
        local inside = GetVehiclePedIsIn(ped, false)
        if inside ~= 0 then return inside end
        local here, best, bestDistance = GetEntityCoords(ped), nil, nil
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if owned(vehicle) then
                local d = #(GetEntityCoords(vehicle) - here)
                if (d <= manual or (state(vehicle) and d <= reach)) and (not bestDistance or d < bestDistance) then best, bestDistance = vehicle, d end
            end
        end
        return best
    end
    function cars.key()
        local vehicle = cars.target(15.0, 3.5)
        if not vehicle then options.notify('No hay ningun vehiculo tuyo a mano (acercate a la puerta).', 'info'); return end
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            RequestAnimDict('anim@mp_player_intmenu@key_fob@')
            local deadline = GetGameTimer() + 500
            while not HasAnimDictLoaded('anim@mp_player_intmenu@key_fob@') and GetGameTimer() < deadline do Wait(0) end
            if HasAnimDictLoaded('anim@mp_player_intmenu@key_fob@') then TaskPlayAnim(ped, 'anim@mp_player_intmenu@key_fob@', 'fob_click', 8.0, -8.0, 800, 48, 0, false, false, false) end
        end
        TriggerServerEvent('os_security:car:toggle', NetworkGetNetworkIdFromEntity(vehicle))
    end
    -- Con cierre centralizado: destellos de intermitentes y pitido (uno al cerrar, dos al abrir).
    function cars.fx(netId, locked, remote)
        if not NetworkDoesNetworkIdExist(netId) then return end
        local vehicle = NetToVeh(netId)
        if vehicle == 0 then return end
        SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
        if not remote then return end
        CreateThread(function()
            for _ = 1, locked and 1 or 2 do
                SetVehicleIndicatorLights(vehicle, 0, true); SetVehicleIndicatorLights(vehicle, 1, true)
                StartVehicleHorn(vehicle, 60, GetHashKey('HELDDOWN'), false)
                Wait(180)
                SetVehicleIndicatorLights(vehicle, 0, false); SetVehicleIndicatorLights(vehicle, 1, false)
                Wait(140)
            end
        end)
    end
    function cars.alarm(netId, seconds)
        if not NetworkDoesNetworkIdExist(netId) then return end
        local vehicle = NetToVeh(netId)
        if vehicle == 0 then return end
        if seconds > 0 then
            SetVehicleAlarm(vehicle, true)
            SetVehicleAlarmTimeLeft(vehicle, seconds * 1000)
            StartVehicleAlarm(vehicle)
        else
            SetVehicleAlarmTimeLeft(vehicle, 1)
            SetVehicleAlarm(vehicle, false)
        end
    end
    -- Motor: en un vehiculo con matricula OS el juego no lo arranca solo al subirse; se arranca y se apaga
    -- con la llave (tecla) si el servidor confirma que es tuyo.
    local started = {} -- vehiculo -> true si lo arranco este jugador con la llave
    function cars.engine()
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then options.notify('Sientate al volante.', 'info'); return end
        TriggerServerEvent('os_security:car:engine')
    end
    function cars.engineResult(ok, message)
        if not ok then options.notify(message or 'No tienes la llave de este vehiculo.', 'error'); return end
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 then return end
        local on = not GetIsVehicleEngineRunning(vehicle)
        started[vehicle] = on or nil
        SetVehicleEngineOn(vehicle, on, false, true)
    end
    CreateThread(function()
        local last = 0
        while true do
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsTryingToEnter(ped)
            if vehicle == 0 then vehicle = GetVehiclePedIsIn(ped, false) end
            local keyed = vehicle ~= 0 and owned(vehicle)
            SetPedConfigFlag(ped, 429, keyed) -- no arrancar solo al subir
            if keyed and GetPedInVehicleSeat(vehicle, -1) == ped and not started[vehicle] and GetIsVehicleEngineRunning(vehicle) then
                SetVehicleEngineOn(vehicle, false, true, true)
            end
            if vehicle ~= last then
                if last ~= 0 and not DoesEntityExist(last) then started[last] = nil end
                last = vehicle
            end
            Wait(keyed and 100 or 400)
        end
    end)
    -- Intentar entrar en un vehiculo cerrado (o estar dentro de uno cerrado sin abrirlo) se informa al
    -- servidor, que decide si salta la alarma. Una vez cada 3 s por vehiculo.
    CreateThread(function()
        local reported = {}
        while true do
            Wait(250)
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsTryingToEnter(ped)
            if vehicle == 0 then
                local inside = GetVehiclePedIsIn(ped, false)
                if inside ~= 0 and GetPedInVehicleSeat(inside, -1) == ped then vehicle = inside end
            end
            local value = vehicle ~= 0 and state(vehicle)
            if value and value.locked and NetworkGetEntityIsNetworked(vehicle) then
                local now = GetGameTimer()
                if not reported[vehicle] or now - reported[vehicle] > 3000 then
                    reported[vehicle] = now
                    TriggerServerEvent('os_security:car:tamper', NetworkGetNetworkIdFromEntity(vehicle))
                end
            end
        end
    end)
    return cars
end
