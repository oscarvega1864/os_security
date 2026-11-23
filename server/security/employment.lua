-- Adaptador opcional de empleo. Traduce el empleo del personaje activo (por ejemplo, el de
-- os_devtools: /setjob <id> gruppe6 <rango> y /setduty <id> on) a un perfil profesional G6.
-- Nunca concede 'admin' (solo ACE), ni la tablet Client, ni objetos. Sin proveedor, o si este
-- falla o responde algo no valido, no concede nada y siguen valiendo los ACE.
OSSecurity.Employment = {}

function OSSecurity.Employment.new(options)
    local settings = options.settings
    return function(source, holder)
        if not options.read or not settings or not settings.Job then return nil end
        local ok, employment = pcall(options.read, source)
        if not ok or type(employment) ~= 'table' then return nil, 'no_job' end
        if employment.job ~= settings.Job or type(employment.rank) ~= 'string' then return nil, 'no_job' end
        if settings.RequireDuty ~= false and employment.duty ~= true then return nil, 'off_duty' end
        -- Con objetos por personaje, el empleo debe ser del mismo personaje que posee la tablet.
        if holder ~= nil and employment.characterId ~= holder then return nil, 'other_character' end
        local role = settings.Ranks and settings.Ranks[employment.rank] or settings.DefaultRole
        if role ~= 'technician' and role ~= 'supervisor' then return nil, 'no_role' end
        return role
    end
end
