local util = OSSecurity.Util
-- Calibracion del mapa de la tablet: convierte coordenadas del mundo en posicion sobre la imagen del mapa
-- (web/map/, la pone el propio servidor). En unidades de una imagen de 256 px de lado:
--   u = ax * x + bx      v = ay * y + by
-- La NUI multiplica por (ancho o alto real / 256). Los valores de fabrica corresponden al encuadre habitual
-- de los mapas cuadrados de GTA V (atlas, satelite, carreteras); un administrador puede recalibrar en el juego
-- con dos puntos lejanos. Se guarda en data/map.json (no se distribuye).
OSSecurity.TabletMap = {}

local FILE = 'data/map.json'
local DEFAULT = { ax = 0.02072, bx = 117.3, ay = -0.0205, by = 172.8 }
local MIN_SPAN = 800 -- metros entre los dos puntos de calibracion en cada eje

local function finite(value, limit) return type(value) == 'number' and value == value and math.abs(value) < (limit or 100000) end
local function valid(calibration)
    return type(calibration) == 'table' and finite(calibration.ax, 1) and finite(calibration.ay, 1)
        and math.abs(calibration.ax) > 1e-5 and math.abs(calibration.ay) > 1e-5
        and finite(calibration.bx, 10000) and finite(calibration.by, 10000)
end

function OSSecurity.TabletMap.new(options)
    local map = {}
    local current = util.copy(DEFAULT)
    current.custom = false
    if options.files then
        local ok, saved = pcall(function()
            local content = options.files.read(FILE)
            return content and OSSecurity.JsonCodec.decode(content) or nil
        end)
        if ok and valid(saved) then
            current = { ax = saved.ax, bx = saved.bx, ay = saved.ay, by = saved.by, custom = true }
        elseif not ok and options.log then options.log('Mapa de la tablet: data/map.json ilegible; se usa la calibracion de fabrica.') end
    end
    function map.calibration() return util.copy(current) end

    -- args: { first = { u, v, x, y }, second = { u, v, x, y } } o { reset = true }.
    -- u, v: punto marcado en la imagen (unidades de 256); x, y: posicion del jugador en ese momento.
    function map.calibrate(actor, args)
        if actor.kind ~= 'operations' or actor.role ~= 'admin' then return nil, 'Solo un administrador puede calibrar el mapa.' end
        if util.object(args, { reset = true }) and args.reset == true then
            current = util.copy(DEFAULT); current.custom = false
            if options.files then options.files.write(FILE, OSSecurity.JsonCodec.encode({ reset = true })) end
            return map.calibration()
        end
        if not util.object(args, { first = true, second = true }) then return nil, 'Calibracion no valida.' end
        local points = {}
        for _, key in ipairs({ 'first', 'second' }) do
            local point = args[key]
            if not util.object(point, { u = true, v = true, x = true, y = true }) or not finite(point.u, 300) or not finite(point.v, 300)
                or not finite(point.x, 10000) or not finite(point.y, 10000) then return nil, 'Punto de calibracion no valido.' end
            points[#points + 1] = point
        end
        local a, b = points[1], points[2]
        if math.abs(b.x - a.x) < MIN_SPAN or math.abs(b.y - a.y) < MIN_SPAN then
            return nil, ('Los dos puntos deben estar a mas de %d m en horizontal y en vertical.'):format(MIN_SPAN)
        end
        local ax = (b.u - a.u) / (b.x - a.x); local ay = (b.v - a.v) / (b.y - a.y)
        local result = { ax = ax, bx = a.u - ax * a.x, ay = ay, by = a.v - ay * a.y }
        if not valid(result) or ax <= 0 or ay >= 0 then return nil, 'Calibracion incoherente: revisa los puntos marcados.' end
        if options.files and not options.files.write(FILE, OSSecurity.JsonCodec.encode(result)) then return nil, 'No se pudo guardar la calibracion.' end
        current = result; current.custom = true
        if options.audit then options.audit('map_calibrate', actor.source) end
        return map.calibration()
    end
    return map
end
