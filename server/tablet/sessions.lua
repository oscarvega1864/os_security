OSSecurity.TabletSessions = {}

function OSSecurity.TabletSessions.new(options)
    local sessions, buckets = {}, {}
    local controller = {}
    local config = OSSecurity.GameplayConfig
    function controller.rate(source, opening)
        if not OSSecurity.Util.integer(source, 1, 2147483647) then return false end
        local now = options.now()
        local bucket = buckets[source]
        if not bucket or now < bucket.at or now - bucket.at >= config.RequestWindow then
            bucket = { at = now, requests = 0, openings = 0 }; buckets[source] = bucket
        end
        local key, limit = opening and 'openings' or 'requests', opening and config.OpenRequestsPerWindow or config.RequestsPerWindow
        if bucket[key] >= limit then return false end
        bucket[key] = bucket[key] + 1
        return true
    end
    function controller.open(source, kind)
        if not controller.rate(source, true) then return nil, 'Limite de apertura alcanzado.' end
        if not options.alive(source) then return nil, 'Jugador no disponible.' end
        local actor, err = options.auth.profile(source, kind)
        if not actor then return nil, err end
        local token = options.token(source)
        if not OSSecurity.Util.text(token, 128) then return nil, 'No se pudo crear la sesion.' end
        local session = { token = token, source = source, actor = actor, sequence = 0, expires = options.now() + config.SessionSeconds }
        sessions[source] = session
        return session
    end
    function controller.check(source, token, sequence)
        if not controller.rate(source, false) then return nil, 'Limite de solicitudes alcanzado.' end
        local session = sessions[source]
        if not session or type(token) ~= 'string' or token ~= session.token
            or not OSSecurity.Util.integer(sequence, 1, 2147483647) or sequence ~= session.sequence + 1 then
            return nil, 'Sesion o secuencia no valida.'
        end
        local actor = options.auth.profile(source, session.actor.kind)
        if options.now() > session.expires or not options.alive(source) or not actor
            or actor.principal ~= session.actor.principal or actor.role ~= session.actor.role then
            sessions[source] = nil
            return nil, 'La sesion ha caducado o su autorizacion ha cambiado.'
        end
        session.sequence, session.expires = sequence, options.now() + config.SessionSeconds
        return session
    end
    function controller.close(source) sessions[source] = nil end
    function controller.drop(source) sessions[source], buckets[source] = nil, nil end
    function controller.clear() sessions, buckets = {}, {} end
    return controller
end
