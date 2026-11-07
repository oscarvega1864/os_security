-- Adaptador opcional del contrato administrativo. No concede roles G6 ni items.
OSSecurity.AdminAccess = {}
function OSSecurity.AdminAccess.new(options)
    return function(source,permission)
        local native=options.ace(source,permission)
        if native==true or native==1 then return true end
        if permission~=options.permission or not options.resource then return false end
        local ok,allowed=pcall(function()
            if options.state(options.resource)~='started' then return false end
            return options.delegate(options.resource,source,permission)
        end)
        return ok and allowed==true
    end
end
