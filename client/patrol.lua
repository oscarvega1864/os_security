-- Ronda de vigilancia en curso: marca y punto en el mapa del siguiente punto de control; junto a el, E ficha.
-- El servidor decide si se ha fichado (comprueba la distancia con su posicion del jugador).
local run, blip = nil, nil
local T = function() return OSSecurity.Brand.Text.patrols end
local CHECK_KEY, NEAR, DRAW = 38, 2.5, 60.0

local function clearBlip() if blip and DoesBlipExist(blip) then RemoveBlip(blip) end; blip = nil end
RegisterNetEvent('os_security:patrol:patrolRun', function(data)
    if source ~= 65535 then return end
    clearBlip()
    if type(data) ~= 'table' or type(data.point) ~= 'table' or type(data.point.x) ~= 'number' then run = nil; return end
    run = data
    blip = AddBlipForCoord(data.point.x + 0.0, data.point.y + 0.0, data.point.z + 0.0)
    SetBlipSprite(blip, 1); SetBlipColour(blip, 2); SetBlipRoute(blip, true); SetBlipRouteColour(blip, 2)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(('%s %d/%d'):format(T().blip, data.next, data.total)); EndTextCommandSetBlipName(blip)
end)

CreateThread(function()
    local pressed = 0
    while true do
        if not run then Wait(500) else
            Wait(0)
            local p = run.point
            local here = GetEntityCoords(PlayerPedId())
            local d = #(here - vector3(p.x, p.y, p.z))
            if d < DRAW then
                DrawMarker(1, p.x, p.y, p.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.6, 120, 200, 110, 140, false, false, 2, false, nil, nil, false)
            end
            if d < NEAR then
                BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(T().help3D); EndTextCommandDisplayHelp(0, false, false, -1)
                if IsControlJustPressed(0, CHECK_KEY) and GetGameTimer() - pressed > 1000 then
                    pressed = GetGameTimer()
                    TriggerServerEvent('os_security:patrol:check')
                end
            end
        end
    end
end)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then clearBlip() end end)
TriggerEvent('chat:addSuggestion', '/ronda', 'Ronda de vigilancia: /ronda cancelar para abandonarla')
