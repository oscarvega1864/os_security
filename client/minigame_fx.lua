-- Efectos del minijuego de instalacion: herramienta en la mano, animacion y sonidos por fase.
-- Todo es local y opcional: si un modelo, animacion o banco de sonido no existe en el juego,
-- esa parte se omite sin error. Referencias de props/animaciones: ver CHANGELOG.
OSSecurity.MinigameFx = {}

local PHASES = {
    drill = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle',
        prop = 'hei_prop_heist_drill', bone = 57005, offset = { 0.14, 0.0, -0.01 }, rotation = { 90.0, -90.0, 180.0 } },
    screw = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer',
        prop = 'prop_tool_screwdvr01', bone = 57005, offset = { 0.10, 0.02, -0.02 }, rotation = { 0.0, 0.0, 0.0 } },
    cables = { dict = 'mini@repair', clip = 'fixing_a_player' }
}
local DRILL_BANK, DRILL_SOUND, DRILL_SET = 'DLC_HEIST_FLEECA_DRILL', 'Drill', 'DLC_HEIST_FLEECA_SOUNDSET'
local FRONTEND = {
    hit = { 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS' }, miss = { 'Hack_Failed', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS' },
    connected = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' }, wrong = { 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET' }
}

function OSSecurity.MinigameFx.new()
    local fx, prop, sound, current, generation = {}, nil, nil, nil, 0
    local function load(request, loaded, name, timeout)
        request(name)
        local deadline = GetGameTimer() + (timeout or 1500)
        while not loaded(name) and GetGameTimer() < deadline do Wait(10) end
        return loaded(name)
    end
    local function stopSound()
        if sound then StopSound(sound); ReleaseSoundId(sound); sound = nil end
    end
    local function clear()
        stopSound()
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
        prop = nil
    end
    function fx.phase(name)
        local definition = PHASES[name]
        if not definition or current == name then return end
        generation = generation + 1
        local mine = generation
        current = name
        clear()
        CreateThread(function()
            local ped = PlayerPedId()
            if definition.prop then
                local model = GetHashKey(definition.prop)
                if IsModelInCdimage(model) and load(RequestModel, HasModelLoaded, model) and mine == generation then
                    local point = GetEntityCoords(ped)
                    prop = CreateObject(model, point.x, point.y, point.z + 0.2, false, false, false)
                    local o, r = definition.offset, definition.rotation
                    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, definition.bone), o[1], o[2], o[3], r[1], r[2], r[3], true, true, false, true, 1, true)
                    SetModelAsNoLongerNeeded(model)
                end
            end
            if mine ~= generation then return end
            if DoesAnimDictExist(definition.dict) and load(RequestAnimDict, HasAnimDictLoaded, definition.dict) then
                TaskPlayAnim(ped, definition.dict, definition.clip, 3.0, 3.0, -1, 1, 0.0, false, false, false)
                RemoveAnimDict(definition.dict)
            end
        end)
    end
    -- Taladro: sonido mientras se mantiene pulsado.
    function fx.drilling(active)
        if current ~= 'drill' then return end
        if not active then stopSound(); return end
        if sound or not prop then return end
        CreateThread(function()
            if not RequestScriptAudioBank(DRILL_BANK, false) then Wait(100); if not RequestScriptAudioBank(DRILL_BANK, false) then return end end
            if current ~= 'drill' or sound or not prop then return end
            sound = GetSoundId()
            PlaySoundFromEntity(sound, DRILL_SOUND, prop, DRILL_SET, true, 0)
        end)
    end
    function fx.cue(name)
        local entry = FRONTEND[name]
        if entry then PlaySoundFrontend(-1, entry[1], entry[2], true) end
    end
    function fx.start() fx.phase('drill') end
    function fx.stop()
        generation = generation + 1
        current = nil
        clear()
        ClearPedTasks(PlayerPedId())
        ReleaseNamedScriptAudioBank(DRILL_BANK)
    end
    return fx
end
