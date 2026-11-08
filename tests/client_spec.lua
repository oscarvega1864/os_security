local test = StorageTest.test
dofile('/repo/client/tablet.lua')
dofile('/repo/client/view.lua')
dofile('/repo/client/props.lua')
dofile('/repo/client/placement.lua')

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

test('Placement editor keeps the camera on the mount plane, inside its radius, facing out of the wall', function()
    local P = OSSecurity.ClientPlacement
    local mount = { id = 'm', position = { x = 10, y = 5, z = 2 }, normal = { x = 0, y = -1, z = 0 }, radius = 0.75 }
    local frame = P.frame(mount)
    assert(math.abs(frame.up.z - 1) < 1e-9 and math.abs(frame.right.z) < 1e-9) -- pared vertical: Y es la altura
    local offset = { x = 0.3, y = 0.2 }; local p = P.compose(mount, offset)
    assert(math.abs(p.y - 5) < 1e-9 and math.abs(p.z - 2.2) < 1e-9 and math.abs(p.x - 10.3) < 1e-9) -- quien mira hacia +y tiene la derecha en +x
    offset = { x = 5, y = 0 }; p = P.compose(mount, offset) -- fuera del radio: se limita
    assert(math.abs(offset.x - 0.75 * 0.95) < 1e-9 and math.abs(p.y - 5) < 1e-9)
    -- Mirando fuera de la pared: vector frontal (-sin h, cos h) igual a la normal
    local h = math.rad(P.heading(mount)); assert(math.abs(-math.sin(h) - 0) < 1e-9 and math.abs(math.cos(h) + 1) < 1e-9)
    local floor = { id = 'f', position = { x = 0, y = 0, z = 0 }, normal = { x = 0, y = 0, z = 1 }, radius = 1 }
    p = P.compose(floor, { x = 0.5, y = 0 }); assert(math.abs(p.z) < 1e-9 and P.heading(floor) == 0.0)
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
