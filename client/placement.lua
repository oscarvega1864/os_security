OSSecurity.ClientPlacement = {}

-- Editor de colocacion. La previsualizacion se ancla al montaje autorizado (sin seguir la mira) y se
-- ajusta con el teclado sobre los ejes de la pared:
--   Flechas: mover X (horizontal) / Y (vertical) dentro del radio del montaje.
--   Mayus + flechas o rueda: girar (izquierda/derecha) e inclinar (arriba/abajo).
--   Ctrl: ajuste fino. Tab: siguiente montaje. E o Intro: confirmar. Retroceso o Esc: cancelar.
-- Todo es local y visual: el servidor revalida montaje, radio, plano, giro, distancia y objetos.
local CONTROLS = { left = 174, right = 175, up = 172, down = 173, fine = 36, rotate = 21, next = 37,
    wheelUp = 14, wheelDown = 15, confirm = 38, enter = 191, cancel = 177, escape = 200 }
local MOVE_SPEED, TURN_SPEED, TILT_LIMIT = 0.30, 60.0, 45.0 -- m/s, grados/s, limite del servidor

local function normalize(v)
    local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if length < 0.0001 then return nil end
    return { x = v.x / length, y = v.y / length, z = v.z / length }
end

-- Ejes locales del montaje: X a lo largo de la pared, Y "hacia arriba" sobre la pared.
function OSSecurity.ClientPlacement.frame(mount)
    local n = normalize(mount.normal) or { x = 0, y = 1, z = 0 }
    -- Derecha de quien mira la pared; en suelo o techo, eje X del mundo.
    local right = normalize({ x = -n.y, y = n.x, z = 0 }) or { x = 1, y = 0, z = 0 }
    local up = { x = n.y * right.z - n.z * right.y, y = n.z * right.x - n.x * right.z, z = n.x * right.y - n.y * right.x }
    return { normal = n, right = right, up = up }
end

-- Rumbo inicial mirando hacia fuera de la pared (vector frontal de GTA: -sin(h), cos(h)).
function OSSecurity.ClientPlacement.heading(mount)
    local n = OSSecurity.ClientPlacement.frame(mount).normal
    if math.abs(n.x) < 0.0001 and math.abs(n.y) < 0.0001 then return 0.0 end
    return math.deg(math.atan(-n.x, n.y)) % 360
end

-- Limita el desplazamiento al radio autorizado (con margen) y devuelve el punto sobre el plano.
function OSSecurity.ClientPlacement.compose(mount, offset)
    local frame, limit = OSSecurity.ClientPlacement.frame(mount), mount.radius * 0.95
    local x, y = offset.x, offset.y
    local length = math.sqrt(x * x + y * y)
    if length > limit then x, y = x * limit / length, y * limit / length end
    offset.x, offset.y = x, y
    local p = mount.position
    return { x = p.x + frame.right.x * x + frame.up.x * y, y = p.y + frame.right.y * x + frame.up.y * y,
        z = p.z + frame.right.z * x + frame.up.z * y }
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
            local offset, yaw, tilt = { x = 0.0, y = 0.0 }, mounts[1] and OSSecurity.ClientPlacement.heading(mounts[index]) or 0.0, 0.0
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
                local mount = mounts[index]
                if IsDisabledControlJustPressed(0, CONTROLS.next) and #mounts > 1 then
                    index = index % #mounts + 1; mount = mounts[index]
                    offset.x, offset.y, tilt, yaw = 0.0, 0.0, 0.0, OSSecurity.ClientPlacement.heading(mount)
                end
                local scale = IsDisabledControlPressed(0, CONTROLS.fine) and 0.2 or 1.0
                local h = (IsDisabledControlPressed(0, CONTROLS.right) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.left) and 1 or 0)
                local v = (IsDisabledControlPressed(0, CONTROLS.up) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.down) and 1 or 0)
                if IsDisabledControlPressed(0, CONTROLS.rotate) then
                    yaw = (yaw - h * TURN_SPEED * scale * dt) % 360
                    tilt = math.max(-TILT_LIMIT, math.min(TILT_LIMIT, tilt + v * TURN_SPEED * scale * dt))
                else
                    offset.x = offset.x + h * MOVE_SPEED * scale * dt
                    offset.y = offset.y + v * MOVE_SPEED * scale * dt
                end
                if IsDisabledControlJustPressed(0, CONTROLS.wheelUp) then yaw = (yaw + 5 * scale) % 360 end
                if IsDisabledControlJustPressed(0, CONTROLS.wheelDown) then yaw = (yaw - 5 * scale) % 360 end
                local target = OSSecurity.ClientPlacement.compose(mount, offset)
                local n = OSSecurity.ClientPlacement.frame(mount).normal
                SetEntityCoordsNoOffset(prop, target.x + n.x * 0.02, target.y + n.y * 0.02, target.z + n.z * 0.02, false, false, false)
                SetEntityRotation(prop, tilt, 0.0, yaw, 2, true)
                -- Zona autorizada: disco del radio del montaje sobre la pared.
                DrawMarker(28, mount.position.x, mount.position.y, mount.position.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    mount.radius, mount.radius, mount.radius, 120, 200, 110, 35, false, false, 2, false, nil, nil, false)
                if IsDisabledControlJustPressed(0, CONTROLS.confirm) or IsDisabledControlJustPressed(0, CONTROLS.enter) then
                    local proposal = { anchorId = mount.id, position = target, rotation = { x = tilt, y = 0, z = yaw } }
                    manager.cancel(); callback(proposal); break
                end
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(OSSecurity.Brand.Text.placementHelp)
                AddTextComponentSubstringPlayerName(('~n~%s ~b~%s~s~ (%d/%d)  X %+.2f  Y %+.2f  Giro %d  Incl. %+d'):format(
                    OSSecurity.Brand.Text.placementMount, mount.id, index, #mounts, offset.x, offset.y, math.floor(yaw + 0.5) % 360, math.floor(tilt + 0.5)))
                EndTextCommandDisplayHelp(0, false, false, -1)
            end
            SetModelAsNoLongerNeeded(model)
        end)
    end
    return manager
end
