local test = StorageTest.test
dofile('/repo/client/tablet.lua')
dofile('/repo/client/view.lua')
dofile('/repo/client/props.lua')
dofile('/repo/client/placement.lua')
dofile('/repo/client/anchor.lua')
dofile('/repo/client/minigame.lua')

local function fixture()
    local c = { packets = {}, timers = {}, notifications = {}, shown = {}, hidden = 0, cancelled = 0, props = {} }
    c.client = OSSecurity.ClientTablet.new({
        send = function(packet) c.packets[#c.packets + 1] = packet end,
        timeout = function(callback) c.timers[#c.timers + 1] = callback end,
        show = function(session) assert(session.token == nil and session.sequence == nil); c.shown[#c.shown + 1] = session end,
        hide = function() c.hidden = c.hidden + 1 end,
        cancelPlacement = function() c.cancelled = c.cancelled + 1 end,
        beginPlacement = function(_, callback) c.confirm = callback end,
        props = function(list) c.props = list end,
        expiry = function() end,
        notify = function(message) c.notifications[#c.notifications + 1] = message end
    })
    function c.respond(response) c.client.response(c.packets[#c.packets].id, response) end
    function c.open(kind)
        c.client.open(kind)
        c.respond({ ok = true, session = { kind = kind, token = 'server-' .. kind, sequence = 0, expires = 9999999999,
            brand = OSSecurity.Brand, profile = kind } })
    end
    return c
end

test('Shared client controller uses distinct tablet sessions without exposing token to NUI', function()
    local c = fixture(); c.open('inventory')
    local result
    c.client.use('g6_operations_tablet', function(response) result = response end)
    assert(c.packets[#c.packets].token == 'server-inventory' and c.packets[#c.packets].args.item == 'g6_operations_tablet')
    c.respond({ ok = true, session = { kind = 'operations', token = 'server-operations', sequence = 0, expires = 9999999999,
        brand = OSSecurity.Brand, profile = 'Tecnico' } })
    assert(result.ok and result.session == nil and c.shown[#c.shown].kind == 'operations')
    c.client.request('inventory', {}, function() end)
    assert(c.packets[#c.packets].token == 'server-operations' and c.packets[#c.packets].sequence == 1)
end)

test('Client closes pending NUI callbacks, releases focus and ignores late server responses', function()
    local c = fixture(); c.open('client')
    local callbackResult
    c.client.request('devices', {}, function(response) callbackResult = response end)
    local oldId = c.packets[#c.packets].id
    c.client.close()
    assert(callbackResult and not callbackResult.ok and callbackResult.close)
    assert(not c.client.visible and c.cancelled > 0 and c.hidden > 0)
    local shows = #c.shown
    c.client.response(oldId, { ok = true, data = {} })
    assert(#c.shown == shows and not c.client.visible)
end)

test('RPC timeout and resource stop finish callbacks and clean local UI/placement state', function()
    local c = fixture(); c.open('operations')
    local result
    c.client.request('devices', {}, function(response) result = response end)
    c.timers[#c.timers]()
    assert(result and result.close and not c.client.visible and c.cancelled > 0)
    c = fixture(); c.open('operations')
    c.client.request('inventory', {}, function(response) result = response end)
    c.client.stop()
    assert(result.close and not c.client.visible and not c.client.placing)
end)

test('Placement uses the same authorized controller and cancellation does not invent a successful installation', function()
    local c = fixture(); c.open('operations')
    c.client.place(function() end)
    c.respond({ ok = true, placement = { model = 'prop_cctv_cam_01a', mounts = {} } })
    assert(c.client.placing and not c.client.visible)
    c.confirm(nil)
    assert(c.packets[#c.packets].action == 'place_cancel')
    c.respond({ ok = true, data = { cancelled = true } })
    assert(not c.client.placing and c.notifications[#c.notifications] == 'Colocacion cancelada.')
end)

test('Using the CCTV kit from an external inventory opens a hidden session, then starts placement only if authorized', function()
    local c = fixture()
    c.client.useItem('os_cctv_kit')
    assert(c.packets[#c.packets].action == 'open' and c.packets[#c.packets].args.kind == 'inventory')
    c.respond({ ok = true, session = { kind = 'inventory', token = 'server-inventory', sequence = 0, expires = 9999999999,
        brand = OSSecurity.Brand, profile = 'inventory' } })
    assert(#c.shown == 0 and c.packets[#c.packets].action == 'use' and c.packets[#c.packets].token == 'server-inventory')
    assert(c.packets[#c.packets].args.item == 'os_cctv_kit')
    c.respond({ ok = true, session = { kind = 'operations', token = 'server-operations', sequence = 0, expires = 9999999999,
        brand = OSSecurity.Brand, profile = 'Tecnico' }, placement = { model = 'prop_cctv_cam_01a', mounts = {} } })
    assert(c.client.placing and not c.client.visible and c.confirm and #c.shown == 0)

    local denied = fixture()
    denied.client.useItem('os_cctv_kit')
    denied.respond({ ok = true, session = { kind = 'inventory', token = 'server-inventory', sequence = 0, expires = 9999999999,
        brand = OSSecurity.Brand, profile = 'inventory' } })
    denied.respond({ ok = false, error = 'Faltan herramientas de instalacion.', close = true })
    assert(not denied.client.placing and not denied.client.visible and #denied.shown == 0)
    assert(denied.notifications[#denied.notifications] == 'Faltan herramientas de instalacion.')
end)

test('Player messages use os_notify with their kind when started and fall back to the standard chat', function()
    dofile('/repo/client/notify.lua')
    local saved = { GetResourceState = rawget(_G, 'GetResourceState'), exports = rawget(_G, 'exports'), TriggerEvent = rawget(_G, 'TriggerEvent') }
    local state, toasts, chats = 'started', {}, {}
    local ok, err = pcall(function()
        GetResourceState = function(name) assert(name == 'os_notify'); return state end
        exports = { os_notify = { Notify = function(_, message, kind) toasts[#toasts + 1] = { message, kind } end } }
        TriggerEvent = function(name, payload) assert(name == 'chat:addMessage'); chats[#chats + 1] = payload.args end
        assert(OSSecurity.Notify('CCTV registrado: osd_0000000001', 'success') == 'os_notify')
        assert(toasts[1][1] == 'CCTV registrado: osd_0000000001' and toasts[1][2] == 'success')
        OSSecurity.Notify('Sin tipo valido', 'html'); assert(toasts[2][2] == 'info')
        state = 'stopped'
        assert(OSSecurity.Notify('Faltan materiales.', 'error') == 'chat')
        assert(chats[1][1] == OSSecurity.Brand.Name and chats[1][2] == 'Faltan materiales.')
        state = 'started'; exports.os_notify.Notify = function() error('export no disponible') end
        assert(OSSecurity.Notify('Error del proveedor', 'error') == 'chat' and #chats == 2)
        assert(OSSecurity.Notify(nil, 'error') == 'chat' and chats[3][2] == OSSecurity.Brand.Text.failed)
    end)
    for name, value in pairs(saved) do _G[name] = value end
    assert(ok, err)
end)

test('Mount geometry keeps the camera inside the square zone on walls and ceilings', function()
    local G, P = OSSecurity.Geometry, OSSecurity.ClientPlacement
    local wall = { id = 'm', position = { x = 10, y = 5, z = 2 }, normal = { x = 0, y = -1, z = 0 }, radius = 0.75 }
    local frame = G.frame(wall.normal)
    assert(math.abs(frame.up.z - 1) < 1e-9 and math.abs(frame.right.z) < 1e-9) -- pared vertical: Y es la altura
    local p, x, y = G.point(wall, 0.3, 0.2, 0.95)
    assert(math.abs(p.y - 5) < 1e-9 and math.abs(p.z - 2.2) < 1e-9 and math.abs(p.x - 10.3) < 1e-9) -- quien mira hacia +y tiene la derecha en +x
    p, x, y = G.point(wall, 5, 5, 0.95) -- fuera: se limita a la esquina del cuadrado, no a un circulo
    assert(math.abs(x - 0.7125) < 1e-9 and math.abs(y - 0.7125) < 1e-9 and G.inside(wall, p))
    assert(G.inside(wall, { x = 10.74, y = 5, z = 2.74 }) and not G.inside(wall, { x = 10.8, y = 5, z = 2 }))
    -- Mirando fuera de la pared: vector frontal (-sin h, cos h) igual a la normal
    local h = math.rad(P.heading(wall)); assert(math.abs(-math.sin(h)) < 1e-9 and math.abs(math.cos(h) + 1) < 1e-9)
    local ceiling = { id = 'c', position = { x = 0, y = 0, z = 3 }, normal = { x = 0, y = 0, z = -1 }, radius = 1 }
    p = G.point(ceiling, 0.5, -0.5); assert(math.abs(p.z - 3) < 1e-9 and G.inside(ceiling, p))
    local yaw, tilt, roll = P.initial(ceiling, 90); assert(yaw == 90 and tilt == -45 and roll == 180)
    assert(#G.corners(ceiling) == 4 and math.abs(G.corners(ceiling, 0.01)[1].z - 2.99) < 1e-9)
    assert(OSSecurity.ClientAnchor.size(0.75, 1) == 0.8 and OSSecurity.ClientAnchor.size(2, 1) == 2 and OSSecurity.ClientAnchor.size(0.25, -1) == 0.25)
    assert(OSSecurity.ClientAnchor.size(0.75, 1, true) == 0.76)
    -- Mover la zona fijada sobre la pared, con limite de 3 m desde el punto apuntado
    local moved, mx, my = OSSecurity.ClientAnchor.move({ x = 10, y = 5, z = 2 }, { x = 0, y = -1, z = 0 }, 0.5, 9)
    assert(math.abs(moved.x - 10.5) < 1e-9 and math.abs(moved.z - 5) < 1e-9 and moved.y == 5 and mx == 0.5 and my == 3)
end)

test('Placement asks for the installation minigame and only confirms when it is passed', function()
    local function setup(outcome)
        local c = { packets = {}, notes = {} }
        c.client = OSSecurity.ClientTablet.new({
            send = function(packet) c.packets[#c.packets + 1] = packet end, timeout = function() end,
            show = function() end, hide = function() end, cancelPlacement = function() end, props = function() end, expiry = function() end,
            beginPlacement = function(_, callback) c.confirm = callback end,
            minigame = function(callback) c.played = true; callback(outcome[1], outcome[2]) end,
            notify = function(message, kind) c.notes[#c.notes + 1] = { message, kind } end
        })
        c.client.useItem('os_cctv_kit')
        c.client.response(c.packets[#c.packets].id, { ok = true, session = { kind = 'inventory', token = 't', sequence = 0, expires = 9999999999, brand = OSSecurity.Brand } })
        c.client.response(c.packets[#c.packets].id, { ok = true, session = { kind = 'operations', token = 'o', sequence = 0, expires = 9999999999, brand = OSSecurity.Brand }, placement = { mounts = {} } })
        c.confirm({ anchorId = 'm', position = { x = 0, y = 0, z = 0 }, rotation = { x = 0, y = 0, z = 0 } })
        return c
    end
    local passed = setup({ true }); assert(passed.played and passed.packets[#passed.packets].action == 'place_confirm')
    local failed = setup({ false, nil }); assert(failed.packets[#failed.packets].action == 'place_cancel')
    failed.client.response(failed.packets[#failed.packets].id, { ok = true, data = { cancelled = true } })
    assert(failed.notes[#failed.notes][1] == OSSecurity.Brand.Text.installFailed and failed.notes[#failed.notes][2] == 'error')
    local left = setup({ false, 'cancelled' }); assert(left.packets[#left.packets].action == 'place_cancel')
    left.client.response(left.packets[#left.packets].id, { ok = true, data = { cancelled = true } })
    assert(left.notes[#left.notes][1] == 'Colocacion cancelada.')
end)

test('Minigame controller owns NUI focus only while running and reports a single result', function()
    local log = { sent = {}, focus = {}, anim = {} }
    local timers = {}
    local m = OSSecurity.ClientMinigame.new({ send = function(message) log.sent[#log.sent + 1] = message.type end,
        focus = function(value) log.focus[#log.focus + 1] = value end, animate = function(value) log.anim[#log.anim + 1] = value end,
        timeout = function(callback) timers[#timers + 1] = callback end })
    local results = {}
    m.run(function(ok, reason) results[#results + 1] = { ok, reason } end)
    assert(m.active() and log.sent[1] == 'minigame' and log.focus[1] == true and log.anim[1] == true)
    m.finish({ ok = true }); m.finish({ ok = false }) -- el segundo resultado se ignora
    assert(#results == 1 and results[1][1] == true and log.focus[2] == false and log.sent[2] == 'minigameClose' and not m.active())
    timers[1](); assert(#results == 1) -- el temporizador de una partida terminada no hace nada
    m.run(function(ok, reason) results[#results + 1] = { ok, reason } end); m.cancel()
    assert(results[2][1] == false and results[2][2] == 'cancelled')
    m.run(function(ok, reason) results[#results + 1] = { ok, reason } end); timers[3]()
    assert(results[3][1] == false and results[3][2] == nil)
end)

local function natives(run)
    local originals, queue, objects, calls = {}, {}, {}, { deleted = 0, made = 0, anim = 0 }
    local function stub(name, value) originals[name] = { rawget(_G, name) }; _G[name] = value end
    stub('CreateThread', function(callback) queue[#queue + 1] = callback end)
    stub('PlayerPedId', function() return 1 end)
    stub('GetGameTimer', function() return 1000 end)
    stub('SetNuiFocus', function(focus) calls.focus = focus end)
    stub('SendNUIMessage', function(message) calls.message = message end)
    stub('StopAnimTask', function() end)
    stub('RequestAnimDict', function() end)
    stub('HasAnimDictLoaded', function() return true end)
    stub('TaskPlayAnim', function() calls.anim = calls.anim + 1 end)
    stub('GetHashKey', function() return 1 end)
    stub('RequestModel', function() end)
    stub('HasModelLoaded', function() return true end)
    stub('IsModelInCdimage', function() return true end)
    stub('IsModelValid', function() return true end)
    stub('GetEntityCoords', function() return { x = 0, y = 0, z = 0 } end)
    stub('CreateObjectNoOffset', function(_, _, _, _, network, _, _)
        assert(network == false); calls.made = calls.made + 1; objects[calls.made] = true; return calls.made
    end)
    stub('DoesEntityExist', function(object) return objects[object] == true end)
    stub('DeleteEntity', function(object) assert(objects[object]); objects[object] = nil; calls.deleted = calls.deleted + 1 end)
    for _, name in ipairs({ 'SetEntityCollision', 'AttachEntityToEntity', 'SetModelAsNoLongerNeeded', 'FreezeEntityPosition',
        'SetEntityRotation', 'SetEntityAsMissionEntity', 'SetEntityAlpha' }) do stub(name, function() end) end
    stub('GetPedBoneIndex', function() return 28422 end)
    stub('SetEntityCoordsNoOffset', function(object, x, y, z) calls.coords = { object = object, x = x, y = y, z = z } end)
    stub('GetEntityHeading', function() return 0 end)
    stub('Wait', function() end)
    stub('IsEntityDead', function() return false end)
    stub('IsPedInAnyVehicle', function() return false end)
    stub('IsControlJustPressed', function(_, control) return control == 177 end)
    local ok, err = pcall(run, queue, objects, calls)
    for name, value in pairs(originals) do _G[name] = value[1] end
    assert(ok, err)
end

test('Rapid tablet switching cancels stale animation work and deletes its hand prop', function()
    natives(function(queue, objects, calls)
        local view = OSSecurity.ClientView.new()
        view.show({ kind = 'operations' }); view.show({ kind = 'client' })
        queue[1](); queue[2]()
        assert(calls.made == 1 and calls.anim == 1 and calls.focus)
        view.hide(); assert(calls.deleted == 1 and not calls.focus and next(objects) == nil)
    end)
end)

test('Local camera props stream in/out and are all cleaned without creating network entities', function()
    natives(function(queue, objects, calls)
        local props = OSSecurity.ClientProps.new()
        local a = { id = 'a', model = 'prop_cctv_cam_01a', position = { x = 0, y = 0, z = 0 }, rotation = { x = 0, y = 0, z = 0 } }
        local b = { id = 'b', model = 'prop_cctv_cam_01a', position = { x = 1, y = 0, z = 0 }, rotation = { x = 0, y = 0, z = 0 } }
        props.sync({ a, b }); queue[1](); assert(calls.made == 2)
        props.sync({ a }); queue[2](); assert(calls.deleted == 1 and calls.made == 2)
        props.clear(); assert(next(objects) == nil and calls.deleted == 2)
    end)
end)

test('Cancelling the preview deletes its temporary prop and calls back once', function()
    natives(function(queue, objects, calls)
        local placement = OSSecurity.ClientPlacement.new()
        local callbacks = 0
        placement.begin({ model = 'prop_cctv_cam_01a', seconds = 90, maxDistance = 4,
            mounts = { { id = 'm', position = { x = 1, y = 0, z = 1 }, normal = { x = -1, y = 0, z = 0 }, radius = 0.75 } } }, function(result)
            assert(result == nil); callbacks = callbacks + 1
        end)
        queue[1]()
        assert(callbacks == 1 and calls.made == 1 and calls.deleted == 1 and next(objects) == nil)
    end)
end)
