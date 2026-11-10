-- Vista en directo de una camara CCTV instalada (desde la tablet). La pantalla pasa a una camara de
-- juego en el montaje, con filtro de videovigilancia (y ruido si la optica esta gastada) y el HUD de
-- web/live.js. Controles: raton o flechas para girar, rueda o + / - para zoom, Q / E camara anterior /
-- siguiente, Retroceso o Esc para salir. El personaje queda quieto mientras se mira; recibir dano o
-- morir corta la vista. Cada 20 s se revalida con el servidor (acceso y senal).
OSSecurity.ClientLive = {}

local TURN, LOOK, ZOOM = 70.0, 4.5, 4.0         -- grados/s con flechas, sensibilidad del raton, grados de fov por paso
local FOV_MIN, FOV_MAX, FOV_START = 20.0, 75.0, 60.0
local YAW_RANGE, PITCH_MIN, PITCH_MAX = 80.0, -85.0, 35.0
local CONTROLS = { left = 174, right = 175, up = 172, down = 173, lookX = 1, lookY = 2, wheelUp = 15, wheelDown = 14,
    prev = 44, next = 38, back = 177, escape = 200, zoomIn = 96, zoomOut = 97 }

-- Encuadre inicial a partir de la normal del montaje: en pared mira hacia fuera y algo hacia abajo; en
-- techo, hacia abajo; en suelo, algo hacia arriba. Sin normal se usa el giro del dispositivo.
function OSSecurity.ClientLive.frame(feed)
    local p, n, r = feed.position, feed.normal, feed.rotation or { x = 0, y = 0, z = 0 }
    if type(n) ~= 'table' then
        return { x = p.x, y = p.y, z = p.z - 0.1 }, (r.z or 0) % 360, -15.0
    end
    if n.z <= -0.7 then return { x = p.x + n.x * 0.25, y = p.y + n.y * 0.25, z = p.z + n.z * 0.25 }, (r.z or 0) % 360, -70.0 end
    if n.z >= 0.7 then return { x = p.x + n.x * 0.4, y = p.y + n.y * 0.4, z = p.z + n.z * 0.4 }, (r.z or 0) % 360, 15.0 end
    local yaw = math.deg(math.atan(-n.x, n.y)) % 360
    return { x = p.x + n.x * 0.35, y = p.y + n.y * 0.35, z = p.z - 0.1 }, yaw, -18.0
end

local function wrap(angle) return (angle + 180.0) % 360.0 - 180.0 end

function OSSecurity.ClientLive.new(options)
    local live = { active = false }
    local cam, feed, generation = nil, nil, 0
    local baseYaw, yaw, pitch, fov = 0.0, 0.0, 0.0, FOV_START
    -- Teclas + y - (las mismas del tamano de zona, client/anchor.lua): zoom mientras se mira.
    OSSecurity.ClientLive.zoom = function(step)
        if live.active then fov = math.max(FOV_MIN, math.min(FOV_MAX, fov - step * ZOOM)) end
    end

    local function effects(noise)
        SetTimecycleModifier('CAMERA_secuirity')
        SetTimecycleModifierStrength(1.0)
        if noise and noise > 0 then
            SetExtraTimecycleModifier('CAMERA_secuirity_FUZZ')
            SetExtraTimecycleModifierStrength(math.min(1.0, noise + 0.2))
        else ClearExtraTimecycleModifier() end
    end
    local function aim(data)
        feed = data
        local position
        position, baseYaw, pitch = OSSecurity.ClientLive.frame(data)
        yaw, fov = baseYaw, FOV_START
        SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(position.x, position.y, position.z)
        if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, pitch, 0.0, yaw, fov, true, 2)
        RenderScriptCams(true, false, 0, true, true)
        effects(data.noise)
        options.send({ type = 'live', action = 'show', data = { displayId = data.displayId, site = data.site, noise = data.noise,
            index = data.index, total = data.cameras and #data.cameras or 1 }, text = OSSecurity.Brand.Text.live })
    end
    function live.stop(message, kind)
        if not live.active then return end
        live.active = false
        generation = generation + 1
        if cam and DoesCamExist(cam) then RenderScriptCams(false, false, 0, true, true); DestroyCam(cam, false) end
        cam, feed = nil, nil
        ClearFocus()
        ClearTimecycleModifier()
        ClearExtraTimecycleModifier()
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        DisplayRadar(true)
        options.send({ type = 'live', action = 'hide' })
        if message then OSSecurity.Notify(message, kind or 'info') end
        options.exit()
    end
    -- Cambiar de camara o revalidar: el servidor da el encuadre nuevo o el motivo de no tener senal.
    local function load(deviceId, retarget)
        local mine = generation
        options.request(deviceId, function(response)
            if not live.active or mine ~= generation then return end
            -- Otra peticion en curso (p. ej. cambio de camara y revalidacion a la vez): se reintenta luego.
            if not response.ok and response.error == OSSecurity.Brand.Text.loading then return end
            if not response.ok or type(response.data) ~= 'table' then
                live.stop(response.error or OSSecurity.Brand.Text.live.lost, 'error'); return
            end
            if retarget then DoScreenFadeOut(150); Wait(160); aim(response.data); DoScreenFadeIn(250)
            else feed.cameras, feed.index, feed.noise = response.data.cameras, response.data.index, response.data.noise; effects(feed.noise) end
        end)
    end
    function live.start(data)
        if live.active then live.stop() end
        live.active = true
        generation = generation + 1
        local mine = generation
        local ped = PlayerPedId()
        local health = GetEntityHealth(ped)
        FreezeEntityPosition(ped, true)
        DisplayRadar(false)
        DoScreenFadeOut(150)
        CreateThread(function()
            Wait(160)
            if not live.active or mine ~= generation then DoScreenFadeIn(150); return end
            aim(data)
            DoScreenFadeIn(300)
            local last, refreshed = GetGameTimer(), GetGameTimer()
            while live.active and mine == generation do
                Wait(0)
                local now = GetGameTimer(); local dt = math.min(0.1, (now - last) / 1000); last = now
                DisableAllControlActions(0)
                EnableControlAction(0, 249, true) -- pulsar para hablar
                HideHudAndRadarThisFrame()
                ped = PlayerPedId()
                if IsEntityDead(ped) or GetEntityHealth(ped) < health then live.stop(OSSecurity.Brand.Text.live.interrupted, 'warning'); break end
                if IsDisabledControlJustPressed(0, CONTROLS.back) or IsDisabledControlJustPressed(0, CONTROLS.escape) then live.stop(); break end
                local turnX = (IsDisabledControlPressed(0, CONTROLS.right) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.left) and 1 or 0)
                local turnY = (IsDisabledControlPressed(0, CONTROLS.up) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.down) and 1 or 0)
                local zoomFactor = fov / FOV_START
                yaw = yaw - (turnX * TURN * dt + GetDisabledControlNormal(0, CONTROLS.lookX) * LOOK) * zoomFactor
                pitch = pitch + (turnY * TURN * dt - GetDisabledControlNormal(0, CONTROLS.lookY) * LOOK) * zoomFactor
                yaw = baseYaw + math.max(-YAW_RANGE, math.min(YAW_RANGE, wrap(yaw - baseYaw)))
                pitch = math.max(PITCH_MIN, math.min(PITCH_MAX, pitch))
                if IsDisabledControlJustPressed(0, CONTROLS.wheelUp) or IsDisabledControlJustPressed(0, CONTROLS.zoomIn) then fov = fov - ZOOM end
                if IsDisabledControlJustPressed(0, CONTROLS.wheelDown) or IsDisabledControlJustPressed(0, CONTROLS.zoomOut) then fov = fov + ZOOM end
                fov = math.max(FOV_MIN, math.min(FOV_MAX, fov))
                if cam then SetCamRot(cam, pitch, 0.0, yaw, 2); SetCamFov(cam, fov) end
                local cameras = feed and feed.cameras or {}
                if #cameras > 1 then
                    local step = IsDisabledControlJustPressed(0, CONTROLS.next) and 1 or (IsDisabledControlJustPressed(0, CONTROLS.prev) and -1 or 0)
                    if step ~= 0 then
                        local index = ((feed.index or 1) - 1 + step) % #cameras + 1
                        load(cameras[index].id, true)
                    end
                end
                if now - refreshed > 20000 and feed then refreshed = now; load(feed.id, false) end
            end
        end)
    end
    return live
end
