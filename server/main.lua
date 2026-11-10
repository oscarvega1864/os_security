local config = OSSecurity.Config
local constants = OSSecurity.Constants
local resourceName = GetCurrentResourceName()
local serverConfig = OSSecurity.ServerConfig

local isAceAllowed = OSSecurity.AdminAccess.new({
    ace = IsPlayerAceAllowed, state = GetResourceState,
    permission = serverConfig.AdminAce, resource = serverConfig.AdminAuthorizationResource,
    delegate = function(resource, player, permission)
        return exports[resource]:HasOscarPermission(player, permission)
    end
})

local function storageLog(message)
    print(('%s [ERROR] %s'):format(constants.LOG_PREFIX, message))
end

local resourceFiles = OSSecurity.ResourceFiles.new({
    resource = resourceName,
    load = LoadResourceFile,
    save = SaveResourceFile,
    open = function(...) return io.open(...) end
})

local permissions = OSSecurity.Permissions.new({
    ace = serverConfig.AdminAce,
    limits = serverConfig,
    isAceAllowed = isAceAllowed,
    now = os.time
})

local store = OSSecurity.JsonStorage.new({
    base = serverConfig.StorageBase,
    limits = serverConfig,
    read = resourceFiles.read,
    write = resourceFiles.write,
    encode = OSSecurity.JsonCodec.encode,
    decode = OSSecurity.JsonCodec.decode,
    log = storageLog,
    trace = config.Debug and function(message)
        print(('%s [DEBUG] %s'):format(constants.LOG_PREFIX, message))
    end or nil
})

-- API interna del servidor; sin exports ni eventos de red administrativos.
OSSecurity.Registry = OSSecurity.DeviceRegistry.new({
    store = store, limits = serverConfig, authorize = permissions.authorize, now = os.time
})
local registry = OSSecurity.Registry

-- Comandos guardados por nombre para que el panel de os_admin los ejecute recogiendo sus respuestas.
local commandHandlers, panelCapture = {}, { current = nil }
local function registerCommand(name, handler, restricted)
    commandHandlers[name] = handler
    return RegisterCommand(name, handler, restricted)
end

local commandOptions = {
    registry = registry,
    permissions = permissions,
    register = registerCommand,
    defaultPageSize = serverConfig.DefaultPageSize,
    encode = json.encode,
    reply = function(source, message)
        local capture = panelCapture.current
        if capture and capture.source == source then capture.lines[#capture.lines + 1] = tostring(message); return end
        if source == 0 then
            print(('%s %s'):format(constants.LOG_PREFIX, message))
        else
            TriggerClientEvent('chat:addMessage', source, {
                args = { constants.CHAT_TITLE, message }
            })
        end
    end
}
OSSecurity.DeviceCommands.register(commandOptions)
OSSecurity.MaintenanceCommands.register(commandOptions)

local function world(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil, nil end
    local position = GetEntityCoords(ped)
    if not position then return nil, nil end
    return { x = position.x, y = position.y, z = position.z }, GetPlayerRoutingBucket(source)
end

-- Proveedor de objetos. Por defecto 'standalone' (portable). Con
--   set ossecurity_items os_inventory
-- los objetos pertenecen al personaje activo de os_devtools y se guardan en os_inventory.
local itemProvider = GetConvar('ossecurity_items', 'standalone')
local inventoryResource = GetConvar('ossecurity_items_resource', 'os_inventory')
local identityResource = GetConvar('ossecurity_identity_resource', 'os_devtools')
local externalItems
if itemProvider == 'os_inventory' then
    externalItems = OSSecurity.ExternalItems.new({
        available = function()
            return GetResourceState(inventoryResource) == 'started' and GetResourceState(identityResource) == 'started'
        end,
        holder = function(source)
            local dto = exports[identityResource]:GetActiveCharacter(source)
            return type(dto) == 'table' and dto.characterId or nil
        end,
        count = function(holder, item) return exports[inventoryResource]:GetItemCount(holder, item) end,
        add = function(holder, item, amount, operationId) return exports[inventoryResource]:AddItem(holder, item, amount, nil, operationId) end,
        remove = function(holder, item, amount, operationId) return exports[inventoryResource]:RemoveItem(holder, item, amount, nil, operationId) end,
        inventory = function(holder) return exports[inventoryResource]:GetInventory(holder) end,
        addMeta = function(holder, item, amount, meta, operationId) return exports[inventoryResource]:AddItem(holder, item, amount, meta, operationId) end,
        removeMeta = function(holder, item, amount, meta, operationId) return exports[inventoryResource]:RemoveItem(holder, item, amount, meta, operationId) end
    })
elseif itemProvider ~= 'standalone' then
    storageLog(('ossecurity_items=%s no reconocido; se usa standalone.'):format(itemProvider))
end

-- Perfil G6 por empleo del personaje activo. Por defecto lo lee de ossecurity_identity_resource;
--   set ossecurity_employment_resource none
-- lo desactiva y deja solo los ACE.
local employmentResource = GetConvar('ossecurity_employment_resource', identityResource)
local employment = OSSecurity.Employment.new({
    settings = OSSecurity.GameplayConfig.Employment,
    read = employmentResource ~= 'none' and function(source)
        if GetResourceState(employmentResource) ~= 'started' then return nil end
        return exports[employmentResource]:GetActiveEmployment(source)
    end or nil
})

-- Dinero de la tienda G6: cobra y devuelve al personaje activo. Por defecto os_devtools
-- (ChargeCharacter / PayCharacter / GetCharacterBalance).   set ossecurity_money_resource none   la cierra.
local moneyResource = GetConvar('ossecurity_money_resource', identityResource)
local MAX_REFUND_CHUNK = 50000 -- tope por ingreso del proveedor (MaxPayment de os_devtools)
local money = {
    available = function() return moneyResource ~= 'none' and GetResourceState(moneyResource) == 'started' end,
    balance = function(source)
        local ok, balance = pcall(function() return exports[moneyResource]:GetCharacterBalance(source) end)
        return ok and type(balance) == 'table' and balance or nil
    end,
    charge = function(source, amount, account, reason)
        local ok, done, err = pcall(function() return exports[moneyResource]:ChargeCharacter(source, amount, account, reason) end)
        if not ok then return false, 'provider_error' end
        return done == true, err
    end,
    refund = function(source, amount, account, reason)
        local left = amount
        while left > 0 do
            local part = math.min(left, MAX_REFUND_CHUNK)
            local ok, done = pcall(function() return exports[moneyResource]:PayCharacter(source, part, account, reason) end)
            if not ok or done ~= true then return false end
            left = left - part
        end
        return true
    end
}

-- Propiedades y negocios: el titular del personaje activo ve en la tablet Client los dispositivos vinculados.
--   set ossecurity_sites_resource none   lo desactiva.
local sitesResource = GetConvar('ossecurity_sites_resource', identityResource)
local sites = sitesResource ~= 'none' and OSSecurity.Sites.new({
    asset = function(category, id)
        if GetResourceState(sitesResource) ~= 'started' then return nil end
        return exports[sitesResource]:GetAsset(category, id)
    end,
    list = function(category)
        if GetResourceState(sitesResource) ~= 'started' then return nil end
        return exports[sitesResource]:ListAssets(category)
    end,
    active = function(source)
        if GetResourceState(identityResource) ~= 'started' then return nil end
        return exports[identityResource]:GetActiveCharacter(source)
    end
}) or nil

-- Presencia en el interior de cada central (deviceId -> dentro), comunicada por el cliente cada 2 s
-- solo para centrales instaladas dentro de un interior. Caduca a los 6 s; sin dato se usa la esfera.
local alarmPresence = {}
RegisterNetEvent('os_security:alarm:presence', function(map)
    local player = source
    if type(map) ~= 'table' then return end
    local inside, count = {}, 0
    for deviceId, value in pairs(map) do
        count = count + 1
        if count > 16 then return end
        if OSSecurity.DeviceValidation.id(deviceId) and type(value) == 'boolean' then inside[deviceId] = value end
    end
    alarmPresence[player] = { at = GetGameTimer(), inside = inside }
end)
AddEventHandler('playerDropped', function() alarmPresence[source] = nil end)

-- Efectos de las alarmas en el juego: jugadores conectados, hash del codigo, sirena y avisos.
local alarmEffects = {
    players = function()
        local list = {}
        for _, value in ipairs(GetPlayers()) do
            local player = tonumber(value)
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 then
                local point = GetEntityCoords(ped)
                local presence = alarmPresence[player]
                list[#list + 1] = { source = player, position = { x = point.x, y = point.y, z = point.z }, bucket = GetPlayerRoutingBucket(player),
                    inside = presence and GetGameTimer() - presence.at <= 6000 and presence.inside or nil }
            end
        end
        return list
    end,
    hash = function(pin) return GetPasswordHash(pin) end,
    -- El binding de Lua devuelve el BOOL nativo como entero (1/0), igual que SaveResourceFile.
    verify = function(pin, hash) local result = VerifyPasswordHash(pin, hash); return result == true or result == 1 end,
    serial = function() return ('%08X'):format(math.random(0, 0x7fffffff)) end,
    who = function(player)
        if GetResourceState(identityResource) == 'started' then
            local ok, dto = pcall(function() return exports[identityResource]:GetActiveCharacter(player) end)
            if ok and type(dto) == 'table' and type(dto.alias) == 'string' then return dto.alias:sub(1, 64) end
        end
        return ('jugador %d'):format(player)
    end,
    entry = function(player, device, seconds) TriggerClientEvent('os_security:alarm:entry', player, device.id, seconds, device.position) end,
    entryStop = function(deviceId) TriggerClientEvent('os_security:alarm:entry', -1, deviceId, 0) end,
    siren = function(deviceId, device) TriggerClientEvent('os_security:alarm:siren', -1, deviceId, device and device.position or nil) end,
    notify = function(player, text, kind, position) TriggerClientEvent('os_security:alarm:alert', player, text, kind, position) end
}

-- Vehiculos de os_devtools (cierre centralizado y alarma): datos de la entidad y efectos en el juego.
local function activeAlias(player)
    if GetResourceState(identityResource) ~= 'started' then return nil end
    local ok, dto = pcall(function() return exports[identityResource]:GetActiveCharacter(player) end)
    return ok and type(dto) == 'table' and type(dto.alias) == 'string' and dto.alias or nil
end
local function vehicleOf(netId)
    if type(netId) ~= 'number' or netId % 1 ~= 0 then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
    local p = GetEntityCoords(entity)
    return { entity = entity, netId = netId, plate = GetVehicleNumberPlateText(entity), position = { x = p.x, y = p.y, z = p.z },
        bucket = GetEntityRoutingBucket(entity) }
end
-- Vehiculo mas cercano al jugador que cumpla 'accept' (para la ganzua): lo elige el servidor, no el cliente,
-- y salta los que no valen (trafico, coches abiertos) aunque esten mas cerca.
local function nearestVehicle(player, radius, accept)
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 then return nil end
    local here, bucket = GetEntityCoords(ped), GetPlayerRoutingBucket(player)
    local candidates = {}
    for _, entity in ipairs(GetAllVehicles()) do
        local d = #(GetEntityCoords(entity) - here)
        if d <= radius and GetEntityRoutingBucket(entity) == bucket then candidates[#candidates + 1] = { entity = entity, d = d } end
    end
    table.sort(candidates, function(a, b) return a.d < b.d end)
    for _, candidate in ipairs(candidates) do
        local vehicle = vehicleOf(NetworkGetNetworkIdFromEntity(candidate.entity))
        if vehicle and (not accept or accept(vehicle)) then return vehicle end
    end
    return nil
end
local function playersNear(position, radius)
    local list = {}
    for _, value in ipairs(GetPlayers()) do
        local player = tonumber(value)
        local ped = GetPlayerPed(player)
        if ped and ped ~= 0 then
            local p = GetEntityCoords(ped)
            if math.sqrt((p.x - position.x) ^ 2 + (p.y - position.y) ^ 2 + (p.z - position.z) ^ 2) <= radius then list[#list + 1] = player end
        end
    end
    return list
end
local function carState(entity, want)
    local current = Entity(entity).state.g6car
    if type(current) ~= 'table' or current.locked ~= want.locked or current.alarm ~= want.alarm then
        Entity(entity).state:set('g6car', { locked = want.locked, alarm = want.alarm }, true)
    end
    local target = want.locked and 2 or 1
    if GetVehicleDoorLockStatus(entity) ~= target then SetVehicleDoorsLocked(entity, target) end
end
local carVehicles = {
    asset = function(id)
        if GetResourceState(sitesResource) ~= 'started' then return nil end
        return exports[sitesResource]:GetAsset('vehicles', id)
    end,
    alias = activeAlias,
    -- Posicion de un vehiculo por matricula (Localizadores de la tablet Client), redondeada.
    locate = function(plate)
        for _, entity in ipairs(GetAllVehicles()) do
            local text = GetVehicleNumberPlateText(entity)
            if type(text) == 'string' and (text:gsub('%s+', '')) == plate then
                local p = GetEntityCoords(entity)
                return { x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10, z = math.floor(p.z * 10 + 0.5) / 10 }
            end
        end
        return nil
    end,
    -- Vehiculo que conduce el jugador, como descriptor (para efectos como la alarma).
    entity = function(player)
        local ped = GetPlayerPed(player)
        local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
        if vehicle == 0 then return nil end
        return vehicleOf(NetworkGetNetworkIdFromEntity(vehicle))
    end,
    driving = function(player)
        local ped = GetPlayerPed(player)
        if not ped or ped == 0 then return nil end
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not vehicle or vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
        local v = GetEntityVelocity(vehicle)
        return { plate = GetVehicleNumberPlateText(vehicle), engine = GetIsVehicleEngineRunning(vehicle) == true or GetIsVehicleEngineRunning(vehicle) == 1,
            speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) }
    end
}
local carEffects = {
    locked = function(vehicle, locked, alarm, remote)
        carState(vehicle.entity, { locked = locked, alarm = alarm == true })
        for _, player in ipairs(playersNear(vehicle.position, 60.0)) do TriggerClientEvent('os_security:car:fx', player, vehicle.netId, locked, remote == true) end
    end,
    alarm = function(vehicle, seconds)
        for _, player in ipairs(playersNear(vehicle.position, OSSecurity.GameplayConfig.Cars.AlarmHearing)) do
            TriggerClientEvent('os_security:car:alarm', player, vehicle.netId, seconds)
        end
    end,
    notifyOwner = function(alias, text, position)
        for _, value in ipairs(GetPlayers()) do
            local player = tonumber(value)
            if activeAlias(player) == alias then TriggerClientEvent('os_security:alarm:alert', player, text, 'warning', position) end
        end
    end
}

-- El salt nativo se obtiene una sola vez: bcrypt no debe bloquear cada apertura.
-- El nonce siempre se valida junto al source, secuencia, identidad, item y ACE.
local sessionSalt
local gameplay = OSSecurity.Gameplay.new({
    registry = registry, files = resourceFiles, permissions = permissions,
    register = registerCommand, reply = commandOptions.reply, now = os.time,
    connected = function(source) return GetPlayerName(source) ~= nil end,
    identifier = function(source) return GetPlayerIdentifierByType(source, 'license') end,
    ace = isAceAllowed,
    alive = function(source)
        local ped = GetPlayerPed(source)
        return ped ~= nil and ped ~= 0 and GetEntityHealth(ped) > 0
    end,
    world = world,
    schedule = function(callback) SetTimeout(500, callback) end,
    token = function(source, counter)
        if not sessionSalt then sessionSalt = GetPasswordHash(('g6:%d:%d'):format(source, os.time())) end
        return ('%s:%d:%d'):format(sessionSalt, source, counter)
    end,
    employeeId = function(principal) return OSSecurity.Brand.EmployeePrefix .. '-' .. ('%08X'):format(GetHashKey(principal) & 0xffffffff) end,
    log = storageLog,
    items = externalItems,
    employment = employment,
    alarmEffects = alarmEffects,
    sites = sites,
    -- Clientes de una zona de montaje: jugadores conectados y su nombre (personaje · cuenta).
    players = function()
        local list = {}
        for _, value in ipairs(GetPlayers()) do list[#list + 1] = tonumber(value) end
        return list
    end,
    playerName = function(player)
        local name, alias = GetPlayerName(player), activeAlias(player)
        if alias and name then return alias .. ' · ' .. name end
        return alias or name
    end,
    locksChanged = function(list) TriggerClientEvent('os_security:locks:doors', -1, list) end,
    vehicles = carVehicles, carEffects = carEffects, money = money,
    shopMoved = function(list) TriggerClientEvent('os_security:shop:locations', -1, list) end,
    -- Avisos de ordenes de trabajo (mismo aviso que las alarmas: texto y, si hay, punto en el mapa).
    notifyPlayer = function(player, text, kind, position) TriggerClientEvent('os_security:alarm:alert', player, text, kind, position) end,
    audit = function(action, source, deviceId)
        local safeId = OSSecurity.DeviceValidation.id(deviceId) and deviceId or '-'
        print(('%s [G6 AUDIT] action=%s source=%d device=%s'):format(constants.LOG_PREFIX, action, source, safeId))
    end
})

RegisterNetEvent('os_security:g6:request', function(request)
    local player = source -- La identidad proviene del origen real, nunca del payload.
    if not OSSecurity.Util.integer(player, 1, 2147483647) then return end
    local requestId = type(request) == 'table' and request.id or nil
    if not OSSecurity.Util.integer(requestId, 1, 2147483647) then return end
    local ok, response = pcall(gameplay.handle, player, request)
    if not ok then
        storageLog('Fallo de solicitud G6; no se registra el payload ni la excepcion.')
        response = { ok = false, error = OSSecurity.Brand.Text.failed, close = true }
    end
    TriggerClientEvent('os_security:g6:response', player, requestId, response)
end)

-- /g6anchor: punto y normal apuntados por un administrador; el servidor revalida todo.
local lastAnchorAim = {}
RegisterNetEvent('os_security:g6:anchorAim', function(payload)
    local player = source
    if not OSSecurity.Util.integer(player, 1, 2147483647) then return end
    local now = GetGameTimer()
    if lastAnchorAim[player] and now - lastAnchorAim[player] < 1000 then return end
    lastAnchorAim[player] = now
    local ok, message, err = pcall(gameplay.anchorAt, player, payload)
    if not ok then message, err = nil, OSSecurity.Brand.Text.failed end
    TriggerClientEvent('os_security:g6:anchorResult', player, message ~= nil, message or err)
end)

-- Zona de montaje marcada con el visor desde la tablet G6 Operations.
RegisterNetEvent('os_security:g6:zoneAim', function(payload)
    local player = source
    if not OSSecurity.Util.integer(player, 1, 2147483647) then return end
    local now = GetGameTimer()
    if lastAnchorAim[player] and now - lastAnchorAim[player] < 1000 then return end
    lastAnchorAim[player] = now
    local ok, result, err = pcall(gameplay.zoneAt, player, payload)
    if not ok then result, err = nil, OSSecurity.Brand.Text.failed end
    TriggerClientEvent('os_security:g6:zoneResult', player, result ~= nil, result and result.message or err)
end)

-- Teclado y lector de chapa de las alarmas (junto al dispositivo; el servidor comprueba la distancia).
local alarmRate = {}
local function alarmAllowed(player)
    local now = GetGameTimer()
    local entry = alarmRate[player]
    if not entry or now - entry.start > 2000 then entry = { start = now, count = 0 }; alarmRate[player] = entry end
    entry.count = entry.count + 1
    return entry.count <= 5 and gameplay.status()
end
local function alarmCall(player, callback)
    local ok, result, err = pcall(callback)
    if not ok then storageLog('Fallo en la alarma; no se registra la excepcion.'); return nil, OSSecurity.Brand.Text.failed end
    return result, err
end
RegisterNetEvent('os_security:alarm:panel', function(deviceId)
    local player = source
    if not alarmAllowed(player) then return end
    local data, err = alarmCall(player, function() return gameplay.alarms.panel(player, deviceId) end)
    TriggerClientEvent('os_security:alarm:panelData', player, data, err)
end)
RegisterNetEvent('os_security:alarm:keypad', function(deviceId, action, pin)
    local player = source
    if not alarmAllowed(player) then return end
    local result, err = alarmCall(player, function() return gameplay.alarms.keypad(player, deviceId, action, pin) end)
    local panel = gameplay.alarms.panel(player, deviceId)
    TriggerClientEvent('os_security:alarm:result', player, result, err, panel)
end)
RegisterNetEvent('os_security:alarm:tag', function(deviceId)
    local player = source
    if not alarmAllowed(player) then return end
    local result, err = alarmCall(player, function() return gameplay.alarms.tag(player, deviceId) end)
    local panel = gameplay.alarms.panel(player, deviceId)
    TriggerClientEvent('os_security:alarm:result', player, result, err, panel)
end)
CreateThread(function()
    while true do
        Wait(1000)
        if gameplay.status() then
            local ok = pcall(gameplay.alarms.tick)
            if not ok then storageLog('Fallo en la vigilancia de alarmas; se reintentara.') end
        end
    end
end)

-- Cerraduras de puertas: lista para los clientes, deteccion automatica, llave, cambio de bombin y apano manual.
local lockRate = {}
local function lockAllowed(player, limit)
    local now = GetGameTimer()
    local entry = lockRate[player]
    if not entry or now - entry.start > 5000 then entry = { start = now, count = 0 }; lockRate[player] = entry end
    entry.count = entry.count + 1
    return entry.count <= (limit or 6) and gameplay.status()
end
local function lockCall(callback)
    local ok, result, err, extra = pcall(callback)
    if not ok then storageLog('Fallo en las cerraduras; no se registra la excepcion.'); return nil, OSSecurity.Brand.Text.failed end
    return result, err, extra
end
RegisterNetEvent('os_security:locks:sync', function()
    local player = source
    if not lockAllowed(player) then return end
    local doors, targets = lockCall(function() return gameplay.locks.list(), gameplay.locks.targets() end)
    TriggerClientEvent('os_security:locks:doors', player, doors or {}, targets or {})
end)
RegisterNetEvent('os_security:locks:report', function(report)
    local player = source
    if not lockAllowed(player) then return end
    lockCall(function() return gameplay.locks.report(player, report) end)
end)
RegisterNetEvent('os_security:locks:toggle', function(doorId)
    local player = source
    if not lockAllowed(player) then return end
    local result, err = lockCall(function() return gameplay.locks.toggle(player, type(doorId) == 'string' and doorId or nil) end)
    TriggerClientEvent('os_security:locks:result', player, result ~= nil, result and result.message or err, result and result.locked)
end)
RegisterNetEvent('os_security:locks:changeFinish', function(success)
    local player = source
    if not lockAllowed(player) then return end
    local result, err = lockCall(function() return gameplay.locks.changeFinish(player, success == true) end)
    TriggerClientEvent('os_security:locks:result', player, result ~= nil, result and result.message or err)
end)
RegisterNetEvent('os_security:locks:register', function(payload)
    local player = source
    if not lockAllowed(player, 2) then return end
    local message, err
    if type(payload) == 'table' and payload.remove == true then
        message, err = lockCall(function() return gameplay.locks.unregister(player) end)
    else
        message, err = lockCall(function() return gameplay.locks.register(player, payload) end)
    end
    TriggerClientEvent('os_security:locks:result', player, message ~= nil, message or err)
end)
-- Vehiculos: mando (abrir/cerrar), intentos de entrar con el vehiculo cerrado e instalacion.
RegisterNetEvent('os_security:car:toggle', function(netId)
    local player = source
    if not lockAllowed(player) then return end
    local result, err = lockCall(function() return gameplay.cars.toggle(player, vehicleOf(netId)) end)
    TriggerClientEvent('os_security:car:result', player, result ~= nil, result and result.message or err, result and result.locked)
end)
RegisterNetEvent('os_security:car:tamper', function(netId)
    local player = source
    if not lockAllowed(player) then return end
    local result, err = lockCall(function() return gameplay.cars.tamper(player, vehicleOf(netId)) end)
    if not result and err then TriggerClientEvent('os_security:car:result', player, false, err) end
end)
-- Tienda G6: catalogo al acercarse al mostrador y compra validada en el servidor.
RegisterNetEvent('os_security:shop:open', function()
    local player = source
    if not lockAllowed(player) then return end
    local data, err = lockCall(function() return gameplay.shop.catalog(player) end)
    TriggerClientEvent('os_security:shop:catalog', player, data ~= nil, data or err)
end)
-- Ubicacion del mostrador: al entrar y cada vez que un administrador la mueve desde F10.
RegisterNetEvent('os_security:shop:locations', function()
    local player = source
    if not lockAllowed(player) then return end
    TriggerClientEvent('os_security:shop:locations', player, gameplay.shop.locations())
end)
-- Punto de carretera calculado por el cliente del administrador (F10 > Tienda en la calle).
RegisterNetEvent('os_security:shop:roadPoint', function(point)
    local player = source
    if not lockAllowed(player) then return end
    local message, err = lockCall(function() return gameplay.shop.move(player, 'road', point) end)
    TriggerClientEvent('os_security:shop:moved', player, message ~= nil, message or err)
end)
RegisterNetEvent('os_security:shop:buy', function(cart, account)
    local player = source
    if not lockAllowed(player) then return end
    local result, err = lockCall(function() return gameplay.shop.buy(player, cart, account) end)
    TriggerClientEvent('os_security:shop:result', player, result ~= nil, result or err)
end)

RegisterNetEvent('os_security:car:engine', function()
    local player = source
    if not lockAllowed(player) then return end
    local result, err, canHotwire = lockCall(function() return gameplay.cars.engine(player) end)
    TriggerClientEvent('os_security:car:engineResult', player, result ~= nil, err, canHotwire == true)
end)
RegisterNetEvent('os_security:car:hotwire', function()
    local player = source
    if not lockAllowed(player) then return end
    local challenge, err = lockCall(function() return gameplay.cars.hotwireBegin(player) end)
    if challenge then TriggerClientEvent('os_security:car:hotwireStart', player, challenge)
    else TriggerClientEvent('os_security:car:result', player, false, err) end
end)
RegisterNetEvent('os_security:car:hotwireFinish', function(success)
    local player = source
    if not lockAllowed(player) then return end
    local result, err = lockCall(function() return gameplay.cars.hotwireFinish(player, success == true) end)
    TriggerClientEvent('os_security:car:hotwireResult', player, result ~= nil, result and result.message or err)
end)
RegisterNetEvent('os_security:car:installFinish', function(success)
    local player = source
    if not lockAllowed(player) then return end
    local result, err = lockCall(function() return gameplay.cars.installFinish(player, success == true) end)
    TriggerClientEvent('os_security:car:result', player, result ~= nil, result and result.message or err)
end)
-- Ganzua: resultado del minijuego de pines.
RegisterNetEvent('os_security:lockpick:finish', function(result)
    local player = source
    if not lockAllowed(player) then return end
    local outcome, err = lockCall(function() return gameplay.lockpick.finish(player, result == 'cancel' and 'cancel' or result == true) end)
    TriggerClientEvent('os_security:lockpick:result', player, outcome ~= nil and outcome.ok == true, outcome and outcome.message or err, outcome and outcome.broken == true)
end)

-- Las entidades nacen abiertas: cada pocos segundos se les aplica el estado guardado (puertas y state bag).
CreateThread(function()
    while true do
        Wait(OSSecurity.GameplayConfig.Cars.SyncSeconds * 1000)
        if gameplay.status() then
            local ok = pcall(function()
                gameplay.cars.tick()
                for _, entity in ipairs(GetAllVehicles()) do
                    local want = gameplay.cars.desired(GetVehicleNumberPlateText(entity))
                    if want then carState(entity, want) end
                end
            end)
            if not ok then storageLog('Fallo en la sincronizacion de vehiculos; se reintentara.') end
        end
    end
end)

-- Nivel del bombin (1 serie, 2 seguridad, 3 alta seguridad) de una puerta, para robos o ganzuas.
exports('GetDoorSecurity', function(doorId)
    local ok, tier = pcall(gameplay.locks.security, doorId)
    return ok and tier or nil
end)

AddEventHandler('playerDropped', function()
    lockRate[tonumber(source)] = nil
    alarmRate[tonumber(source)] = nil
    gameplay.alarms.forget(tonumber(source))
    lastAnchorAim[tonumber(source)] = nil
    permissions.forget(tonumber(source))
    gameplay.drop(tonumber(source))
end)

-- Con proveedor externo, un cambio de personaje cierra las sesiones G6 abiertas con el anterior.
AddEventHandler('osdev:characterChanged', function(player)
    if externalItems and OSSecurity.Util.integer(player, 1, 2147483647) then gameplay.drop(player) end
end)

-- "Usar" desde os_inventory: cierra su interfaz y pide al cliente abrir la tablet o, para el kit CCTV,
-- iniciar la colocacion. Ambas vuelven a pasar por la autorizacion completa del servidor
-- (objeto, ACE, perfil, herramientas, materiales y montaje); nada se cobra hasta confirmar.
local function registerUsableTablets()
    if not externalItems or GetResourceState(inventoryResource) ~= 'started' then return end
    for item, definition in pairs(OSSecurity.ItemCatalog) do
        if definition.tablet or ({ placement = true, tag = true, cylinder = true, car = true, lockpick = true })[definition.usable] then
            local ok, registered = pcall(function()
                return exports[inventoryResource]:RegisterUsableItem(item, function(player)
                    TriggerClientEvent('osinventory:forceClose', player)
                    if definition.tablet then TriggerClientEvent('os_security:g6:openTablet', player, definition.tablet)
                    elseif definition.usable == 'lockpick' then
                        local challenge, err = lockCall(function()
                            return gameplay.lockpick.begin(player, nearestVehicle(player, OSSecurity.GameplayConfig.Lockpick.VehicleReach,
                                function(vehicle) return gameplay.cars.pickTarget(vehicle) ~= nil end))
                        end)
                        if challenge then TriggerClientEvent('os_security:lockpick:start', player, challenge)
                        else TriggerClientEvent('os_security:lockpick:result', player, false, err, false) end
                    elseif definition.usable == 'car' then
                        local data, err = lockCall(function() return gameplay.cars.installBegin(player, item) end)
                        if data then TriggerClientEvent('os_security:car:install', player, data)
                        else TriggerClientEvent('os_security:car:result', player, false, err) end
                    elseif definition.usable == 'cylinder' then
                        local data, err = lockCall(function() return gameplay.locks.changeBegin(player, item) end)
                        if data then TriggerClientEvent('os_security:locks:change', player, data)
                        else TriggerClientEvent('os_security:locks:result', player, false, err) end
                    elseif definition.usable == 'tag' then
                        local result, err = gameplay.alarms.tagNearest(player)
                        TriggerClientEvent('os_security:alarm:result', player, result, err, nil)
                    else TriggerClientEvent('os_security:g6:useItem', player, item) end
                end)
            end)
            if not ok or not registered then storageLog(('No se pudo registrar el uso de %s en %s.'):format(item, inventoryResource)) end
        end
    end
end
AddEventHandler('onResourceStart', function(started)
    if started == inventoryResource then registerUsableTablets() end
end)

-- Panel y consola de os_admin (opcional).
OSSecurity.AdminPanel.hooks = {
    anchorEditor = function(player, payload) TriggerClientEvent('os_security:g6:anchorEditor', player, payload) end,
    aimDoor = function(player, site) TriggerClientEvent('os_security:locks:aimDoor', player, site) end,
    removeNearDoor = function(player) return gameplay.locks.unregister(player) end,
    shopRoad = function(player) TriggerClientEvent('os_security:shop:findRoad', player, OSSecurity.ShopConfig.RoadFrom) end,
    shopHere = function(player) return gameplay.shop.move(player, 'here') end
}
local runPanelCommand = OSSecurity.AdminPanel.runner(commandHandlers, panelCapture)
OSSecurity.AdminPanelRun = runPanelCommand
AddEventHandler('os_admin:ready', function() OSSecurity.AdminPanel.publish(runPanelCommand) end)

RegisterCommand('osstatus', function(source)
    local ready = registry.status()
    local message = ('Estado: %s | Version: %s | Device Core: %s'):format(
        GetResourceState(resourceName),
        config.Version,
        ready and 'disponible' or 'bloqueado (revisar consola)'
    )

    print(('%s %s'):format(constants.LOG_PREFIX, message))

    -- Si se ejecuta desde el juego, responde solo al jugador que lo solicita.
    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, {
            args = { constants.CHAT_TITLE, message }
        })
    end
end, false)

AddEventHandler('onResourceStart', function(startedResource)
    if startedResource ~= resourceName then
        return
    end

    print(('%s Recurso iniciado. Version: %s'):format(constants.LOG_PREFIX, config.Version))

    local loaded, err = registry.load()
    if loaded then
        print(('%s Device Core: almacenamiento cargado.'):format(constants.LOG_PREFIX))
    else
        storageLog('Device Core bloqueado: ' .. tostring(err))
    end

    local gameLoaded, gameError = gameplay.load()
    if not gameLoaded then storageLog('Flujo Gruppe Sechs bloqueado: ' .. tostring(gameError)) end
    print(('%s Objetos: %s'):format(constants.LOG_PREFIX, externalItems and ('%s por personaje (%s)'):format(inventoryResource, identityResource) or 'registro local (standalone)'))
    registerUsableTablets()
    OSSecurity.AdminPanel.publish(runPanelCommand)

    if config.Debug then
        print(('%s [DEBUG] Nombre del recurso: %s'):format(constants.LOG_PREFIX, resourceName))
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then
        return
    end

    gameplay.clear()

    print(('%s Recurso detenido. Version: %s'):format(constants.LOG_PREFIX, config.Version))
end)
