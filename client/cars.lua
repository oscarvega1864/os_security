-- Vehiculos en el cliente: mando (tecla L por defecto), destellos y pitido al abrir o cerrar, alarma y
-- aviso al servidor cuando alguien intenta entrar en un vehiculo cerrado. El servidor decide todo; el
-- estado de cada vehiculo llega en su state bag 'g6car' = { locked, alarm }.
OSSecurity.ClientCars = {}

function OSSecurity.ClientCars.new(options)
    local cars = {}
    local function state(vehicle) local value = Entity(vehicle).state.g6car; return type(value) == 'table' and value or nil end
    -- Vehiculo para el mando: en el que vas o el mas cercano con equipo G6 a 'reach' metros.
    function cars.target(reach)
        local ped = PlayerPedId()
        local inside = GetVehiclePedIsIn(ped, false)
        if inside ~= 0 and state(inside) then return inside end
        local here, best, bestDistance = GetEntityCoords(ped), nil, nil
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if state(vehicle) then
                local d = #(GetEntityCoords(vehicle) - here)
                if d <= reach and (not bestDistance or d < bestDistance) then best, bestDistance = vehicle, d end
            end
        end
        return best
    end
    function cars.key()
        local vehicle = cars.target(15.0)
        if not vehicle then options.notify('No hay ningun vehiculo con cierre centralizado cerca.', 'info'); return end
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            RequestAnimDict('anim@mp_player_intmenu@key_fob@')
            local deadline = GetGameTimer() + 500
            while not HasAnimDictLoaded('anim@mp_player_intmenu@key_fob@') and GetGameTimer() < deadline do Wait(0) end
            if HasAnimDictLoaded('anim@mp_player_intmenu@key_fob@') then TaskPlayAnim(ped, 'anim@mp_player_intmenu@key_fob@', 'fob_click', 8.0, -8.0, 800, 48, 0, false, false, false) end
        end
        TriggerServerEvent('os_security:car:toggle', NetworkGetNetworkIdFromEntity(vehicle))
    end
    -- Destellos de intermitentes y pitido: uno al cerrar, dos al abrir.
    function cars.fx(netId, locked)
        if not NetworkDoesNetworkIdExist(netId) then return end
        local vehicle = NetToVeh(netId)
        if vehicle == 0 then return end
        SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
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
