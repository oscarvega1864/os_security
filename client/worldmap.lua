-- Mapa de la tablet: abre el mapa real del juego (menu de pausa, pestana Mapa) con los puntos de la tablet como
-- iconos temporales. Al cerrar el mapa se quitan los iconos y se vuelve a abrir la tablet.
-- Los puntos vienen del resumen del servidor ya filtrado por perfil; aqui solo se dibujan.
OSSecurity.ClientWorldMap = {}

local STYLE = { -- sprite y color de icono por tipo de punto
    device = { sprite = 459, colour = 2 }, order = { sprite = 402, colour = 5 },
    call = { sprite = 161, colour = 1 }, car = { sprite = 225, colour = 3 }
}
local ALERT = { triggered = true, fault = true, worn = true, maintenance = true, sounding = true }
local MAX_POINTS = 200

function OSSecurity.ClientWorldMap.new(options)
    local worldmap, blips, open = {}, {}, false
    local function clear()
        for _, blip in ipairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
        blips = {}
    end
    local function text(value, limit)
        if type(value) ~= 'string' then return nil end
        value = value:gsub('[%c<>~]', ''):sub(1, limit or 60)
        return value ~= '' and value or nil
    end
    local function add(point)
        local style = STYLE[point.kind]
        if not style or type(point.x) ~= 'number' or type(point.y) ~= 'number'
            or math.abs(point.x) > 10000 or math.abs(point.y) > 10000 then return end
        local blip = AddBlipForCoord(point.x + 0.0, point.y + 0.0, 0.0)
        SetBlipSprite(blip, style.sprite)
        SetBlipColour(blip, ALERT[point.state] and 1 or style.colour)
        SetBlipScale(blip, 0.85); SetBlipAsShortRange(blip, false)
        if point.kind == 'call' or point.state == 'triggered' or point.state == 'sounding' then SetBlipFlashes(blip, true) end
        local label = text(point.label) or ''
        local subtitle = text(point.subtitle)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(subtitle and (label .. ' - ' .. subtitle) or label)
        EndTextCommandSetBlipName(blip)
        blips[#blips + 1] = blip
    end
    -- points: lista enviada por la NUI; reopen: funcion que vuelve a abrir la tablet al salir del mapa.
    function worldmap.show(points, reopen)
        if open then return false end
        open = true; clear()
        if type(points) == 'table' then
            for index, point in ipairs(points) do
                if index > MAX_POINTS then break end
                if type(point) == 'table' then add(point) end
            end
        end
        CreateThread(function()
            Wait(250) -- deja cerrar la NUI antes de abrir el menu de pausa
            ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), false, -1)
            Wait(100)
            PauseMenuceptionGoDeeper(0)
            local deadline = GetGameTimer() + 3000
            while not IsPauseMenuActive() and GetGameTimer() < deadline do Wait(50) end
            while IsPauseMenuActive() do Wait(200) end
            clear(); open = false
            if reopen and not IsEntityDead(PlayerPedId()) then reopen() end
        end)
        return true
    end
    function worldmap.stop() clear(); open = false end
    worldmap.open = function() return open end
    return worldmap
end
