-- Geometria comun de montajes (cliente y servidor). Un montaje es un cuadrado sobre una superficie
-- (pared, techo o suelo) con centro, normal y semilado ('radius', 0,25-2 m).
OSSecurity = OSSecurity or {}
OSSecurity.Geometry = {}
local geometry = OSSecurity.Geometry

local function normalize(v)
    local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if length < 0.0001 then return nil end
    return { x = v.x / length, y = v.y / length, z = v.z / length }
end

-- Ejes locales: X a la derecha de quien mira la superficie, Y "arriba" sobre ella.
-- En techo o suelo (normal casi vertical) X es el eje X del mundo e Y el eje Y del mundo.
function geometry.frame(normal)
    local n = normalize(normal) or { x = 0, y = 1, z = 0 }
    local right = math.abs(n.z) < 0.95 and normalize({ x = -n.y, y = n.x, z = 0 }) or { x = 1, y = 0, z = 0 }
    local up = { x = n.y * right.z - n.z * right.y, y = n.z * right.x - n.x * right.z, z = n.x * right.y - n.y * right.x }
    return { normal = n, right = right, up = up }
end

-- Coordenadas locales (x, y) de un punto respecto al centro del montaje, y distancia al plano.
function geometry.project(mount, point)
    local frame = geometry.frame(mount.normal)
    local d = { x = point.x - mount.position.x, y = point.y - mount.position.y, z = point.z - mount.position.z }
    return d.x * frame.right.x + d.y * frame.right.y + d.z * frame.right.z,
        d.x * frame.up.x + d.y * frame.up.y + d.z * frame.up.z,
        d.x * frame.normal.x + d.y * frame.normal.y + d.z * frame.normal.z
end

-- Dentro del cuadrado del montaje (con tolerancia en mm).
function geometry.inside(mount, point)
    local x, y = geometry.project(mount, point)
    local limit = mount.radius + 0.001
    return math.abs(x) <= limit and math.abs(y) <= limit
end

-- Punto del plano a partir de coordenadas locales, limitado al cuadrado (margen opcional).
function geometry.point(mount, x, y, margin)
    local frame, limit = geometry.frame(mount.normal), mount.radius * (margin or 1)
    x, y = math.max(-limit, math.min(limit, x)), math.max(-limit, math.min(limit, y))
    local p = mount.position
    return { x = p.x + frame.right.x * x + frame.up.x * y, y = p.y + frame.right.y * x + frame.up.y * y,
        z = p.z + frame.right.z * x + frame.up.z * y }, x, y
end

-- Esquinas del cuadrado (para dibujarlo), separadas 'lift' metros de la superficie.
function geometry.corners(mount, lift)
    local frame, r, p, l = geometry.frame(mount.normal), mount.radius, mount.position, lift or 0.01
    local list = {}
    for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
        list[#list + 1] = { x = p.x + frame.right.x * r * s[1] + frame.up.x * r * s[2] + frame.normal.x * l,
            y = p.y + frame.right.y * r * s[1] + frame.up.y * r * s[2] + frame.normal.y * l,
            z = p.z + frame.right.z * r * s[1] + frame.up.z * r * s[2] + frame.normal.z * l }
    end
    return list
end
