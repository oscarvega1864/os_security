-- Catalogo de contratos, sin implementar los futuros modulos.
-- metadataSchema admite descriptores string/number/boolean con limites.
local definitions = {}
for _, id in ipairs({
    'cctv_camera', 'alarm_panel', 'alarm_sensor', 'smart_lock',
    'vehicle_tracker', 'bodycam', 'security_monitor'
}) do
    definitions[id] = { id = id, defaultModel = 'generic', metadataSchema = {} }
end

-- Correlacion de una instalacion confirmada por el servidor, sin cambiar IDs.
definitions.cctv_camera.metadataSchema.installationId = { type = 'string', maxLength = 64 }

OSSecurity.DeviceCatalog = {}

function OSSecurity.DeviceCatalog.get(id)
    if type(id) ~= 'string' then return nil end
    return OSSecurity.Util.copy(definitions[id])
end

function OSSecurity.DeviceCatalog.list()
    local ids = {}
    for id in pairs(definitions) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
