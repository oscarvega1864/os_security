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
    function sites.label(site)
        if not OSSecurity.InventoryState.site(site) then return nil end
        local asset = sites.get(site)
        local name = asset and type(asset.name) == 'string' and asset.name or nil
        return ('%s %d%s'):format(OSSecurity.Sites.Labels[site.kind], site.id, name and (' · ' .. name) or '')
    end
    return sites
end
