-- Estado operativo/instalacion. La salud se guarda aparte en condition.
local transitions = {
    registered = { installing = true, retired = true },
    installing = { installed = true, registered = true, retired = true },
    installed = { active = true, maintenance = true, fault = true, retired = true },
    active = { maintenance = true, fault = true, retired = true },
    maintenance = { installed = true, active = true, fault = true, retired = true },
    fault = { maintenance = true, retired = true },
    retired = {}
}

OSSecurity.DeviceStates = {}

function OSSecurity.DeviceStates.exists(state)
    return type(state) == 'string' and transitions[state] ~= nil
end

function OSSecurity.DeviceStates.canTransition(origin, target)
    return OSSecurity.DeviceStates.exists(origin) and type(target) == 'string'
        and transitions[origin][target] == true
end
