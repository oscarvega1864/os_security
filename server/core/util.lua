OSSecurity.Util = {}
local util = OSSecurity.Util

-- Solo copiar datos ya validados: tablas planas, sin ciclos ni metatablas.
function util.copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = util.copy(item) end
    return result
end

function util.equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end
    for key, item in pairs(left) do
        if not util.equal(item, right[key]) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

-- Redondeo a decimales fijos para coordenadas y angulos persistidos. Evita mantisas largas y
-- exponentes muy negativos (p. ej. 2e-17 en normales del raycast) que el JSON del runtime no
-- relee de forma exacta, lo que bloquearia el guardado por integridad.
function util.round(value, decimals)
    if not util.finite(value) then return value end
    local rounded = tonumber(('%.' .. decimals .. 'f'):format(value))
    if rounded == 0 then return 0 end
    if rounded == math.floor(rounded) and math.abs(rounded) < 2^53 then return math.tointeger(rounded) end
    return rounded
end

-- Igualdad de datos tras serializar: como util.equal, pero dos decimales que solo difieren en el redondeo del
-- JSON (error relativo menor de 1e-9) cuentan como iguales. Enteros, textos y estructura se comparan exactos.
function util.sameData(left, right)
    if type(left) == 'number' and type(right) == 'number' then
        if left == right then return true end
        if math.type(left) == 'integer' and math.type(right) == 'integer' then return false end
        if not util.finite(left) or not util.finite(right) then return false end
        return math.abs(left - right) <= 1e-9 * math.max(math.abs(left), math.abs(right))
    end
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end
    for key, item in pairs(left) do
        if not util.sameData(item, right[key]) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

function util.finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

function util.integer(value, minimum, maximum)
    return util.finite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

function util.text(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum
        and not value:find('[%c]')
end

function util.object(value, fields)
    if type(value) ~= 'table' or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if type(key) ~= 'string' or (fields and not fields[key]) then return false end
    end
    return true
end

function util.array(value, maximum)
    if type(value) ~= 'table' or getmetatable(value) ~= nil then return false end
    local count = 0
    for key in pairs(value) do
        if not util.integer(key, 1, maximum) then return false end
        count = count + 1
    end
    return count <= maximum and count == #value
end

-- Recorta a 'size' bytes sin partir una letra de varios bytes (ñ, tildes): sin esto quedaba UTF-8 invalido.
function util.cut(text, size)
    text = text:sub(1, size)
    while #text > 0 and not utf8.len(text) do text = text:sub(1, -2) end
    return text
end

-- Texto libre de un jugador: sin controles ni < >, espacios normalizados y como mucho 'size' bytes; nil si queda vacio.
function util.clean(text, size)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[%c<>]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    text = util.cut(text, size)
    text = text:gsub('%s+$', '')
    return text ~= '' and text or nil
end

-- Siguiente identificador 'prefijo_000001' de una lista indexada por esos identificadores.
function util.nextId(list, prefix)
    local highest = 0
    for id in pairs(list) do highest = math.max(highest, tonumber(id:sub(#prefix + 2)) or 0) end
    return ('%s_%06d'):format(prefix, highest + 1)
end
