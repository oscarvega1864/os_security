-- Mostrador de la tienda Gruppe Sechs: blip, marcador y E para abrir. El catalogo, los precios
-- que valen y la compra los decide el servidor; aqui solo se dibuja y se pide.
OSSecurity.ClientShop = {}

function OSSecurity.ClientShop.new(options)
    local config = OSSecurity.ShopConfig
    local shop = {}
    local blips = {}

    for _, location in ipairs(config.Locations) do
        if location.blip then
            local blip = AddBlipForCoord(location.x + 0.0, location.y + 0.0, location.z + 0.0)
            SetBlipSprite(blip, 52)
            SetBlipColour(blip, 2)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(location.label)
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end

    CreateThread(function()
        local lastOpen = 0
        while true do
            local ped = PlayerPedId()
            local here = GetEntityCoords(ped)
            local nearest, best
            for _, location in ipairs(config.Locations) do
                local d = #(here - vector3(location.x, location.y, location.z))
                if not best or d < best then nearest, best = location, d end
            end
            if nearest and best <= 20.0 and not IsPedInAnyVehicle(ped, false) then
                Wait(0)
                DrawMarker(29, nearest.x, nearest.y, nearest.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5,
                    140, 200, 110, 170, true, true, 2, false, nil, nil, false)
                if best <= config.Distance and not options.busy() then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(OSSecurity.Brand.Text.shop.prompt)
                    EndTextCommandDisplayHelp(0, false, false, -1)
                    if IsControlJustPressed(0, 38) and GetGameTimer() - lastOpen > 1500 then
                        lastOpen = GetGameTimer()
                        TriggerServerEvent('os_security:shop:open')
                    end
                end
            else
                Wait(750)
            end
        end
    end)

    function shop.clear()
        for _, blip in ipairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
        blips = {}
    end
    return shop
end
