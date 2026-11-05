OSSecurity.ClientPlacement = {}

function OSSecurity.ClientPlacement.new()
    local manager, generation, prop = {}, 0, nil
    function manager.cancel()
        generation = generation + 1
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
        prop = nil
    end
    function manager.begin(context, callback)
        manager.cancel()
        local current = generation
        CreateThread(function()
            local model = GetHashKey(context.model)
            if not IsModelInCdimage(model) or not IsModelValid(model) then callback(nil); return end
            RequestModel(model)
            local timeout = GetGameTimer() + 3000
            while generation == current and not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
            if generation ~= current then SetModelAsNoLongerNeeded(model); return end
            if not HasModelLoaded(model) then SetModelAsNoLongerNeeded(model); callback(nil); return end
            local ped, origin = PlayerPedId(), GetEntityCoords(PlayerPedId())
            prop = CreateObjectNoOffset(model, origin.x, origin.y, origin.z, false, false, false)
            if not prop or prop == 0 then SetModelAsNoLongerNeeded(model); callback(nil); return end
            SetEntityCollision(prop, false, false); FreezeEntityPosition(prop, true); SetEntityAlpha(prop, 130, false)
            local deadline, heading, handle = GetGameTimer() + context.seconds * 1000, GetEntityHeading(ped), nil
            local target, mount
            while generation == current do
                Wait(0) -- Solo durante esta colocacion activa.
                ped = PlayerPedId()
                local position = GetEntityCoords(ped)
                local moved = math.sqrt((position.x-origin.x)^2 + (position.y-origin.y)^2 + (position.z-origin.z)^2)
                if IsEntityDead(ped) or moved > 6 or GetGameTimer() > deadline or IsPedInAnyVehicle(ped, false)
                    or IsControlJustPressed(0, 177) or IsControlJustPressed(0, 200) then
                    manager.cancel(); callback(nil); break
                end
                DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
                DisableControlAction(0, 14, true); DisableControlAction(0, 15, true)
                if IsDisabledControlJustPressed(0, 14) then heading = (heading + 5) % 360 end
                if IsDisabledControlJustPressed(0, 15) then heading = (heading - 5) % 360 end
                local camera, rotation = GetGameplayCamCoord(), GetGameplayCamRot(2)
                if not handle then
                    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
                    local horizontal = math.abs(math.cos(pitch))
                    handle = StartShapeTestLosProbe(camera.x, camera.y, camera.z,
                        camera.x - math.sin(yaw) * horizontal * context.maxDistance,
                        camera.y + math.cos(yaw) * horizontal * context.maxDistance,
                        camera.z + math.sin(pitch) * context.maxDistance, 1, ped, 7)
                end
                local status, hit, hitPoint, normal = GetShapeTestResult(handle)
                if status == 2 then
                    target, mount, handle = nil, nil, nil
                    if hit == 1 or hit == true then
                        for _, candidate in ipairs(context.mounts) do
                            local d = math.sqrt((hitPoint.x-candidate.position.x)^2 + (hitPoint.y-candidate.position.y)^2 + (hitPoint.z-candidate.position.z)^2)
                            local dot = normal.x*candidate.normal.x + normal.y*candidate.normal.y + normal.z*candidate.normal.z
                            if d <= candidate.radius and dot > 0.8 then target, mount = hitPoint, candidate; break end
                        end
                    end
                elseif status == 0 then handle = nil end
                SetEntityVisible(prop, target ~= nil, false)
                if target then
                    SetEntityCoordsNoOffset(prop, target.x + mount.normal.x*0.02, target.y + mount.normal.y*0.02, target.z + mount.normal.z*0.02, false, false, false)
                    SetEntityRotation(prop, 0, 0, heading, 2, true)
                    if IsControlJustPressed(0, 38) then
                        local proposal = { anchorId = mount.id, position = { x = target.x, y = target.y, z = target.z }, rotation = { x = 0, y = 0, z = heading } }
                        manager.cancel(); callback(proposal); break
                    end
                end
                BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(OSSecurity.Brand.Text.placementHelp); EndTextCommandDisplayHelp(0, false, false, -1)
            end
            SetModelAsNoLongerNeeded(model)
        end)
    end
    return manager
end
