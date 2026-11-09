-- Adaptador opcional de propiedades y negocios (por defecto os_devtools: GetAsset y GetActiveCharacter).
-- Solo concede la consulta en la tablet Client al titular del personaje activo. Sin proveedor, o si
-- falla o responde algo no valido, no concede nada.
OSSecurity.Sites = { Categories = { property = 'properties', business = 'businesses' },
    Labels = { property = 'Propiedad', business = 'Negocio' } }

function OSSecurity.Sites.new(options)
    local sites = {}
    local function call(callback, ...)
        if not callback then return nil end
        local ok, result = pcall(callback, ...)
        return ok and result or nil
    end
    function sites.available() return options.asset ~= nil and options.active ~= nil end
    function sites.get(site)
        if not OSSecurity.InventoryState.site(site) then return nil end
        local asset = call(options.asset, OSSecurity.Sites.Categories[site.kind], site.id)
        return type(asset) == 'table' and asset or nil
    end
    function sites.owner(site)
        local asset = sites.get(site)
        return asset and type(asset.owner) == 'string' and asset.owner or nil
    end
    function sites.owns(source, site)
        local owner = sites.owner(site)
        if not owner then return false end
        local character = call(options.active, source)
        return type(character) == 'table' and character.alias == owner
    end
    -- Propiedades y negocios con titular y posicion (para las cerraduras de sus puertas).
    function sites.owned()
        local result = {}
        for kind, category in pairs(OSSecurity.Sites.Categories) do
            local list = call(options.list, category)
            for _, asset in ipairs(type(list) == 'table' and list or {}) do
                local p = type(asset) == 'table' and asset.position
                if type(asset.owner) == 'string' and OSSecurity.Util.integer(asset.id, 1, 2147483646) and type(p) == 'table'
                    and OSSecurity.Util.finite(p.x) and OSSecurity.Util.finite(p.y) and OSSecurity.Util.finite(p.z) then
                    result[#result + 1] = { kind = kind, id = asset.id, owner = asset.owner, position = { x = p.x, y = p.y, z = p.z } }
                end
            end
        end
        table.sort(result, function(a, b) return a.kind == b.kind and a.id < b.id or a.kind < b.kind end)
        return result
    end
    function sites.label(site)
        if not OSSecurity.InventoryState.site(site) then return nil end
        local asset = sites.get(site)
        local name = asset and type(asset.name) == 'string' and asset.name or nil
        return ('%s %d%s'):format(OSSecurity.Sites.Labels[site.kind], site.id, name and (' · ' .. name) or '')
    end
    return sites
end
