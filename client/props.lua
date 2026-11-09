OSSecurity.ClientProps = {}

function OSSecurity.ClientProps.new()
    local objects, generation = {}, 0
    local props = {}
    function props.clear()
        generation = generation + 1
        for _, object in pairs(objects) do if DoesEntityExist(object) then DeleteEntity(object) end end
        objects = {}
    end
    function props.sync(list)
        generation = generation + 1
        local current, keep = generation, {}
        for _, entry in ipairs(list) do keep[entry.id] = true end
        for id, object in pairs(objects) do
            if not keep[id] then if DoesEntityExist(object) then DeleteEntity(object) end; objects[id] = nil end
        end
        CreateThread(function()
            for _, entry in ipairs(list) do
                if generation ~= current then return end
                if not objects[entry.id] then
                    local model = GetHashKey(entry.model)
                    if IsModelInCdimage(model) and IsModelValid(model) then
                        RequestModel(model)
                        local deadline = GetGameTimer() + 2000
                        while generation == current and not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(10) end
                        if generation ~= current then SetModelAsNoLongerNeeded(model); return end
                        if HasModelLoaded(model) then
                            local p, r = entry.position, entry.rotation
                            local object = CreateObjectNoOffset(model, p.x, p.y, p.z, false, false, false)
                            if object and object ~= 0 then
                                -- Misma colocacion que la vista previa: origen del modelo en la posicion guardada.
                                SetEntityRotation(object, r.x, r.y, r.z, 2, true); FreezeEntityPosition(object, true)
                                SetEntityAsMissionEntity(object, true, true); objects[entry.id] = object
                            end
                        end
                        SetModelAsNoLongerNeeded(model)
                    end
                end
            end
        end)
    end
    return props
end
