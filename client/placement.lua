OSSecurity.ClientPlacement = {}

-- Editor de colocacion. La previsualizacion se ancla al montaje autorizado (sin seguir la mira) y se
-- ajusta con el teclado sobre los ejes de la superficie (pared, techo o suelo):
--   Flechas: mover X / Y dentro del cuadrado del montaje.
--   Mayus + flechas o rueda: girar (izquierda/derecha) e inclinar (arriba/abajo).
--   R: dar la vuelta a la camara (montaje invertido, para techos). Ctrl: ajuste fino.
--   Tab: siguiente montaje. E o Intro: confirmar. Retroceso o Esc: cancelar.
-- Todo es local y visual: el servidor revalida montaje, cuadrado, plano, giro, distancia y objetos.
local CONTROLS = { left = 174, right = 175, up = 172, down = 173, fine = 36, rotate = 21, next = 37, flip = 45,
    wheelUp = 14, wheelDown = 15, confirm = 38, enter = 191, cancel = 177, escape = 200 }
local MOVE_SPEED, TURN_SPEED = 0.30, 60.0 -- m/s y grados/s
OSSecurity.ClientPlacement.TiltLimit = 90.0 -- igual que el servidor

-- Rumbo inicial: mirando hacia fuera de la pared (vector frontal de GTA: -sin(h), cos(h)).
-- En techo o suelo no hay "fuera": se usa el rumbo de reserva (el del jugador).
function OSSecurity.ClientPlacement.heading(mount, fallback)
    local n = OSSecurity.Geometry.frame(mount.normal).normal
    if math.abs(n.z) >= 0.95 then return (fallback or 0.0) % 360 end
    return math.deg(math.atan(-n.x, n.y)) % 360
end

-- Orientacion inicial: en techo, invertida y mirando hacia abajo; en pared, recta.
function OSSecurity.ClientPlacement.initial(mount, fallback)
    local n = OSSecurity.Geometry.frame(mount.normal).normal
    local yaw = OSSecurity.ClientPlacement.heading(mount, fallback)
    if n.z <= -0.95 then return yaw, -45.0, 180.0 end
    return yaw, 0.0, 0.0
end

-- Cuadrado de la zona de montaje sobre la superficie: borde y relleno translucido por ambas caras.
function OSSecurity.ClientPlacement.drawZone(mount)
    local c = OSSecurity.Geometry.corners(mount, 0.01)
    for i = 1, 4 do
        local a, b = c[i], c[i % 4 + 1]
        DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, 140, 220, 120, 230)
    end
    -- Relleno translucido por ambas caras.
    DrawPoly(c[1].x, c[1].y, c[1].z, c[2].x, c[2].y, c[2].z, c[3].x, c[3].y, c[3].z, 120, 200, 110, 40)
    DrawPoly(c[1].x, c[1].y, c[1].z, c[3].x, c[3].y, c[3].z, c[4].x, c[4].y, c[4].z, 120, 200, 110, 40)
    DrawPoly(c[3].x, c[3].y, c[3].z, c[2].x, c[2].y, c[2].z, c[1].x, c[1].y, c[1].z, 120, 200, 110, 40)
    DrawPoly(c[4].x, c[4].y, c[4].z, c[3].x, c[3].y, c[3].z, c[1].x, c[1].y, c[1].z, 120, 200, 110, 40)
end

function OSSecurity.ClientPlacement.new()
    local manager, generation, prop = {}, 0, nil
    function manager.cancel()
        generation = generation + 1
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
        prop = nil
    end
    function manager.begin(context, callback)
        manager.cancel()
        local current = generation
        CreateThread(function()
            local model = GetHashKey(context.model)
            if not IsModelInCdimage(model) or not IsModelValid(model) then callback(nil); return end
            RequestModel(model)
            local timeout = GetGameTimer() + 3000
            while generation == current and not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
            if generation ~= current then SetModelAsNoLongerNeeded(model); return end
            if not HasModelLoaded(model) then SetModelAsNoLongerNeeded(model); callback(nil); return end
            local ped, origin = PlayerPedId(), GetEntityCoords(PlayerPedId())
            prop = CreateObjectNoOffset(model, origin.x, origin.y, origin.z, false, false, false)
            if not prop or prop == 0 then SetModelAsNoLongerNeeded(model); callback(nil); return end
            SetEntityCollision(prop, false, false); FreezeEntityPosition(prop, true); SetEntityAlpha(prop, 170, false)
            local mounts = context.mounts or {}
            -- Empieza por el montaje mas cercano al jugador.
            local index, best = 1, math.huge
            for i, candidate in ipairs(mounts) do
                local p = candidate.position
                local d = (p.x - origin.x) ^ 2 + (p.y - origin.y) ^ 2 + (p.z - origin.z) ^ 2
                if d < best then index, best = i, d end
            end
            local x, y, yaw, tilt, roll = 0.0, 0.0, 0.0, 0.0, 0.0
            local function reset()
                x, y = 0.0, 0.0
                yaw, tilt, roll = OSSecurity.ClientPlacement.initial(mounts[index], GetEntityHeading(ped))
            end
            if mounts[1] then reset() end
            local limit = OSSecurity.ClientPlacement.TiltLimit
            local deadline, last = GetGameTimer() + context.seconds * 1000, GetGameTimer()
            while generation == current do
                Wait(0) -- Solo durante esta colocacion activa.
                ped = PlayerPedId()
                local position = GetEntityCoords(ped)
                local moved = math.sqrt((position.x-origin.x)^2 + (position.y-origin.y)^2 + (position.z-origin.z)^2)
                if IsEntityDead(ped) or moved > 6 or GetGameTimer() > deadline or IsPedInAnyVehicle(ped, false) or not mounts[1]
                    or IsControlJustPressed(0, CONTROLS.cancel) or IsControlJustPressed(0, CONTROLS.escape) then
                    manager.cancel(); callback(nil); break
                end
                local now = GetGameTimer(); local dt = math.min(0.1, (now - last) / 1000); last = now
                for _, control in pairs(CONTROLS) do
                    if control ~= CONTROLS.cancel and control ~= CONTROLS.escape then DisableControlAction(0, control, true) end
                end
                DisableControlAction(0, 24, true); DisableControlAction(0, 25, true) -- sin disparar ni apuntar
                if IsDisabledControlJustPressed(0, CONTROLS.next) and #mounts > 1 then index = index % #mounts + 1; reset() end
                local mount = mounts[index]
                local scale = IsDisabledControlPressed(0, CONTROLS.fine) and 0.2 or 1.0
                local h = (IsDisabledControlPressed(0, CONTROLS.right) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.left) and 1 or 0)
                local v = (IsDisabledControlPressed(0, CONTROLS.up) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.down) and 1 or 0)
                if IsDisabledControlPressed(0, CONTROLS.rotate) then
                    yaw = (yaw - h * TURN_SPEED * scale * dt) % 360
                    tilt = math.max(-limit, math.min(limit, tilt + v * TURN_SPEED * scale * dt))
                else
                    x, y = x + h * MOVE_SPEED * scale * dt, y + v * MOVE_SPEED * scale * dt
                end
                if IsDisabledControlJustPressed(0, CONTROLS.wheelUp) then yaw = (yaw + 5 * scale) % 360 end
                if IsDisabledControlJustPressed(0, CONTROLS.wheelDown) then yaw = (yaw - 5 * scale) % 360 end
                if IsDisabledControlJustPressed(0, CONTROLS.flip) then roll = roll == 0.0 and 180.0 or 0.0 end
                local target
                target, x, y = OSSecurity.Geometry.point(mount, x, y, 0.95)
                local n = OSSecurity.Geometry.frame(mount.normal).normal
                SetEntityCoordsNoOffset(prop, target.x + n.x * 0.02, target.y + n.y * 0.02, target.z + n.z * 0.02, false, false, false)
                SetEntityRotation(prop, tilt, roll, yaw, 2, true)
                OSSecurity.ClientPlacement.drawZone(mount)
                if IsDisabledControlJustPressed(0, CONTROLS.confirm) or IsDisabledControlJustPressed(0, CONTROLS.enter) then
                    local proposal = { anchorId = mount.id, position = target, rotation = { x = tilt, y = roll, z = yaw } }
                    manager.cancel(); callback(proposal); break
                end
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(OSSecurity.Brand.Text.placementHelp)
                AddTextComponentSubstringPlayerName(('~n~%s ~b~%s~s~ (%d/%d)  X %+.2f  Y %+.2f  Giro %d  Incl. %+d%s'):format(
                    OSSecurity.Brand.Text.placementMount, mount.id, index, #mounts, x, y, math.floor(yaw + 0.5) % 360,
                    math.floor(tilt + 0.5), roll ~= 0.0 and '  Invertida' or ''))
                EndTextCommandDisplayHelp(0, false, false, -1)
            end
            SetModelAsNoLongerNeeded(model)
        end)
    end
    return manager
end
