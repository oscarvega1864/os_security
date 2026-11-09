-- Metadatos vacios en esta fase: ni roles ni autorizaciones viven en el item.
local prefix = OSSecurity.Brand.Name .. ' · '
OSSecurity.ItemCatalog = {
    g6_client_tablet = { name = OSSecurity.Brand.Tablets.client.name, category = 'tablet', weight = 1, tablet = 'client' },
    g6_operations_tablet = { name = OSSecurity.Brand.Tablets.operations.name, category = 'tablet', weight = 1, tablet = 'operations' },
    os_cctv_kit = { name = prefix .. 'Kit CCTV', category = 'kit', weight = 3, usable = 'placement' },
    os_alarm_kit = { name = prefix .. 'Kit alarma', category = 'kit', weight = 3, usable = 'placement' },
    g6_alarm_tag = { name = prefix .. 'Chapa de alarma', category = 'access', weight = 0, usable = 'tag' },
    os_lock_kit = { name = prefix .. 'Kit cerradura', category = 'kit', weight = 2 },
    os_tracker_kit = { name = prefix .. 'Kit localizador', category = 'kit', weight = 1 },
    os_drill = { name = prefix .. 'Taladro', category = 'tool', weight = 2 },
    os_screwdriver = { name = prefix .. 'Destornillador', category = 'tool', weight = 1 },
    os_battery = { name = prefix .. 'Bateria', category = 'material', weight = 1 }
}
for _, definition in pairs(OSSecurity.ItemCatalog) do definition.metadataSchema = {} end
