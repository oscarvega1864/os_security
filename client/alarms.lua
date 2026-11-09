-- Alarmas en el cliente: teclado junto al dispositivo (E), aviso de entrada, sirena y marcador de aviso.
-- El cliente no decide nada: pide al servidor y muestra lo que este responde.
OSSecurity.ClientAlarms = {}

function OSSecurity.ClientAlarms.new()
    local alarms = { keypads = {}, open = nil }
    local sirens, alertBlips = {}, {}
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
        SendNUIMessage({ type = 'pinpadResult', ok = result ~= nil, text = result and result.message or err, data = panel })
        PlaySoundFrontend(-1, result and 'SELECT' or 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
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
                PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                Wait(GetGameTimer() > deadline - 10000 and 500 or 1000)
            end
        end)
    end
    -- Sirena en la posicion del teclado (si estas cerca). Sonido configurable en el servidor.
    function alarms.siren(deviceId, position, name, set)
        local current = sirens[deviceId]
        if current then StopSound(current); ReleaseSoundId(current); sirens[deviceId] = nil end
        if type(position) ~= 'table' or type(name) ~= 'string' or type(set) ~= 'string' then return end
        local here = GetEntityCoords(PlayerPedId())
        if #(here - vector3(position.x, position.y, position.z)) > 150.0 then return end
        local id = GetSoundId()
        PlaySoundFromCoord(id, name, position.x + 0.0, position.y + 0.0, position.z + 0.0, set, false, 0, false)
        sirens[deviceId] = id
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
        for deviceId, id in pairs(sirens) do StopSound(id); ReleaseSoundId(id); sirens[deviceId] = nil end
        for _, blip in ipairs(alertBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
        alertBlips = {}
    end
    return alarms
end
