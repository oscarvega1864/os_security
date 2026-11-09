-- Cerraduras en el cliente: aplica en el sistema de puertas de GTA el estado que manda el servidor,
-- detecta las puertas del mapa junto a las propiedades con titular, ofrece la llave (E) y el cambio de
-- bombin. El cliente no decide nada: el servidor valida titular, distancia, objetos y estado.
OSSecurity.ClientLocks = {}

-- Una puerta de GTA o de MLO: la conoce el sistema de puertas del juego o tiene forma de hoja de puerta
-- (alta, fina y de ancho normal). Las puertas dobles son dos hojas, cada una se registra por separado.
function OSSecurity.ClientLocks.doorShape(min, max)
    local sx, sy, sz = max.x - min.x, max.y - min.y, max.z - min.z
    local thin, wide = math.min(sx, sy), math.max(sx, sy)
    return sz >= 1.8 and sz <= 3.2 and thin <= 0.35 and wide >= 0.6 and wide <= 1.8
end

function OSSecurity.ClientLocks.new(options)
    local locks = { doors = {}, targets = {} }
    local scanned = {} -- 'kind:id' -> true: ya informado en esta sesion
    local function systemHash(id) return GetHashKey('os_security_door_' .. id) end

    -- Aplica la lista del servidor: altas, bajas y estado (1 = cerrada con llave, 0 = libre).
    function locks.apply(list)
        local seen = {}
        for _, door in ipairs(type(list) == 'table' and list or {}) do
            if type(door) == 'table' and type(door.id) == 'string' and type(door.model) == 'number' and type(door.position) == 'table' then
                local hash = systemHash(door.id)
                seen[door.id] = true
                if not locks.doors[door.id] or not IsDoorRegisteredWithSystem(hash) then
                    local p = door.position
                    AddDoorToSystem(hash, door.model, p.x + 0.0, p.y + 0.0, p.z + 0.0, false, false, false)
                end
                DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, false)
                locks.doors[door.id] = { id = door.id, hash = hash, locked = door.locked == true, tier = door.tier,
                    position = vector3(door.position.x, door.position.y, door.position.z) }
            end
        end
        for id, door in pairs(locks.doors) do
            if not seen[id] then
                if IsDoorRegisteredWithSystem(door.hash) then
                    DoorSystemSetDoorState(door.hash, 0, false, false)
                    RemoveDoorFromSystem(door.hash)
                end
                locks.doors[id] = nil
            end
        end
    end
    function locks.setTargets(list) locks.targets = type(list) == 'table' and list or {} end
    function locks.nearest(point, reach)
        local best, bestDistance
        for _, door in pairs(locks.doors) do
            local d = #(point - door.position)
            if d <= reach and (not bestDistance or d < bestDistance) then best, bestDistance = door, d end
        end
        return best
    end
    -- Puertas del mapa alrededor de un punto (objetos que no son de ningun script).
    local function scan(center, radius)
        local found = {}
        for _, object in ipairs(GetGamePool('CObject')) do
            if not IsEntityAMissionEntity(object) and not IsEntityAttached(object) then
                local p = GetEntityCoords(object)
                if #(p - center) <= radius then
                    local model = GetEntityModel(object)
                    local known = DoorSystemFindExistingDoor(p.x, p.y, p.z, model)
                    local min, max = GetModelDimensions(model)
                    if known == true or known == 1 or OSSecurity.ClientLocks.doorShape(min, max) then
                        found[#found + 1] = { model = model, x = p.x, y = p.y, z = p.z }
                        if #found >= 32 then break end
                    end
                end
            end
        end
        return found
    end
    -- Al acercarse a una propiedad con titular, informa una vez por sesion de sus puertas.
    CreateThread(function()
        while true do
            Wait(3000)
            local here = GetEntityCoords(PlayerPedId())
            for _, site in ipairs(locks.targets) do
                local key = tostring(site.kind) .. ':' .. tostring(site.id)
                local p = site.position
                if not scanned[key] and type(p) == 'table' and #(here - vector3(p.x, p.y, p.z)) <= (options.scanRange or 25.0) then
                    scanned[key] = true
                    local doors = scan(vector3(p.x, p.y, p.z), options.detectRadius or 15.0)
                    if #doors > 0 then options.report({ kind = site.kind, id = site.id, doors = doors }) end
                end
            end
        end
    end)
    -- /g6puerta: entidad apuntada (para el apano manual de un administrador).
    function locks.aimed(reach)
        local camera, rotation = GetGameplayCamCoord(), GetGameplayCamRot(2)
        local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
        local horizontal = math.abs(math.cos(pitch))
        local handle = StartExpensiveSynchronousShapeTestLosProbe(camera.x, camera.y, camera.z,
            camera.x - math.sin(yaw) * horizontal * reach, camera.y + math.cos(yaw) * horizontal * reach,
            camera.z + math.sin(pitch) * reach, 16, PlayerPedId(), 0)
        local _, hit, _, _, entity = GetShapeTestResult(handle)
        if (hit == 1 or hit == true) and entity and entity ~= 0 and GetEntityType(entity) == 3 then return entity end
        return nil
    end
    function locks.clear()
        for _, door in pairs(locks.doors) do
            if IsDoorRegisteredWithSystem(door.hash) then
                DoorSystemSetDoorState(door.hash, 0, false, false)
                RemoveDoorFromSystem(door.hash)
            end
        end
        locks.doors = {}
    end
    return locks
end
