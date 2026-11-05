local config = OSSecurity.Config
local constants = OSSecurity.Constants
local resourceName = GetCurrentResourceName()
local serverConfig = OSSecurity.ServerConfig

local function storageLog(message)
    print(('%s [ERROR] %s'):format(constants.LOG_PREFIX, message))
end

local function readResourceFile(path)
    local content = LoadResourceFile(resourceName, path)
    if content ~= nil then return content end
    -- LoadResourceFile devuelve nil tanto por ausencia como por errores de
    -- acceso. io.open solo distingue esos casos; no sustituye la lectura nativa.
    local file, _, code = io.open(('@%s/%s'):format(resourceName, path), 'rb')
    if file then
        file:close()
        return nil, 'El archivo existe pero LoadResourceFile no pudo leerlo.'
    end
    if code == 2 then return nil end -- ENOENT: primera ejecucion sin datos.
    return nil, 'No se pudo comprobar la ausencia del archivo (acceso/IO).'
end

local permissions = OSSecurity.Permissions.new({
    ace = serverConfig.AdminAce,
    limits = serverConfig,
    isAceAllowed = IsPlayerAceAllowed,
    now = os.time
})

local store = OSSecurity.JsonStorage.new({
    base = serverConfig.StorageBase,
    limits = serverConfig,
    read = readResourceFile,
    write = function(path, content)
        return SaveResourceFile(resourceName, path, content, #content)
    end,
    encode = OSSecurity.JsonCodec.encode,
    decode = OSSecurity.JsonCodec.decode,
    log = storageLog
})

-- API interna del servidor; sin exports ni eventos de red administrativos.
OSSecurity.Registry = OSSecurity.DeviceRegistry.new({
    store = store, limits = serverConfig, authorize = permissions.authorize, now = os.time
})
local registry = OSSecurity.Registry

OSSecurity.DeviceCommands.register({
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
})

AddEventHandler('playerDropped', function()
    permissions.forget(tonumber(source))
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

    if config.Debug then
        print(('%s [DEBUG] Nombre del recurso: %s'):format(constants.LOG_PREFIX, resourceName))
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then
        return
    end

    print(('%s Recurso detenido. Version: %s'):format(constants.LOG_PREFIX, config.Version))
end)
