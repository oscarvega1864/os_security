OSSecurity.ClientView = {}

function OSSecurity.ClientView.new()
    local view, active, handProp, generation = {}, false, nil, 0
    local dictionary, animation = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base'
    function view.hide()
        active = false
        generation = generation + 1
        SetNuiFocus(false, false)
        SendNUIMessage({ type = 'close' })
        StopAnimTask(PlayerPedId(), dictionary, animation, 2.0)
        if handProp and DoesEntityExist(handProp) then DeleteEntity(handProp) end
        handProp = nil
    end
    function view.show(session)
        view.hide(); active = true
        local current = generation
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'open', session = session })
        if session.kind == 'inventory' then return end
        CreateThread(function()
            RequestAnimDict(dictionary)
            local deadline = GetGameTimer() + 2000
            while active and generation == current and not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(10) end
            if not active or generation ~= current or not HasAnimDictLoaded(dictionary) then return end
            TaskPlayAnim(PlayerPedId(), dictionary, animation, 3.0, -3.0, -1, 49, 0, false, false, false)
            local model = GetHashKey('prop_cs_tablet')
            RequestModel(model); deadline = GetGameTimer() + 2000
            while active and generation == current and not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(10) end
            if active and generation == current and HasModelLoaded(model) then
                local ped = PlayerPedId(); local point = GetEntityCoords(ped)
                handProp = CreateObjectNoOffset(model, point.x, point.y, point.z, false, false, false)
                if handProp and handProp ~= 0 then
                    SetEntityCollision(handProp, false, false)
                    AttachEntityToEntity(handProp, ped, GetPedBoneIndex(ped, 28422), 0.0, -0.02, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
                end
            end
            SetModelAsNoLongerNeeded(model)
        end)
    end
    return view
end
