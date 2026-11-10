local test = StorageTest.test
local W, crypto = OSSecurity.WebBridge, OSSecurity.Crypto
local SECRET = string.rep('0123456789abcdef', 4)

test('SHA-256 and HMAC-SHA256 match FIPS 180-2 and RFC 4231 vectors', function()
    assert(crypto.sha256('') == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    assert(crypto.sha256('abc') == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
    assert(crypto.sha256('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq') == '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1')
    assert(crypto.sha256(string.rep('a', 1000)) == '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3')
    assert(crypto.hmac(string.rep('\11', 20), 'Hi There') == 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7')
    assert(crypto.hmac('Jefe', 'what do ya want for nothing?') == '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843')
    assert(crypto.hmac(string.rep('\170', 131), 'Test Using Larger Than Block-Size Key - Hash Key First')
        == '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54')
    assert(crypto.equal('abc', 'abc') and not crypto.equal('abc', 'abd') and not crypto.equal('abc', 'ab'))
end)

test('Web bridge signature is byte-identical to the GruppeNGRP vector (tests/fivem-bridge-cases.php)', function()
    local body = '{"action":"hello","data":{"version":"0.13.0","cursor":0}}'
    assert(W.signature(SECRET, W.canonical('fivem-test', 1, 1762862400, '00112233445566778899aabbccddeeff', 'POST', '', body))
        == 'v1=94f29622a1671bdc9ce5ddc6ca9cbfd2ed52b4cc523f6c3d2a504374496167a7')
end)

test('Web bridge settings: https only (http just for this machine), hex secrets and safe client ids', function()
    assert(W.validUrl('https://gruppe6.es/intranet/api/fivem-bridge.php') and W.validUrl('http://127.0.0.1:8080/x'))
    assert(not W.validUrl('http://gruppe6.es/x') and not W.validUrl('ftp://gruppe6.es') and not W.validUrl('https://a b'))
    assert(W.validSecret(SECRET) and not W.validSecret('abc') and not W.validSecret(string.rep('G', 64)))
    assert(W.validClient('fivem-prod') and not W.validClient('Fivem Prod') and not W.validClient('x'))
end)

-- Web simulada: verifica cada firma y nonce, guarda recibos por clave de idempotencia (exige el mismo
-- cuerpo al reintentar) y firma sus respuestas como fivem_bridge.php.
local function fixture(files)
    local c = { now = 1762862400, timers = {}, logs = {}, files = files or {} }
    c.web = { commands = {}, events = {}, acks = {}, receipts = {}, nonces = {}, requests = 0 }
    local web = c.web
    local function http(_, method, body, headers, callback)
        web.requests = web.requests + 1
        assert(method == 'POST')
        if web.down then return callback(0, '', {}) end
        local key = headers['Idempotency-Key'] or ''
        local client, version = headers['X-G6-Client'], tonumber(headers['X-G6-Key-Version'])
        assert(headers['X-G6-Signature'] == W.signature(SECRET, W.canonical(client, version, headers['X-G6-Timestamp'], headers['X-G6-Nonce'], 'POST', key, body)), 'request signature')
        assert(headers['X-G6-Nonce']:match('^[0-9a-f]+$') and #headers['X-G6-Nonce'] == 32 and not web.nonces[headers['X-G6-Nonce']], 'fresh nonce')
        web.nonces[headers['X-G6-Nonce']] = true
        local request = json.decode(body)
        local data
        if request.action == 'hello' or request.action == 'pull' then
            web.lastCursor = request.data.cursor
            local list = {}
            for _, command in ipairs(web.commands) do if command.id > request.data.cursor then list[#list + 1] = command end end
            data = { commands = list, latest = #web.commands }
        else
            assert(#key == 64, 'idempotency key')
            local receipt = web.receipts[key]
            if receipt then assert(receipt.body == body, 'retry reuses the same body'); data = receipt.data
            else
                for _, item in ipairs(request.data.items) do table.insert(request.action == 'events' and web.events or web.acks, item) end
                data = { done = #request.data.items }
                web.receipts[key] = { body = body, data = data }
            end
            if web.loseResponse then web.loseResponse = false; return callback(0, '', {}) end
        end
        local status = web.status or 200
        local response = json.encode(status == 200 and { ok = true, data = data } or { ok = false, error = 'invalid_payload' })
        local stamp = tostring(c.now)
        local signature = W.signature(web.forge and string.rep('f', 64) or SECRET,
            W.canonical(client, version, stamp, headers['X-G6-Nonce'], 'RESPONSE ' .. status, key, response))
        callback(status, response, { ['x-g6-signature'] = signature, ['X-G6-Timestamp'] = stamp })
    end
    local boots = 0
    function c.bridge()
        boots = boots + 1 -- en el servidor la semilla sale de bcrypt con sal aleatoria en cada arranque
        return W.new({ url = 'https://fixture.test/bridge', secret = SECRET, client = 'fivem-test', version = 1, resourceVersion = '0.13.0',
            seed = 'fixture-seed-' .. boots, now = function() return c.now end,
            encode = OSSecurity.JsonCodec.encode, decode = OSSecurity.JsonCodec.decode, path = 'data/web_bridge.json',
            files = { read = function(path) return c.files[path] end, write = function(path, content) c.files[path] = content; return true end },
            http = http, schedule = function(_, callback) c.timers[#c.timers + 1] = callback end,
            log = function(message) c.logs[#c.logs + 1] = message end })
    end
    function c.run(steps)
        for _ = 1, steps or 20 do
            local callback = table.remove(c.timers, 1)
            if not callback then return end
            callback()
        end
    end
    return c
end

test('Web bridge: commands are applied once in order, acknowledged, and not reapplied after a restart', function()
    local c = fixture()
    c.web.commands = { { id = 1, type = 'request.create', data = { ref = 'GS-2030-0001' } }, { id = 2, type = 'unknown.thing', data = {} },
        { id = 3, type = 'request.create', data = { ref = 'bad' } } }
    local applied = {}
    local bridge = c.bridge()
    bridge.on('request.create', function(data)
        if data.ref == 'bad' then return 'rejected', 'Referencia no valida' end
        applied[#applied + 1] = data.ref
    end)
    assert(bridge.start()); c.run()
    assert(#applied == 1 and applied[1] == 'GS-2030-0001' and bridge.status().cursor == 3 and bridge.status().connected)
    assert(#c.web.acks == 3 and c.web.acks[1].result == 'applied' and c.web.acks[2].result == 'ignored' and c.web.acks[2].detail == 'unsupported')
    assert(c.web.acks[3].result == 'rejected' and c.web.acks[3].detail == 'Referencia no valida')
    bridge.stop()
    local again = c.bridge(); again.on('request.create', function(data) applied[#applied + 1] = data.ref end)
    assert(again.start()); c.run()
    assert(#applied == 1 and c.web.lastCursor == 3 and #c.web.acks == 3)
end)

test('Web bridge: events wait while the web is down, survive a restart and a lost response is retried with the same key and body', function()
    local c = fixture()
    c.web.down = true
    local bridge = c.bridge(); assert(bridge.start())
    assert(bridge.emit('order.created', { order = 'ot_000001' }) and bridge.emit('order.status', { order = 'ot_000001', status = 'accepted' }))
    assert(not bridge.emit('Bad Type', {}))
    c.run(5)
    assert(#c.web.events == 0 and bridge.status().queued == 2 and bridge.status().failures > 0 and not bridge.status().connected)
    bridge.stop()
    c.web.down, c.web.loseResponse = false, true
    local restarted = c.bridge(); assert(restarted.start()); c.run()
    assert(#c.web.events == 2 and c.web.events[1].type == 'order.created' and c.web.events[2].data.status == 'accepted')
    assert(c.web.events[1].event_id ~= c.web.events[2].event_id and #c.web.events[1].event_id == 64)
    assert(restarted.status().queued == 0 and not restarted.status().inflight and restarted.status().connected)
end)

test('Web bridge: a forged or unsigned response changes nothing, and a rejected batch is dropped instead of blocking the queue', function()
    local c = fixture()
    c.web.commands = { { id = 1, type = 'request.create', data = {} } }
    c.web.forge = true
    local applied = 0
    local bridge = c.bridge(); bridge.on('request.create', function() applied = applied + 1 end)
    assert(bridge.start()); c.run(3)
    assert(applied == 0 and bridge.status().cursor == 0 and bridge.status().lastError:find('firma', 1, true))
    c.web.forge = false; c.run(); assert(applied == 1)
    c.web.status = 422
    bridge.emit('order.created', { order = 'x' }); c.run(4)
    assert(bridge.status().queued == 0 and not bridge.status().inflight)
end)

test('Web bridge: a corrupt queue file blocks the bridge without being overwritten', function()
    local c = fixture({ ['data/web_bridge.json'] = '{corrupt' })
    local bridge = c.bridge()
    local ok, err = bridge.start()
    assert(not ok and err:find('corrupta', 1, true) and c.files['data/web_bridge.json'] == '{corrupt' and #c.timers == 0)
end)
