OSSecurity.Identity = {}

-- Titular de datos de Gruppe Sechs (dispositivos, zonas, concesiones, solicitudes):
--   license:<40 hex>  cuenta de Rockstar (modo standalone, sin personajes)
--   char:<id>         personaje activo del proveedor de identidad (os_devtools), para que
--                     cada personaje de una misma cuenta tenga lo suyo.
function OSSecurity.Identity.valid(principal)
    return OSSecurity.Identity.account(principal) or OSSecurity.Identity.character(principal)
end

function OSSecurity.Identity.character(principal)
    return type(principal) == 'string' and #principal > 5 and #principal <= 69 and principal:match('^char:[%w_:%-]+$') ~= nil
end

function OSSecurity.Identity.account(principal)
    return type(principal) == 'string' and #principal == 48 and principal:match('^license:[0-9a-f]+$') ~= nil
end

function OSSecurity.Identity.new(options)
    local identity = {}
    -- Con options.character, el titular es el personaje activo; sin personaje no hay identidad.
    function identity.characters() return options.character ~= nil end
    function identity.resolve(source)
        if not OSSecurity.Util.integer(source, 1, 2147483647) or not options.connected(source) then
            return nil, 'Jugador no conectado.'
        end
        if options.character then
            local ok, holder = pcall(options.character, source)
            local principal = ok and type(holder) == 'string' and ('char:' .. holder) or nil
            if not OSSecurity.Identity.character(principal) then return nil, 'Personaje activo no disponible.' end
            return principal
        end
        local principal = options.identifier(source)
        if not OSSecurity.Identity.valid(principal) then return nil, 'Identidad estable no disponible.' end
        return principal
    end
    return identity
end
