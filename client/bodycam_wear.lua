-- Bodycam puesta: mientras esta encendida (/bodycam o "Usar" el objeto os_bodycam) se ve una camarita en el pecho
-- del vigilante. El objeto lo crea su propio cliente (en red, para que lo vean los demas) y se quita al apagarla,
-- al morir, al cambiar de personaje o al parar el recurso. Es solo visual: quien graba lo decide el servidor.
local prop = nil
local function remove()
    if prop and DoesEntityExist(prop) then DetachEntity(prop, true, false); DeleteEntity(prop) end
    prop = nil
end
local function wear()
    remove()
    local config = OSSecurity.SharedGameplay.BodycamWear
    if not config or not config.Model then return end
    local model = GetHashKey(config.Model)
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local limit = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < limit do Wait(10) end
    if not HasModelLoaded(model) then return end
    local ped = PlayerPedId()
    local here = GetEntityCoords(ped)
    prop = CreateObject(model, here.x, here.y, here.z + 0.5, true, true, false)
    SetEntityCollision(prop, false, false)
    local o, r = config.Offset, config.Rotation
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, config.Bone), o[1], o[2], o[3], r[1], r[2], r[3], true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

local on = false
AddEventHandler('os_security:bodycamState', function(state)
    on = state == true
    if on then wear() else remove() end
end)
-- Si el personaje cambia de modelo o muere, se vuelve a poner (o se quita) sola.
CreateThread(function()
    local lastPed = 0
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if on and (ped ~= lastPed or not (prop and DoesEntityExist(prop))) and not IsEntityDead(ped) then wear() end
        if prop and IsEntityDead(ped) then remove() end
        lastPed = ped
    end
end)
AddEventHandler('onResourceStop', function(name) if name == GetCurrentResourceName() then remove() end end)

-- Ajuste fino de la posicion (solo en tu pantalla): /bodycamajuste x y z rx ry rz
RegisterCommand('bodycamajuste', function(_, args)
    local values = {}
    for i = 1, 6 do values[i] = tonumber(args[i]) end
    if not values[6] then
        TriggerEvent('chat:addMessage', { args = { 'Bodycam', 'Uso: /bodycamajuste x y z rx ry rz (con la bodycam encendida)' } })
        return
    end
    local config = OSSecurity.SharedGameplay.BodycamWear
    config.Offset = { values[1], values[2], values[3] }
    config.Rotation = { values[4], values[5], values[6] }
    if on then wear() end
    TriggerEvent('chat:addMessage', { args = { 'Bodycam', ('Offset = { %s, %s, %s }, Rotation = { %s, %s, %s }'):format(table.unpack(values)) } })
end, false)
