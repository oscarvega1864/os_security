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
        remove = function(holder, item, amount, operationId) return exports[inventoryResource]:RemoveItem(holder, item, amount, nil, operationId) end
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

-- Propiedades y negocios: el titular del personaje activo ve en la tablet Client los dispositivos vinculados.
--   set ossecurity_sites_resource none   lo desactiva.
local sitesResource = GetConvar('ossecurity_sites_resource', identityResource)
local sites = sitesResource ~= 'none' and OSSecurity.Sites.new({
    asset = function(category, id)
        if GetResourceState(sitesResource) ~= 'started' then return nil end
        return exports[sitesResource]:GetAsset(category, id)
    end,
    active = function(source)
        if GetResourceState(identityResource) ~= 'started' then return nil end
        return exports[identityResource]:GetActiveCharacter(source)
    end
}) or nil

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
    sites = sites,
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

AddEventHandler('playerDropped', function()
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
        if definition.tablet or definition.usable == 'placement' then
            local ok, registered = pcall(function()
                return exports[inventoryResource]:RegisterUsableItem(item, function(player)
                    TriggerClientEvent('osinventory:forceClose', player)
                    if definition.tablet then TriggerClientEvent('os_security:g6:openTablet', player, definition.tablet)
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
