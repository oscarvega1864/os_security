-- Puente firmado con la web de Gruppe Sechs (opcional). os_security inicia siempre la conexion
-- (HTTPS saliente): envia sus eventos al momento y recoge los comandos de la web cada pocos segundos.
-- Contrato y seguridad: docs/integracion-web-gruppe6.md. Sin URL y secreto validos no se crea.
--
-- Firma: v1=HMAC-SHA256(secreto, canonico), canonico =
--   "v1\n" cliente "\n" version "\n" timestamp "\n" nonce "\n" metodo "\n" "fivem-bridge" "\n" idempotencia "\n" sha256(cuerpo)
-- Las respuestas llegan firmadas igual con el mismo nonce y metodo "RESPONSE <estado>"; las que no
-- verifican se descartan sin tocar el estado.
OSSecurity.WebBridge = { Path = 'fivem-bridge', Protocol = 1, Batch = 50 }

local crypto = OSSecurity.Crypto

function OSSecurity.WebBridge.validSecret(secret)
    return type(secret) == 'string' and #secret >= 64 and #secret <= 128 and secret:match('^[0-9a-f]+$') ~= nil
end

function OSSecurity.WebBridge.validClient(client)
    return type(client) == 'string' and #client >= 3 and #client <= 40 and client:match('^[a-z0-9][a-z0-9%-]+$') ~= nil
end

-- HTTPS obligatorio; HTTP solo hacia esta maquina (pruebas locales).
function OSSecurity.WebBridge.validUrl(url)
    if type(url) ~= 'string' or #url > 300 or url:find('[%s%c\'"<>]') then return false end
    local scheme, host = url:match('^(https?)://([%w%.%-]+)')
    if not scheme then return false end
    return scheme == 'https' or host == '127.0.0.1' or host == 'localhost'
end

function OSSecurity.WebBridge.canonical(client, version, timestamp, nonce, method, idempotency, body)
    return table.concat({ 'v1', client, tostring(version), tostring(timestamp), nonce, method, OSSecurity.WebBridge.Path,
        idempotency or '', crypto.sha256(body) }, '\n')
end

function OSSecurity.WebBridge.signature(secret, canonical) return 'v1=' .. crypto.hmac(secret, canonical) end

local function integer(value, minimum)
    local number = math.tointeger(value)
    return number ~= nil and number >= (minimum or 0) and number or nil
end

function OSSecurity.WebBridge.new(options)
    local bridge = {}
    local W = OSSecurity.WebBridge
    local pullSeconds, maxEvents = options.pullSeconds or 5, options.maxEvents or 500
    local state, loaded, stopped, busy, greeted = nil, false, true, false, false
    local failures, counter, lastOk, lastError, timer = 0, 0, nil, nil, 0
    local handlers = {}
    local log = options.log or function() end

    local function nonce()
        counter = counter + 1
        return crypto.hmac(options.seed, ('nonce:%d:%d'):format(counter, options.now())):sub(1, 32)
    end

    -- Estado persistente: cursor de comandos aplicados, cola de eventos, confirmaciones pendientes y la
    -- peticion de escritura en vuelo (se reenvia con el mismo cuerpo y la misma clave).
    local function valid(value)
        if type(value) ~= 'table' or not integer(value.cursor) or not integer(value.seq)
            or type(value.instance) ~= 'string' or not value.instance:match('^[0-9a-f]+$') or #value.instance ~= 32
            or type(value.events) ~= 'table' or type(value.acks) ~= 'table' then return false end
        if value.inflight ~= nil and (type(value.inflight) ~= 'table' or type(value.inflight.body) ~= 'string'
            or type(value.inflight.key) ~= 'string' or (value.inflight.action ~= 'events' and value.inflight.action ~= 'ack')
            or not integer(value.inflight.count, 1)) then return false end
        return true
    end
    local function save()
        local ok, encoded = pcall(options.encode, state)
        if not ok or not options.files.write(options.path, encoded) then
            lastError = 'No se pudo guardar la cola del puente web.'
            log(lastError)
            return false
        end
        return true
    end
    local function load()
        local content, err = options.files.read(options.path)
        if err then return nil, 'Cola del puente web ilegible: ' .. tostring(err) end
        if content == nil then
            state = { cursor = 0, seq = 0, instance = nonce(), events = {}, acks = {} }
            return save() or nil, lastError
        end
        local ok, decoded = pcall(options.decode, content)
        if not ok or not valid(decoded) then return nil, 'Cola del puente web corrupta; no se sobrescribe (revisar ' .. options.path .. ').' end
        decoded.cursor, decoded.seq = integer(decoded.cursor), integer(decoded.seq)
        if decoded.inflight then decoded.inflight.count = integer(decoded.inflight.count, 1) end
        state = decoded
        return true
    end

    local function request(action, data, inflight, done)
        local body = inflight and inflight.body or options.encode({ action = action, data = data })
        local key = inflight and inflight.key or ''
        local timestamp, requestNonce = options.now(), nonce()
        local headers = {
            ['Content-Type'] = 'application/json', ['X-G6-Client'] = options.client, ['X-G6-Key-Version'] = tostring(options.version),
            ['X-G6-Timestamp'] = tostring(timestamp), ['X-G6-Nonce'] = requestNonce,
            ['X-G6-Signature'] = W.signature(options.secret, W.canonical(options.client, options.version, timestamp, requestNonce, 'POST', key, body))
        }
        if key ~= '' then headers['Idempotency-Key'] = key end
        options.http(options.url, 'POST', body, headers, function(status, responseBody, responseHeaders)
            status = integer(status) or 0
            local lower = {}
            for name, value in pairs(type(responseHeaders) == 'table' and responseHeaders or {}) do
                if type(name) == 'string' then lower[name:lower()] = value end
            end
            local signature, stamp = lower['x-g6-signature'], integer(tonumber(lower['x-g6-timestamp']))
            if status == 0 then return done(false, 'sin conexion') end
            if type(signature) ~= 'string' or not stamp or type(responseBody) ~= 'string' then
                return done(false, ('respuesta %d sin firmar'):format(status), status)
            end
            local expected = W.signature(options.secret, W.canonical(options.client, options.version, stamp, requestNonce, 'RESPONSE ' .. status, key, responseBody))
            if not crypto.equal(expected, signature) or math.abs(options.now() - stamp) > 300 then
                return done(false, 'firma de respuesta no valida', status)
            end
            local ok, decoded = pcall(options.decode, responseBody)
            if not ok or type(decoded) ~= 'table' then return done(false, 'respuesta ilegible', status) end
            if status ~= 200 or decoded.ok ~= true then return done(false, tostring(decoded.error or status), status) end
            done(true, decoded.data, status)
        end)
    end

    -- Comandos de la web: se aplican en orden una sola vez (cursor) y se confirman despues.
    local function apply(commands)
        if type(commands) ~= 'table' then return end
        local changed = false
        for _, command in ipairs(commands) do
            local id = type(command) == 'table' and integer(command.id, 1)
            if id and id > state.cursor then
                local handler, result, detail = handlers[command.type], 'ignored', 'unsupported'
                if handler then
                    local ok, outcome, why = pcall(handler, type(command.data) == 'table' and command.data or {})
                    if not ok then result, detail = 'rejected', 'error'
                        log(('Comando web %d (%s) fallo: %s'):format(id, tostring(command.type), tostring(outcome)))
                    elseif outcome == 'applied' or outcome == 'rejected' or outcome == 'ignored' then result, detail = outcome, why
                    else result, detail = 'applied', nil end
                end
                state.acks[#state.acks + 1] = { id = id, result = result, detail = type(detail) == 'string' and detail:sub(1, 200) or nil }
                state.cursor, changed = id, true
            end
        end
        if changed then save() end
    end

    local schedule
    local function finish(ok, err)
        busy = false
        if ok then failures, lastOk, lastError = 0, options.now(), nil
        else
            failures = failures + 1
            if err ~= lastError then log('Puente web: ' .. tostring(err)) end
            lastError = err
        end
        schedule()
    end
    local function pending() return state.inflight ~= nil or #state.acks > 0 or #state.events > 0 end

    local function prepare(action, items, count)
        local first = action == 'events' and items[1].event_id or tostring(items[1].id)
        local body = options.encode({ action = action, data = { items = items } })
        state.inflight = { action = action, key = crypto.sha256(('%s:%s:%s:%d:%d'):format(options.client, state.instance, first, count, state.seq)),
            body = body, count = count }
        return save()
    end
    local function settle(sent, ok, status)
        -- Exito o rechazo definitivo del contenido (4xx salvo autenticacion/limite): se retira de la cola.
        local final = ok or (status == 409 or status == 413 or status == 422)
        if not final then return end
        local list = sent.action == 'events' and state.events or state.acks
        for _ = 1, math.min(sent.count, #list) do table.remove(list, 1) end
        if not ok then log(('Puente web: lote %s descartado (%d).'):format(sent.action, status)) end
        state.inflight = nil
        save()
    end

    local function tick()
        if stopped or busy then return end
        busy = true
        if not greeted then
            return request('hello', { version = options.resourceVersion, cursor = state.cursor }, nil, function(ok, data)
                if ok then greeted = true; apply(type(data) == 'table' and data.commands) end
                finish(ok, data)
            end)
        end
        if not state.inflight then
            if #state.acks > 0 then
                local items = {}
                for i = 1, math.min(W.Batch, #state.acks) do items[i] = state.acks[i] end
                if not prepare('ack', items, #items) then return finish(false, lastError) end
            elseif #state.events > 0 then
                local items = {}
                for i = 1, math.min(W.Batch, #state.events) do items[i] = state.events[i] end
                if not prepare('events', items, #items) then return finish(false, lastError) end
            end
        end
        if state.inflight then
            local sent = state.inflight
            return request(sent.action, nil, sent, function(ok, data, status)
                settle(sent, ok, status or 0)
                finish(ok, data)
            end)
        end
        request('pull', { cursor = state.cursor }, nil, function(ok, data)
            if ok then apply(type(data) == 'table' and data.commands) end
            finish(ok, data)
        end)
    end

    schedule = function()
        if stopped then return end
        timer = timer + 1
        local mine = timer
        local delay = failures > 0 and math.min(300, 5 * 2 ^ math.min(failures - 1, 6)) or (pending() and 0.2 or pullSeconds)
        options.schedule(delay, function() if mine == timer then tick() end end)
    end

    -- API para los modulos (fases siguientes).
    function bridge.on(commandType, handler) handlers[commandType] = handler end
    function bridge.emit(eventType, data)
        if not loaded or type(eventType) ~= 'string' or not eventType:match('^[a-z]+%.[a-z_%.]+$') or #eventType > 40 then return false end
        state.seq = state.seq + 1
        state.events[#state.events + 1] = { event_id = crypto.sha256(('%s:%s:%d'):format(options.client, state.instance, state.seq)),
            type = eventType, at = options.now(), data = data or {} }
        while #state.events > maxEvents do
            table.remove(state.events, 1)
            log('Puente web: cola llena, se descarta el evento mas antiguo.')
        end
        save()
        if not busy and not stopped then schedule() end
        return true
    end
    function bridge.start()
        local ok, err = load()
        if not ok then lastError = err; log(err); return false, err end
        loaded, stopped, greeted = true, false, false
        schedule()
        return true
    end
    function bridge.stop() stopped = true; timer = timer + 1 end
    function bridge.status()
        return { enabled = loaded and not stopped, connected = lastOk ~= nil and failures == 0, lastOk = lastOk, lastError = lastError,
            failures = failures, cursor = state and state.cursor or 0, queued = state and #state.events or 0,
            acks = state and #state.acks or 0, inflight = state and state.inflight ~= nil or false }
    end
    bridge.tick = tick -- pruebas
    return bridge
end
