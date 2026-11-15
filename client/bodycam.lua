-- Vista en directo de una bodycam (G6 Operations > Bodycams): la camara del juego va sujeta al pecho del
-- vigilante y gira con el. Mismo HUD y filtro que las camaras CCTV (web/live.js). Controles: raton o flechas para
-- mirar un poco alrededor, Q / E otra bodycam, Retroceso o Esc para salir. El servidor amplia el radio de
-- visibilidad de quien mira para que el vigilante exista en su equipo; si no aparece en unos segundos, sin senal.
OSSecurity.ClientBodycam = {}

local LOOK, YAW_RANGE, PITCH_MIN, PITCH_MAX, FOV = 4.0, 60.0, -40.0, 25.0, 70.0
local OFFSET = { x = 0.0, y = 0.32, z = 0.45 } -- delante del pecho, respecto al centro del personaje
local CONTROLS = { lookX = 1, lookY = 2, left = 174, right = 175, up = 172, down = 173, prev = 44, next = 38, back = 177, escape = 200 }

function OSSecurity.ClientBodycam.new(options)
    local bodycam = { active = false }
    local cam, feed, generation = nil, nil, 0
    local yaw, pitch = 0.0, -5.0
    local T = function() return OSSecurity.Brand.Text.bodycams end

    local function targetPed(target)
        local index = GetPlayerFromServerId(target)
        if index == -1 then return nil end
        local ped = GetPlayerPed(index)
        return ped ~= 0 and DoesEntityExist(ped) and ped or nil
    end
    local function hud(data)
        options.send({ type = 'live', action = 'show', text = OSSecurity.Brand.Text.live, data = {
            displayId = ('%s · %s'):format(T().label, data.name or ''), site = T().recording, title = ('%s · %s'):format(T().label, data.name or ''),
            index = data.index, total = data.cameras and #data.cameras or 1, noise = 0, help = T().help2 } })
    end
    function bodycam.stop(message, kind)
        if not bodycam.active then return end
        bodycam.active = false
        generation = generation + 1
        if cam and DoesCamExist(cam) then RenderScriptCams(false, false, 0, true, true); DestroyCam(cam, false) end
        cam, feed = nil, nil
        ClearFocus(); ClearTimecycleModifier(); ClearExtraTimecycleModifier()
        FreezeEntityPosition(PlayerPedId(), false)
        DisplayRadar(true)
        TriggerEvent('os_security:cameraView', false)
        options.send({ type = 'live', action = 'hide' })
        if message then OSSecurity.Notify(message, kind or 'info') end
        options.exit()
    end
    -- Espera a que el vigilante exista en este equipo y monta la camara en su pecho.
    local function attach(data, mine)
        feed = data
        if type(data.position) == 'table' then SetFocusPosAndVel(data.position.x + 0.0, data.position.y + 0.0, data.position.z + 0.0, 0.0, 0.0, 0.0) end
        local deadline, ped = GetGameTimer() + 6000, nil
        while bodycam.active and mine == generation and GetGameTimer() < deadline do
            ped = targetPed(data.target)
            if ped then break end
            Wait(100)
        end
        if not bodycam.active or mine ~= generation then return false end
        if not ped then bodycam.stop(T().noSignal, 'error'); return false end
        SetFocusEntity(ped)
        if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        AttachCamToEntity(cam, ped, OFFSET.x, OFFSET.y, OFFSET.z, true)
        SetCamFov(cam, FOV)
        RenderScriptCams(true, false, 0, true, true)
        SetTimecycleModifier('CAMERA_secuirity'); SetTimecycleModifierStrength(0.6)
        yaw, pitch = 0.0, -5.0
        hud(data)
        return true
    end
    -- refresh: solo revalida (sin fundido) y actualiza la lista de bodycams; si no, cambia de vigilante.
    local function switch(target, refresh)
        local mine = generation
        options.request(target, function(response)
            if not bodycam.active or mine ~= generation then return end
            if not response.ok or type(response.data) ~= 'table' then
                if response.error ~= OSSecurity.Brand.Text.loading then bodycam.stop(response.error or T().lost, 'error') end
                return
            end
            if refresh then feed.cameras, feed.index = response.data.cameras, response.data.index; return end
            DoScreenFadeOut(150); Wait(160)
            attach(response.data, mine)
            DoScreenFadeIn(250)
        end)
    end
    function bodycam.start(data)
        if bodycam.active then bodycam.stop() end
        bodycam.active = true
        generation = generation + 1
        local mine = generation
        local ped = PlayerPedId()
        local health = GetEntityHealth(ped)
        FreezeEntityPosition(ped, true)
        DisplayRadar(false)
        TriggerEvent('os_security:cameraView', true)
        OSSecurity.Notify(T().waiting, 'info')
        DoScreenFadeOut(150)
        CreateThread(function()
            Wait(160)
            if not attach(data, mine) then DoScreenFadeIn(200); return end
            DoScreenFadeIn(300)
            local refreshed = GetGameTimer()
            while bodycam.active and mine == generation do
                Wait(0)
                DisableAllControlActions(0)
                EnableControlAction(0, 249, true) -- pulsar para hablar
                HideHudAndRadarThisFrame()
                local me = PlayerPedId()
                if IsEntityDead(me) or GetEntityHealth(me) < health then bodycam.stop(OSSecurity.Brand.Text.live.interrupted, 'warning'); break end
                if IsDisabledControlJustPressed(0, CONTROLS.back) or IsDisabledControlJustPressed(0, CONTROLS.escape) then bodycam.stop(); break end
                local target = feed and targetPed(feed.target)
                if not target then bodycam.stop(T().lost, 'error'); break end
                local turnX = (IsDisabledControlPressed(0, CONTROLS.right) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.left) and 1 or 0)
                local turnY = (IsDisabledControlPressed(0, CONTROLS.up) and 1 or 0) - (IsDisabledControlPressed(0, CONTROLS.down) and 1 or 0)
                yaw = math.max(-YAW_RANGE, math.min(YAW_RANGE, yaw - turnX * 1.2 - GetDisabledControlNormal(0, CONTROLS.lookX) * LOOK))
                pitch = math.max(PITCH_MIN, math.min(PITCH_MAX, pitch + turnY * 1.2 - GetDisabledControlNormal(0, CONTROLS.lookY) * LOOK))
                if cam then SetCamRot(cam, pitch, 0.0, GetEntityHeading(target) + yaw, 2) end
                local cameras = feed and feed.cameras or {}
                if #cameras > 1 then
                    local step = IsDisabledControlJustPressed(0, CONTROLS.next) and 1 or (IsDisabledControlJustPressed(0, CONTROLS.prev) and -1 or 0)
                    if step ~= 0 then switch(cameras[((feed.index or 1) - 1 + step) % #cameras + 1].id) end
                end
                -- Revalida acceso y que sigue encendida.
                if GetGameTimer() - refreshed > 15000 and feed then refreshed = GetGameTimer(); switch(feed.target, true) end
            end
        end)
    end
    return bodycam
end
