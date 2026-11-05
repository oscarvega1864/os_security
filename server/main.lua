local config = OSSecurity.Config
local constants = OSSecurity.Constants
local resourceName = GetCurrentResourceName()

RegisterCommand('osstatus', function(source)
    local message = ('Estado: %s | Version: %s'):format(
        GetResourceState(resourceName),
        config.Version
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
