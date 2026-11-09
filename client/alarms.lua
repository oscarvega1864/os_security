-- Alarmas en el cliente: teclado junto al dispositivo (E), aviso de entrada, sirena y marcador de aviso.
-- El cliente no decide nada: pide al servidor y muestra lo que este responde.
OSSecurity.ClientAlarms = {}

function OSSecurity.ClientAlarms.new()
    local alarms = { keypads = {}, open = nil }
    local sirens, alertBlips = {}, {} -- sirens: deviceId -> posicion del teclado
    local volume = 0
    local function beep(frequency, duration) SendNUIMessage({ type = 'beep', frequency = frequency, duration = duration }) end
    -- Volumen de la sirena segun la sirena activa mas cercana (inaudible a 150 m).
    CreateThread(function()
        while true do
            Wait(250)
            local loudest = 0
            if next(sirens) then
                local here = GetEntityCoords(PlayerPedId())
                for _, position in pairs(sirens) do
                    local d = #(here - vector3(position.x, position.y, position.z))
                    loudest = math.max(loudest, 1.0 - math.min(1.0, d / 150.0))
                end
            end
            if math.abs(loudest - volume) > 0.02 or (loudest == 0 and volume ~= 0) then
                volume = loudest
                SendNUIMessage({ type = 'siren', volume = volume })
            end
        end
    end)
    local A = OSSecurity.Brand.Text.alarm

    -- Teclados cercanos a partir de los props que ya se transmiten (dispositivos instalados).
    function alarms.sync(list)
        local keypads = {}
        for _, entry in ipairs(list or {}) do if entry.kind == 'alarm_panel' then keypads[#keypads + 1] = entry end end
        alarms.keypads = keypads
    end
    function alarms.nearest(point, maxDistance)
        local best, bestDistance
        for _, entry in ipairs(alarms.keypads) do
            local p = entry.position
            local d = math.sqrt((p.x - point.x) ^ 2 + (p.y - point.y) ^ 2 + (p.z - point.z) ^ 2)
            if d <= maxDistance and (not bestDistance or d < bestDistance) then best, bestDistance = entry, d end
        end
        return best
    end
    function alarms.show(data, err)
        if not data then OSSecurity.Notify(err, 'error'); return end
        alarms.open = data.deviceId
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'pinpad', data = data, text = { pad = A.pad, pinFormat = OSSecurity.Brand.Text.alarm.pinFormat } })
    end
    function alarms.result(result, err, panel)
        if alarms.open then SendNUIMessage({ type = 'pinpadResult', ok = result ~= nil, text = result and result.message or err, data = panel })
        else OSSecurity.Notify(result and result.message or err, result and 'success' or 'error') end
        if result then beep(2200, 0.08); SetTimeout(120, function() beep(2200, 0.08) end) else beep(400, 0.35) end
    end
    function alarms.close()
        if not alarms.open then return end
        alarms.open = nil
        SetNuiFocus(false, false)
        SendNUIMessage({ type = 'pinpadClose' })
    end
    -- Aviso de entrada: pitidos durante el retardo.
    function alarms.entry(seconds)
        OSSecurity.Notify(A.entryWarning:format(seconds), 'warning')
        CreateThread(function()
            local deadline = GetGameTimer() + seconds * 1000
            while GetGameTimer() < deadline do
                beep(1900, 0.12)
                Wait(GetGameTimer() > deadline - 10000 and 500 or 1000)
            end
        end)
    end
    -- Sirena en la posicion del teclado: la genera la NUI (web/siren.js) con volumen por distancia.
    function alarms.siren(deviceId, position)
        if type(position) == 'table' and type(position.x) == 'number' then sirens[deviceId] = { x = position.x, y = position.y, z = position.z }
        else sirens[deviceId] = nil end
    end
    -- Aviso al titular o a Gruppe Sechs: notificacion y marcador parpadeante temporal.
    function alarms.alert(text, kind, position)
        OSSecurity.Notify(text, kind or 'warning')
        if type(position) ~= 'table' then return end
        local blip = AddBlipForCoord(position.x + 0.0, position.y + 0.0, position.z + 0.0)
        SetBlipSprite(blip, 161); SetBlipColour(blip, 1); SetBlipScale(blip, 1.1); SetBlipFlashes(blip, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(A.title); EndTextCommandSetBlipName(blip)
        alertBlips[#alertBlips + 1] = blip
        SetTimeout(120000, function() if DoesBlipExist(blip) then RemoveBlip(blip) end end)
    end
    function alarms.clear()
        alarms.close()
        sirens = {}; volume = 0; SendNUIMessage({ type = 'siren', volume = 0 })
        for _, blip in ipairs(alertBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
        alertBlips = {}
    end
    return alarms
end
