-- Control de acceso (cliente): arcos detectores en el mundo, aviso al cruzarlos, colocacion del arco y cacheo.
-- El servidor decide si pita, quien puede cachear y que se retiene; aqui solo se dibuja, se detecta el cruce
-- y se informa de las armas que lleva el propio ped (no hay otra fuente de armas en este servidor).
local T = OSSecurity.Brand.Text.checkpoint
local detectors = {}      -- id -> { id, x, y, z, h, company }
local props = {}          -- id -> entidad local
local model = nil         -- primer modelo de arco que exista; nil = arco dibujado con marcadores
local flash = {}          -- id -> { untilAt, alarm }
local sides = {}          -- id -> lado del arco en el que estaba el jugador
local handsUp = false
local MODELS = { 'ch_prop_ch_metal_detector_01a', 'ch_prop_ch_metal_detector_01b' }
local HANDS = { dict = 'missminuteman_1ig_2', clip = 'handsup_base' }

local function notify(text, kind) if OSSecurity.Notify then OSSecurity.Notify(text, kind or 'info') end end
local function pickModel()
    for _, name in ipairs(MODELS) do
        local hash = GetHashKey(name)
        if IsModelInCdimage(hash) and IsModelValid(hash) then return hash, name end
    end
end
CreateThread(function() model = pickModel() end)
RegisterCommand('arcomodelo', function()
    local _, name = pickModel()
    notify(name and ('Arco detector: modelo %s.'):format(name) or 'Arco detector: sin modelo en este juego, se dibuja con marcadores.', 'info')
end, false)

local function axes(h)
    local r = math.rad(h)
    return vector2(-math.sin(r), math.cos(r)), vector2(math.cos(r), math.sin(r)) -- adelante (paso), lado (ancho)
end
local function despawn(id)
    if props[id] and DoesEntityExist(props[id]) then DeleteEntity(props[id]) end
    props[id], sides[id], flash[id] = nil, nil, nil
end

RegisterNetEvent('os_security:checkpoint:detectors', function(list)
    if source ~= 65535 or type(list) ~= 'table' then return end
    local keep = {}
    for _, entry in ipairs(list) do
        if type(entry) == 'table' and type(entry.id) == 'string' and type(entry.x) == 'number' then keep[entry.id] = entry end
    end
    for id in pairs(detectors) do if not keep[id] then despawn(id) end end
    detectors = keep
end)
CreateThread(function()
    Wait(3000)
    TriggerServerEvent('os_security:checkpoint:list')
end)

-- Armas que lleva el jugador (solo las de la lista compartida).
local function myWeapons()
    local ped, result = PlayerPedId(), {}
    for name in pairs(OSSecurity.Weapons.List) do
        local hash = GetHashKey(name)
        if HasPedGotWeapon(ped, hash, false) then result[#result + 1] = { name = name, ammo = GetAmmoInPedWeapon(ped, hash) } end
    end
    return result
end

-- Props cercanos (cada segundo) y cruce de arcos (cada fotograma solo si hay uno cerca).
CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        for id, detector in pairs(detectors) do
            local d = #(here - vector3(detector.x, detector.y, detector.z))
            if d < 80.0 and model and not props[id] then
                RequestModel(model)
                local deadline = GetGameTimer() + 3000
                while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
                if HasModelLoaded(model) and detectors[id] then
                    local entity = CreateObjectNoOffset(model, detector.x, detector.y, detector.z, false, false, false)
                    SetEntityHeading(entity, detector.h + 0.0); PlaceObjectOnGroundProperly(entity); FreezeEntityPosition(entity, true)
                    props[id] = entity
                end
            elseif d >= 100.0 and props[id] then
                if DoesEntityExist(props[id]) then DeleteEntity(props[id]) end
                props[id] = nil
            end
        end
        Wait(1000)
    end
end)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local here = GetEntityCoords(ped)
        local near = false
        for id, detector in pairs(detectors) do
            local center = vector3(detector.x, detector.y, detector.z)
            local d = #(here - center)
            if d < 25.0 then
                near = true
                local forward, side = axes(detector.h)
                -- Sin modelo: dos postes y un travesano con marcadores.
                if not model then
                    local tops = {}
                    for index, offset in ipairs({ -0.55, 0.55 }) do
                        local p = center + vector3(side.x * offset, side.y * offset, 0.0)
                        DrawMarker(1, p.x, p.y, p.z - 1.0, 0, 0, 0, 0, 0, 0, 0.12, 0.12, 2.2, 190, 195, 200, 220, false, false, 2, false, nil, nil, false)
                        tops[index] = p + vector3(0.0, 0.0, 1.2)
                    end
                    DrawLine(tops[1].x, tops[1].y, tops[1].z, tops[2].x, tops[2].y, tops[2].z, 190, 195, 200, 255)
                end
                local glow = flash[id]
                if glow and GetGameTimer() < glow.untilAt then
                    local r, g = glow.alarm and 255 or 40, glow.alarm and 30 or 230
                    DrawLightWithRange(center.x, center.y, center.z + 1.3, r, g, 40, 3.0, 6.0)
                end
                -- Cruce: cambio de lado sobre el eje de paso dentro del hueco del arco.
                local rel = vector2(here.x - center.x, here.y - center.y)
                local along, across = rel.x * forward.x + rel.y * forward.y, rel.x * side.x + rel.y * side.y
                if math.abs(across) < 0.6 and math.abs(here.z - center.z) < 2.0 and math.abs(along) < 1.2 and not IsPedInAnyVehicle(ped, false) then
                    local now = along >= 0
                    if sides[id] ~= nil and sides[id] ~= now then TriggerServerEvent('os_security:checkpoint:pass', id, myWeapons()) end
                    sides[id] = now
                else sides[id] = nil end
            end
        end
        Wait(near and 0 or 500)
    end
end)

-- Pitido y luz para quien esta cerca: tres pitidos graves con metal; uno agudo y luz verde sin metal.
RegisterNetEvent('os_security:checkpoint:detector', function(data)
    if source ~= 65535 or type(data) ~= 'table' or not detectors[data.id] then return end
    local detector = detectors[data.id]
    local d = #(GetEntityCoords(PlayerPedId()) - vector3(detector.x, detector.y, detector.z))
    local volume = math.max(0.0, 0.1 * (1.0 - d / 30.0))
    flash[data.id] = { untilAt = GetGameTimer() + 2200, alarm = data.alarm == true }
    if volume <= 0 then return end
    if data.alarm then
        CreateThread(function()
            for _ = 1, 3 do SendNUIMessage({ type = 'beep', frequency = 880, duration = 0.28, volume = volume }); Wait(380) end
        end)
    else SendNUIMessage({ type = 'beep', frequency = 1900, duration = 0.12, volume = volume * 0.6 }) end
end)

-- Colocar el arco (objeto os_metal_detector): fantasma delante, rueda gira, E coloca, Retroceso cancela.
local placing = false
RegisterNetEvent('os_security:checkpoint:placeBegin', function(reach)
    if source ~= 65535 or placing then return end
    placing = true
    CreateThread(function()
        local ped = PlayerPedId()
        local heading = GetEntityHeading(ped)
        local ghost
        if model then
            RequestModel(model)
            local deadline = GetGameTimer() + 3000
            while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
            if HasModelLoaded(model) then
                local here = GetEntityCoords(ped)
                ghost = CreateObjectNoOffset(model, here.x, here.y, here.z, false, false, false)
                SetEntityAlpha(ghost, 150, false); SetEntityCollision(ghost, false, false); FreezeEntityPosition(ghost, true)
            end
        end
        local distance = math.min(2.0, tonumber(reach) or 2.0)
        while placing do
            Wait(0)
            ped = PlayerPedId()
            DisableControlAction(0, 14, true); DisableControlAction(0, 15, true); DisableControlAction(0, 16, true); DisableControlAction(0, 17, true)
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            if IsDisabledControlPressed(0, 14) or IsDisabledControlPressed(0, 16) then heading = heading + 3.0 end
            if IsDisabledControlPressed(0, 15) or IsDisabledControlPressed(0, 17) then heading = heading - 3.0 end
            local here, h = GetEntityCoords(ped), math.rad(GetEntityHeading(ped))
            local spot = here + vector3(-math.sin(h) * distance, math.cos(h) * distance, 0.0)
            local found, ground = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.0, false)
            local z = found and ground or (here.z - 1.0)
            if ghost then SetEntityCoordsNoOffset(ghost, spot.x, spot.y, z, false, false, false); SetEntityHeading(ghost, heading % 360)
            else
                local forward, side = axes(heading)
                for _, offset in ipairs({ -0.55, 0.55 }) do
                    DrawMarker(1, spot.x + side.x * offset, spot.y + side.y * offset, z, 0, 0, 0, 0, 0, 0, 0.12, 0.12, 2.2, 120, 200, 255, 160, false, false, 2, false, nil, nil, false)
                end
            end
            BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(T.placeHelp); EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustPressed(0, 38) then
                TriggerServerEvent('os_security:checkpoint:place', { x = spot.x, y = spot.y, z = z + 1.0, h = heading % 360 })
                placing = false
            elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 200) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
                placing = false
            end
        end
        if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    end)
end)

-- Cacheo -----------------------------------------------------------------------------------------------
-- /cacheo: a la persona mas cercana que tengas delante (2 m).
local function facingPlayer()
    local ped = PlayerPedId()
    local here = GetEntityCoords(ped)
    local h = math.rad(GetEntityHeading(ped))
    local forward = vector2(-math.sin(h), math.cos(h))
    local best, bestDistance
    for _, index in ipairs(GetActivePlayers()) do
        if index ~= PlayerId() then
            local other = GetPlayerPed(index)
            local there = GetEntityCoords(other)
            local d = #(here - there)
            local dot = (there.x - here.x) * forward.x + (there.y - here.y) * forward.y
            if d <= 2.2 and dot > 0 and (not bestDistance or d < bestDistance) then best, bestDistance = GetPlayerServerId(index), d end
        end
    end
    return best
end
RegisterCommand('cacheo', function()
    local target = facingPlayer()
    if not target then notify(T.noTarget, 'warning'); return end
    TriggerServerEvent('os_security:checkpoint:frisk', target)
end, false)
TriggerEvent('chat:addSuggestion', '/cacheo', 'Pedir permiso para cachear a la persona que tienes delante (empleado de servicio)')
TriggerEvent('chat:addSuggestion', '/custodia', 'Recoger los objetos que te retuvieron (en el mismo sitio)')
TriggerEvent('chat:addSuggestion', '/arco', 'Arco detector: /arco recoger (junto a un arco de tu empresa)')

local consenting = false
RegisterNetEvent('os_security:checkpoint:friskAsk', function(data)
    if source ~= 65535 or type(data) ~= 'table' then return end
    consenting = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'friskAsk', data = data, text = T })
end)
RegisterNUICallback('friskConsent', function(body, callback)
    callback({ ok = true })
    if not consenting then return end
    consenting = false
    SetNuiFocus(false, false)
    local accept = type(body) == 'table' and body.accept == true
    TriggerServerEvent('os_security:checkpoint:answer', accept, accept and myWeapons() or nil)
end)

-- El cacheado: manos arriba hasta que termine.
local function stopHands()
    if not handsUp then return end
    handsUp = false
    StopAnimTask(PlayerPedId(), HANDS.dict, HANDS.clip, 1.0)
end
RegisterNetEvent('os_security:checkpoint:friskBegin', function()
    if source ~= 65535 then return end
    handsUp = true
    CreateThread(function()
        RequestAnimDict(HANDS.dict)
        local deadline = GetGameTimer() + 2000
        while not HasAnimDictLoaded(HANDS.dict) and GetGameTimer() < deadline do Wait(0) end
        while handsUp do
            local ped = PlayerPedId()
            if HasAnimDictLoaded(HANDS.dict) and not IsEntityPlayingAnim(ped, HANDS.dict, HANDS.clip, 3) then
                TaskPlayAnim(ped, HANDS.dict, HANDS.clip, 4.0, 4.0, -1, 49, 0.0, false, false, false)
            end
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisableControlAction(0, 21, true); DisableControlAction(0, 22, true)
            Wait(0)
        end
    end)
end)
RegisterNetEvent('os_security:checkpoint:friskEnd', function() if source == 65535 then stopHands() end end)

-- El vigilante: panel de cacheo por zonas.
local frisking = false
RegisterNetEvent('os_security:checkpoint:friskOpen', function(data)
    if source ~= 65535 or type(data) ~= 'table' then return end
    frisking = true
    TaskStartScenarioInPlace(PlayerPedId(), 'CODE_HUMAN_POLICE_INVESTIGATE', 0, true)
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'friskOpen', data = data, text = T })
end)
local function endFrisk()
    if not frisking then return end
    frisking = false
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
end
RegisterNUICallback('friskFinish', function(body, callback)
    callback({ ok = true })
    if not frisking then return end
    endFrisk()
    local retain = type(body) == 'table' and type(body.retain) == 'table' and body.retain or {}
    TriggerServerEvent('os_security:checkpoint:finish', retain)
end)
RegisterNUICallback('friskCancel', function(_, callback)
    callback({ ok = true })
    if not frisking then return end
    endFrisk()
    TriggerServerEvent('os_security:checkpoint:cancel')
end)

-- Armas retenidas y devueltas (las del ped de GTA).
RegisterNetEvent('os_security:checkpoint:removeWeapons', function(list)
    if source ~= 65535 or type(list) ~= 'table' then return end
    local ped = PlayerPedId()
    for _, name in ipairs(list) do if OSSecurity.Weapons.List[name] then RemoveWeaponFromPed(ped, GetHashKey(name)) end end
end)
RegisterNetEvent('os_security:checkpoint:giveWeapons', function(list)
    if source ~= 65535 or type(list) ~= 'table' then return end
    local ped = PlayerPedId()
    for _, weapon in ipairs(list) do
        if type(weapon) == 'table' and OSSecurity.Weapons.List[weapon.name] then GiveWeaponToPed(ped, GetHashKey(weapon.name), tonumber(weapon.ammo) or 0, false, false) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(props) do despawn(id) end
    stopHands()
    if frisking or consenting then SetNuiFocus(false, false) end
end)
