-- Adaptador del JSON de CfxLua y de dkjson. RapidJSON usa sus metatablas
-- predeterminadas cuando objectmeta/arraymeta son nil: no desactiva las etiquetas.
OSSecurity.JsonCodec = {}

function OSSecurity.JsonCodec.encode(value)
    return json.encode(value)
end

function OSSecurity.JsonCodec.decode(content)
    -- Proporcionar marcadores propios y retirar exclusivamente esas metatablas
    -- del resultado recien decodificado. El dominio sigue exigiendo datos planos.
    local objectMeta, arrayMeta = {}, {}
    local value, position, err = json.decode(content, 1, json.null, objectMeta, arrayMeta)
    if err or not position or content:sub(position):find('%S') then
        error('Documento JSON invalido o con contenido adicional.')
    end
    local function normalize(item)
        if type(item) ~= 'table' or item == json.null then return end
        local meta = getmetatable(item)
        if meta ~= nil and meta ~= objectMeta and meta ~= arrayMeta then return end
        if meta ~= nil then setmetatable(item, nil) end
        for _, child in pairs(item) do normalize(child) end
    end
    normalize(value)
    return value
end
