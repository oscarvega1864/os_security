OSSecurity.Permissions = {}

function OSSecurity.Permissions.new(options)
    local buckets = {}
    local permissions = {}

    function permissions.isAdmin(source)
        if not OSSecurity.Util.integer(source, 0, 2147483647) then return false end
        return source == 0 or options.isAceAllowed(source, options.ace) == true
    end

    function permissions.authorize(source, writing)
        if not permissions.isAdmin(source) then return nil, 'Acceso denegado: se requiere ' .. options.ace .. '.' end
        if source == 0 then return true end
        local now = options.now()
        local bucket = buckets[source]
        if not bucket or now < bucket.start or now - bucket.start >= options.limits.RateWindowSeconds then
            bucket = { start = now, reads = 0, writes = 0 }
            buckets[source] = bucket
        end
        local key = writing and 'writes' or 'reads'
        local maximum = writing and options.limits.WriteRequestsPerWindow or options.limits.ReadRequestsPerWindow
        if bucket[key] >= maximum then return nil, 'Limite de solicitudes alcanzado; espera unos segundos.' end
        bucket[key] = bucket[key] + 1
        return true
    end

    function permissions.forget(source) buckets[source] = nil end
    return permissions
end
