-- Vinculacion de personajes con cuentas de gruppe6.es (Extranet o Intranet). Requiere el puente web.
--   /g6web              codigo de un solo uso (10 min) que solo ve el jugador; la web solo guarda su HMAC
--   /g6web estado       cuenta vinculada a este personaje
--   /g6web desvincular  avisa a la web (evento link.revoke) y lo olvida aqui
-- La web confirma con los comandos link.created / link.revoked; el estado local se guarda en
-- data/web_links.json solo para mostrarlo (la web es la fuente de verdad).
OSSecurity.WebLinks = { Alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789', CodeSeconds = 600, OfferEvery = 60 }

local function text(value, size)
    return type(value) == 'string' and value ~= '' and #value <= size and not value:find('[%c<>]') and value or nil
end
local function characterId(value)
    return type(value) == 'string' and #value <= 64 and value:match('^[%w_:%-]+$') ~= nil and value or nil
end

-- Nombre visible a partir del alias de os_devtools ("oscar_vega" -> "Oscar Vega").
function OSSecurity.WebLinks.label(alias)
    if type(alias) ~= 'string' then return nil end
    local words = {}
    for word in alias:gmatch('[^_%s]+') do words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2) end
    return text(table.concat(words, ' '):sub(1, 80), 80)
end

function OSSecurity.WebLinks.new(options)
    local L = OSSecurity.WebLinks
    local links = {}
    local state, offered = nil, {}
    local listen

    local function save()
        local ok, encoded = pcall(options.encode, state)
        return ok and options.files.write(options.path, encoded)
    end
    function links.load()
        local content, err = options.files.read(options.path)
        if err then return nil, 'Vinculos web ilegibles: ' .. tostring(err) end
        if content == nil then state = { links = {} }; listen(); return true end
        local ok, decoded = pcall(options.decode, content)
        if not ok or type(decoded) ~= 'table' or type(decoded.links) ~= 'table' then
            return nil, 'Vinculos web corruptos; no se sobrescriben (revisar ' .. options.path .. ').'
        end
        for id, link in pairs(decoded.links) do
            if not characterId(id) or type(link) ~= 'table' or not text(link.account, 80) then
                return nil, 'Vinculos web corruptos; no se sobrescriben (revisar ' .. options.path .. ').'
            end
        end
        state = decoded
        listen()
        return true
    end

    -- Codigo de 8 caracteres sin ambiguos (sin 0/O, 1/I/L), sesgo eliminado por rechazo.
    local function code()
        local result = {}
        while #result < 8 do
            local random = options.bridge.random()
            for i = 1, #random - 1, 2 do
                local byte = tonumber(random:sub(i, i + 1), 16)
                if byte < 248 then
                    local index = byte % #L.Alphabet + 1
                    result[#result + 1] = L.Alphabet:sub(index, index)
                    if #result == 8 then break end
                end
            end
        end
        return table.concat(result)
    end

    function links.offer(source)
        local character = options.character(source)
        if not character then return options.tell(source, 'Necesitas un personaje activo para vincularlo con gruppe6.es.') end
        local last = offered[character.id]
        if last and options.now() - last < L.OfferEvery then
            return options.tell(source, ('Espera %d s antes de pedir otro código.'):format(L.OfferEvery - (options.now() - last)))
        end
        offered[character.id] = options.now()
        local value = code()
        options.bridge.send('link.offer', { character = character.id, label = character.label, code = value,
            expires_at = options.now() + L.CodeSeconds }, function(ok, result)
            if not ok then
                offered[character.id] = nil
                if options.log then options.log('Codigo /g6web no aceptado: ' .. tostring(result)) end
                return options.tell(source, 'No se ha podido conectar con gruppe6.es. Inténtalo más tarde.')
            end
            -- Solo para este jugador; nunca en logs ni en el chat global.
            options.tell(source, ('Código para gruppe6.es: %s-%s (caduca en 10 minutos, un solo uso). Introdúcelo en Configuración > Personaje de FiveM.')
                :format(value:sub(1, 4), value:sub(5, 8)))
        end)
    end

    function links.status(source)
        local character = options.character(source)
        if not character then return options.tell(source, 'Necesitas un personaje activo.') end
        local link = state.links[character.id]
        options.tell(source, link and ('%s está vinculado a la cuenta %s de gruppe6.es.'):format(character.label, link.account)
            or ('%s no está vinculado. Usa /g6web para obtener un código.'):format(character.label))
    end

    function links.unlink(source)
        local character = options.character(source)
        if not character then return options.tell(source, 'Necesitas un personaje activo.') end
        if not state.links[character.id] then return options.tell(source, 'Este personaje no está vinculado.') end
        state.links[character.id] = nil
        save()
        options.bridge.emit('link.revoke', { character = character.id })
        options.tell(source, 'Personaje desvinculado de gruppe6.es.')
    end

    -- Comandos de la web (solo con el estado cargado).
    listen = function()
        options.bridge.on('link.created', function(data)
            local id, account = characterId(data.character), text(data.account, 80)
            if not id or not account then return 'rejected', 'invalid_payload' end
            state.links[id] = { account = account, kind = data.kind == 'intranet' and 'intranet' or 'extranet', at = options.now() }
            save()
            local player = options.sourceOf(id)
            if player then options.tell(player, ('Personaje vinculado a la cuenta %s de gruppe6.es.'):format(account)) end
            return 'applied'
        end)
        options.bridge.on('link.revoked', function(data)
            local id = characterId(data.character)
            if not id then return 'rejected', 'invalid_payload' end
            if not state.links[id] then return 'ignored', 'not_linked' end
            state.links[id] = nil
            save()
            local player = options.sourceOf(id)
            if player then options.tell(player, 'Tu personaje se ha desvinculado de gruppe6.es.') end
            return 'applied'
        end)
    end

    function links.linked(id) return state and state.links[id] and OSSecurity.Util.copy(state.links[id]) or nil end
    return links
end
