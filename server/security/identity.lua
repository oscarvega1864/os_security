OSSecurity.Identity = {}

function OSSecurity.Identity.valid(principal)
    return type(principal) == 'string' and #principal == 48 and principal:match('^license:[0-9a-f]+$') ~= nil
end

function OSSecurity.Identity.new(options)
    local identity = {}
    function identity.resolve(source)
        if not OSSecurity.Util.integer(source, 1, 2147483647) or not options.connected(source) then
            return nil, 'Jugador no conectado.'
        end
        local principal = options.identifier(source)
        if not OSSecurity.Identity.valid(principal) then return nil, 'Identidad estable no disponible.' end
        return principal
    end
    return identity
end
