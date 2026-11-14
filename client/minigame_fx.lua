-- Efectos del minijuego de instalacion: herramienta en la mano, animacion por fase, camara cercana, polvo y
-- chispas, sonidos y un paso final (colocar o quitar el equipo con el en la mano).
-- Todo es local y opcional: si un modelo, animacion, efecto de particulas o banco de sonido no existe en el juego,
-- esa parte se omite sin error.
OSSecurity.MinigameFx = {}

local PHASES = {
    drill = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle',
        prop = 'hei_prop_heist_drill', bone = 57005, offset = { 0.14, 0.0, -0.01 }, rotation = { 90.0, -90.0, 180.0 } },
    screw = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer',
        prop = 'prop_tool_screwdvr01', bone = 57005, offset = { 0.10, 0.02, -0.02 }, rotation = { 0.0, 0.0, 0.0 } },
    cables = { dict = 'mini@repair', clip = 'fixing_a_player' }
}
-- Paso final: el equipo en la mano mientras se coloca (montar) o se retira (desmontar).
local FINALE = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', bone = 57005,
    offset = { 0.12, 0.04, -0.04 }, rotation = { -70.0, 0.0, 0.0 }, milliseconds = 1600, prop = 'prop_cctv_cam_01a' }
local DRILL_BANK, DRILL_SOUND, DRILL_SET = 'DLC_HEIST_FLEECA_DRILL', 'Drill', 'DLC_HEIST_FLEECA_SOUNDSET'
local PIN_BREAK = 'Drill_Pin_Break' -- golpe seco de la broca al resbalar (mismo banco)
-- Particulas: polvo de la broca mientras perfora y chispas si se calienta o resbala.
local DUST = { asset = 'fm_mission_controler', name = 'scr_drill_debris', offset = { 0.0, -0.55, 0.01 }, rotation = { 90.0, 90.0, 90.0 }, scale = 0.8 }
local SPARKS = { asset = 'core', name = 'ent_brk_sparking_wires', offset = { 0.0, -0.5, 0.0 }, scale = 0.6 }
local FRONTEND = {
    hit = { 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS' }, miss = { 'Hack_Failed', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS' },
    connected = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' }, wrong = { 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    placed = { 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET' }, picked = { 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET' }
}

function OSSecurity.MinigameFx.new()
    local fx, prop, sound, dust, current, generation, cam, extra = {}, nil, nil, nil, nil, 0, nil, {}
    local function load(request, loaded, name, timeout)
        request(name)
        local deadline = GetGameTimer() + (timeout or 1500)
        while not loaded(name) and GetGameTimer() < deadline do Wait(10) end
        return loaded(name)
    end
    local function stopSound()
        if sound then StopSound(sound); ReleaseSoundId(sound); sound = nil end
    end
    local function stopDust()
        if dust then StopParticleFxLooped(dust, false); dust = nil end
    end
    local function clear()
        stopSound(); stopDust()
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
        prop = nil
    end
    local function ptfx(definition)
        if not definition or not prop or not DoesEntityExist(prop) then return false end
        if not HasNamedPtfxAssetLoaded(definition.asset) and not load(RequestNamedPtfxAsset, HasNamedPtfxAssetLoaded, definition.asset, 1000) then return false end
        UseParticleFxAssetNextCall(definition.asset)
        return true
    end
    local function sparks()
        CreateThread(function()
            if not ptfx(SPARKS) then return end
            local o = SPARKS.offset
            StartParticleFxNonLoopedOnEntity(SPARKS.name, prop, o[1], o[2], o[3], 0.0, 0.0, 0.0, SPARKS.scale, false, false, false)
        end)
    end
    local function holdProp(model, definition, mine)
        local ped = PlayerPedId()
        local hash = GetHashKey(model)
        if not IsModelInCdimage(hash) or not load(RequestModel, HasModelLoaded, hash) or mine ~= generation then return end
        local point = GetEntityCoords(ped)
        prop = CreateObject(hash, point.x, point.y, point.z + 0.2, false, false, false)
        SetEntityCollision(prop, false, false)
        local o, r = definition.offset, definition.rotation
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, definition.bone), o[1], o[2], o[3], r[1], r[2], r[3], true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(hash)
    end
    local function play(definition, mine)
        if mine ~= generation then return end
        if DoesAnimDictExist(definition.dict) and load(RequestAnimDict, HasAnimDictLoaded, definition.dict) then
            TaskPlayAnim(PlayerPedId(), definition.dict, definition.clip, 3.0, 3.0, -1, 1, 0.0, false, false, false)
            RemoveAnimDict(definition.dict)
        end
    end
    local function loopSound(entity)
        if sound or not entity then return end
        CreateThread(function()
            if not RequestScriptAudioBank(DRILL_BANK, false) then Wait(100); if not RequestScriptAudioBank(DRILL_BANK, false) then return end end
            if sound or not prop then return end
            sound = GetSoundId()
            PlaySoundFromEntity(sound, DRILL_SOUND, prop, DRILL_SET, true, 0)
        end)
    end

    -- Camara cercana de lado: encuadra al personaje y el punto de trabajo (si se conoce y esta cerca).
    local function cameraOn()
        if cam then return end
        local ped = PlayerPedId(); local p = GetEntityCoords(ped); local f = GetEntityForwardVector(ped)
        local target = vector3(p.x + f.x * 0.7, p.y + f.y * 0.7, p.z + 0.45)
        local focus = extra.focus
        if type(focus) == 'table' and type(focus.x) == 'number' and type(focus.y) == 'number' and type(focus.z) == 'number'
            and (focus.x - p.x) ^ 2 + (focus.y - p.y) ^ 2 + (focus.z - p.z) ^ 2 < 16.0 then
            target = vector3((focus.x + p.x) / 2, (focus.y + p.y) / 2, (focus.z + p.z + 0.5) / 2)
        end
        local right = vector3(f.y, -f.x, 0.0)
        local position = vector3(p.x + right.x * 1.4 - f.x * 0.3, p.y + right.y * 1.4 - f.y * 0.3, p.z + 0.65)
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, 0.0, 0.0, 0.0, 50.0, false, 2)
        PointCamAtCoord(cam, target.x, target.y, target.z)
        SetCamActive(cam, true)
        RenderScriptCams(true, true, 600, true, true)
    end
    local function cameraOff()
        if not cam then return end
        RenderScriptCams(false, true, 600, true, true)
        DestroyCam(cam, false); cam = nil
    end

    function fx.phase(name)
        local definition = PHASES[name]
        if not definition or current == name then return end
        generation = generation + 1
        local mine = generation
        current = name
        clear()
        CreateThread(function()
            if definition.prop then holdProp(definition.prop, definition, mine) end
            play(definition, mine)
        end)
    end
    -- Taladro: sonido y polvo mientras se mantiene pulsado.
    function fx.drilling(active)
        if current ~= 'drill' then return end
        if not active then stopSound(); stopDust(); return end
        if not prop then return end
        loopSound(prop)
        if not dust then
            CreateThread(function()
                if not ptfx(DUST) or dust or current ~= 'drill' then return end
                local o, r = DUST.offset, DUST.rotation
                dust = StartParticleFxLoopedOnEntity(DUST.name, prop, o[1], o[2], o[3], r[1], r[2], r[3], DUST.scale, false, false, false)
                if dust == 0 then dust = nil end
            end)
        end
    end
    -- Destornillador electrico: zumbido mientras se gira un tornillo.
    function fx.screwing(active)
        if current ~= 'screw' then return end
        if active then loopSound(prop) else stopSound() end
    end
    function fx.cue(name)
        if current == 'drill' and (name == 'miss' or name == 'hot') then
            sparks()
            if name == 'miss' then stopSound(); stopDust(); PlaySoundFrontend(-1, PIN_BREAK, DRILL_SET, true) end
            return
        end
        local entry = FRONTEND[name]
        if entry then PlaySoundFrontend(-1, entry[1], entry[2], true) end
    end
    -- extra: { focus = posicion del montaje, prop = modelo del equipo para el paso final }.
    function fx.start(options)
        extra = type(options) == 'table' and options or {}
        cameraOn(); fx.phase('drill')
    end
    function fx.stop()
        generation = generation + 1
        current = nil
        clear(); cameraOff()
        ClearPedTasks(PlayerPedId())
        ReleaseNamedScriptAudioBank(DRILL_BANK)
        if HasNamedPtfxAssetLoaded(DUST.asset) then RemoveNamedPtfxAsset(DUST.asset) end
    end
    -- Exito: el equipo en la mano un momento (colocandolo o retirandolo) y despues todo vuelve a la normalidad.
    function fx.finale(mode)
        generation = generation + 1
        local mine = generation
        current = 'finale'
        clear()
        local model = extra.prop ~= false and (type(extra.prop) == 'string' and extra.prop or FINALE.prop) or nil -- false: sin objeto (arco)
        CreateThread(function()
            if model then holdProp(model, FINALE, mine) end
            play(FINALE, mine)
            local entry = FRONTEND[mode == 'remove' and 'picked' or 'placed']
            PlaySoundFrontend(-1, entry[1], entry[2], true)
            Wait(FINALE.milliseconds)
            if mine == generation then fx.stop() end
        end)
    end
    return fx
end
