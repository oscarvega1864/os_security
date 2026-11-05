-- dkjson (incluido en FiveM): rechazar errores y contenido posterior al JSON.
-- Sin metatablas en los objetos decodificados; null conserva un marcador que
-- la validacion rechaza. No aceptar un documento parcial como snapshot valido.
OSSecurity.JsonCodec = {}

function OSSecurity.JsonCodec.encode(value)
    return json.encode(value)
end

function OSSecurity.JsonCodec.decode(content)
    local value, position, err = json.decode(content, 1, json.null, nil, nil)
    if err or not position or content:sub(position):find('%S') then
        error('Documento JSON invalido o con contenido adicional.')
    end
    return value
end
