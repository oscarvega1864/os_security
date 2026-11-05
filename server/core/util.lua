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
