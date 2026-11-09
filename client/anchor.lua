-- /g6anchor <id> <idCliente> [idInstalador]: editor para registrar la zona de montaje.
-- Se apunta a una pared, techo o suelo y se ve en vivo el cuadrado; la rueda cambia su tamano
-- (semilado 0,25-2 m), Ctrl hace el ajuste fino y E lo registra. Retroceso o Esc cancela.
-- Solo propone centro, normal y tamano: el servidor exige ossecurity.admin y revalida todo.
OSSecurity.ClientAnchor = {}
local SIZE_MIN, SIZE_MAX, SIZE_STEP, REACH = 0.25, 2.0, 0.05, 8.0
local CONTROLS = { wheelUp = 14, wheelDown = 15, fine = 36, confirm = 38, enter = 191, cancel = 177, escape = 200 }

function OSSecurity.ClientAnchor.size(current, delta, fine)
    local step = fine and SIZE_STEP / 5 or SIZE_STEP
    local value = math.floor((current + delta * step) * 100 + 0.5) / 100
    return math.max(SIZE_MIN, math.min(SIZE_MAX, value))
end

local active = 0
function OSSecurity.ClientAnchor.begin(args, send, notify)
    local client, installer = tonumber(args[2]), args[3] and tonumber(args[3]) or nil
    if not args[1] or not client or (args[3] and not installer) then
        notify('Uso: /g6anchor <id> <idCliente> [idInstalador], y apunta a la pared o al techo.', 'warning'); return
    end
    active = active + 1
    local current, size = active, 0.75
    CreateThread(function()
        local handle, hit, point, normal
        while current == active do
            Wait(0)
            if IsControlJustPressed(0, CONTROLS.cancel) or IsControlJustPressed(0, CONTROLS.escape) or IsEntityDead(PlayerPedId()) then
                active = active + 1; notify('Registro de zona cancelado.', 'info'); return
            end
            for _, control in pairs(CONTROLS) do
                if control ~= CONTROLS.cancel and control ~= CONTROLS.escape then DisableControlAction(0, control, true) end
            end
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            local fine = IsDisabledControlPressed(0, CONTROLS.fine)
            if IsDisabledControlJustPressed(0, CONTROLS.wheelUp) then size = OSSecurity.ClientAnchor.size(size, 1, fine) end
            if IsDisabledControlJustPressed(0, CONTROLS.wheelDown) then size = OSSecurity.ClientAnchor.size(size, -1, fine) end
            if not handle then
                local camera, rotation = GetGameplayCamCoord(), GetGameplayCamRot(2)
                local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
                local horizontal = math.abs(math.cos(pitch))
                handle = StartShapeTestLosProbe(camera.x, camera.y, camera.z,
                    camera.x - math.sin(yaw) * horizontal * REACH, camera.y + math.cos(yaw) * horizontal * REACH,
                    camera.z + math.sin(pitch) * REACH, 1, PlayerPedId(), 7)
            end
            local status, result, at, surface = GetShapeTestResult(handle)
            if status == 2 then
                handle = nil
                hit = result == 1 or result == true
                if hit then point, normal = at, surface end
            elseif status == 0 then handle = nil end
            if hit and point then
                local zone = { position = point, normal = normal, radius = size }
                OSSecurity.ClientPlacement.drawZone(zone)
                if IsDisabledControlJustPressed(0, CONTROLS.confirm) or IsDisabledControlJustPressed(0, CONTROLS.enter) then
                    active = active + 1
                    send({ id = args[1], client = math.floor(client), installer = installer and math.floor(installer) or nil,
                        radius = size, position = { x = point.x, y = point.y, z = point.z }, normal = { x = normal.x, y = normal.y, z = normal.z } })
                    return
                end
            end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(OSSecurity.Brand.Text.anchorHelp)
            AddTextComponentSubstringPlayerName(('~n~%s ~b~%s~s~  %.2f x %.2f m%s'):format(OSSecurity.Brand.Text.anchorZone, args[1],
                size * 2, size * 2, hit and '' or '  (sin superficie)'))
            EndTextCommandDisplayHelp(0, false, false, -1)
        end
    end)
end
