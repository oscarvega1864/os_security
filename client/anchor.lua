-- /g6anchor <id> <idCliente> [idInstalador]: editor para registrar la zona de montaje, en dos pasos.
--   1. Apuntar: el cuadrado sigue la mira sobre pared, techo o suelo. E fija la superficie.
--   2. Ajustar: flechas para mover el cuadrado sobre la superficie, rueda para el tamano
--      (semilado 0,25-2 m), Ctrl ajuste fino. E registra; Retroceso vuelve a apuntar.
-- Esc cancela en cualquier momento. Solo propone centro, normal y tamano: el servidor exige
-- ossecurity.admin y revalida todo.
OSSecurity.ClientAnchor = {}
local SIZE_MIN, SIZE_MAX, SIZE_STEP, REACH, MOVE_SPEED, MOVE_LIMIT = 0.25, 2.0, 0.05, 8.0, 0.5, 3.0
local CONTROLS = { left = 174, right = 175, up = 172, down = 173, wheelUp = 14, wheelDown = 15, fine = 36,
    confirm = 38, enter = 191, back = 177, escape = 200 }

function OSSecurity.ClientAnchor.size(current, delta, fine)
    local step = fine and SIZE_STEP / 5 or SIZE_STEP
    local value = math.floor((current + delta * step) * 100 + 0.5) / 100
    return math.max(SIZE_MIN, math.min(SIZE_MAX, value))
end

-- Desplaza el centro sobre la superficie fijada, limitado a MOVE_LIMIT metros del punto apuntado.
function OSSecurity.ClientAnchor.move(base, normal, x, y)
    x, y = math.max(-MOVE_LIMIT, math.min(MOVE_LIMIT, x)), math.max(-MOVE_LIMIT, math.min(MOVE_LIMIT, y))
    local point = OSSecurity.Geometry.point({ position = base, normal = normal, radius = MOVE_LIMIT }, x, y)
    return point, x, y
end

local active = 0
function OSSecurity.ClientAnchor.begin(args, send, notify)
    local client, installer = tonumber(args[2]), args[3] and tonumber(args[3]) or nil
    if not args[1] or not client or (args[3] and not installer) then
        notify('Uso: /g6anchor <id> <idCliente> [idInstalador], y apunta a la pared o al techo.', 'warning'); return
    end
    active = active + 1
    local current, size, mode = active, 0.75, 'aim'
    CreateThread(function()
        local handle, hit, point, normal, base, x, y, last = nil, false, nil, nil, nil, 0.0, 0.0, GetGameTimer()
        while current == active do
            Wait(0)
            local now = GetGameTimer(); local dt = math.min(0.1, (now - last) / 1000); last = now
            if IsControlJustPressed(0, CONTROLS.escape) or IsEntityDead(PlayerPedId()) then
                active = active + 1; notify('Registro de zona cancelado.', 'info'); return
            end
            for _, control in pairs(CONTROLS) do
                if control ~= CONTROLS.escape then DisableControlAction(0, control, true) end
            end
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            local fine = IsDisabledControlPressed(0, CONTROLS.fine)
            if IsDisabledControlJustPressed(0, CONTROLS.wheelUp) then size = OSSecurity.ClientAnchor.size(size, 1, fine) end
            if IsDisabledControlJustPressed(0, CONTROLS.wheelDown) then size = OSSecurity.ClientAnchor.size(size, -1, fine) end
            local confirm = IsDisabledControlJustPressed(0, CONTROLS.confirm) or IsDisabledControlJustPressed(0, CONTROLS.enter)
            if mode == 'aim' then
                if IsDisabledControlJustPressed(0, CONTROLS.back) then active = active + 1; notify('Registro de zona cancelado.', 'info'); return end
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
                    if hit then point, normal = { x = at.x, y = at.y, z = at.z }, { x = surface.x, y = surface.y, z = surface.z } end
                elseif status == 0 then handle = nil end
                if hit and point and confirm then mode, base, x, y = 'adjust', point, 0.0, 0.0 end
            else
                if IsDisabledControlJustPressed(0, CONTROLS.back) then mode, hit = 'aim', false
                else
                    local speed = MOVE_SPEED * (fine and 0.2 or 1.0) * dt
                    x = x + ((IsDisabledControlPressed(0, CONTROLS.right) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.left) and 1 or 0)) * speed
                    y = y + ((IsDisabledControlPressed(0, CONTROLS.up) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.down) and 1 or 0)) * speed
                    point, x, y = OSSecurity.ClientAnchor.move(base, normal, x, y)
                    if confirm then
                        active = active + 1
                        send({ id = args[1], client = math.floor(client), installer = installer and math.floor(installer) or nil,
                            radius = size, position = point, normal = normal })
                        return
                    end
                end
            end
            if (mode == 'adjust' or hit) and point then OSSecurity.ClientPlacement.drawZone({ position = point, normal = normal, radius = size }) end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(mode == 'aim' and OSSecurity.Brand.Text.anchorAimHelp or OSSecurity.Brand.Text.anchorHelp)
            AddTextComponentSubstringPlayerName(('~n~%s ~b~%s~s~  %.2f x %.2f m%s'):format(OSSecurity.Brand.Text.anchorZone, args[1],
                size * 2, size * 2, mode == 'adjust' and ('  X %+.2f  Y %+.2f'):format(x, y) or (hit and '' or '  (sin superficie)')))
            EndTextCommandDisplayHelp(0, false, false, -1)
        end
    end)
end
