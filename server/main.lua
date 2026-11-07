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

local commandOptions = {
    registry = registry,
    permissions = permissions,
    register = RegisterCommand,
    defaultPageSize = serverConfig.DefaultPageSize,
    encode = json.encode,
    reply = function(source, message)
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

-- El salt nativo se obtiene una sola vez: bcrypt no debe bloquear cada apertura.
-- El nonce siempre se valida junto al source, secuencia, identidad, item y ACE.
local sessionSalt
local gameplay = OSSecurity.Gameplay.new({
    registry = registry, files = resourceFiles, permissions = permissions,
    register = RegisterCommand, reply = commandOptions.reply, now = os.time,
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

AddEventHandler('playerDropped', function()
    permissions.forget(tonumber(source))
    gameplay.drop(tonumber(source))
end)

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
