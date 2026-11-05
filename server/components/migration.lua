local util = OSSecurity.Util
OSSecurity.ComponentMigration = {}

-- Migracion explicita por dispositivo. El contenedor de snapshots sigue en v1;
-- pueden convivir dispositivos v1/v2. No escribir durante load() ni perder datos.
function OSSecurity.ComponentMigration.promote(device)
    if device.schemaVersion ~= 1 then return nil, 'El dispositivo ya tiene el esquema de componentes.' end
    local migrated = util.copy(device)
    migrated.schemaVersion = 2
    migrated.condition = { components = {} }
    migrated.maintenance = {
        sequence = 0, events = {},
        legacy = { components = util.copy(device.condition.components), events = util.copy(device.maintenance.events) }
    }
    return migrated
end
