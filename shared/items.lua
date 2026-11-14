-- Metadatos vacios en esta fase: ni roles ni autorizaciones viven en el item.
local prefix = OSSecurity.Brand.Name .. ' · '
OSSecurity.ItemCatalog = {
    g6_client_tablet = { name = OSSecurity.Brand.Tablets.client.name, category = 'tablet', weight = 1, tablet = 'client' },
    g6_operations_tablet = { name = OSSecurity.Brand.Tablets.operations.name, category = 'tablet', weight = 1, tablet = 'operations' },
    os_cctv_kit = { name = prefix .. 'Kit CCTV (exterior)', category = 'kit', weight = 3, usable = 'placement' },
    os_cctv_kit_mini = { name = prefix .. 'Kit CCTV (mini interior)', category = 'kit', weight = 1, usable = 'placement' },
    os_cctv_kit_dome = { name = prefix .. 'Kit CCTV (domo 360)', category = 'kit', weight = 2, usable = 'placement' },
    os_alarm_kit = { name = prefix .. 'Kit alarma (teclado)', category = 'kit', weight = 3, usable = 'placement' },
    os_alarm_kit_panel = { name = prefix .. 'Kit alarma (panel lector)', category = 'kit', weight = 3, usable = 'placement' },
    g6_alarm_tag = { name = prefix .. 'Chapa de alarma', category = 'access', weight = 0, usable = 'tag' },
    os_lock_kit = { name = prefix .. 'Bombin de seguridad', category = 'kit', weight = 1, usable = 'cylinder' },
    os_lock_kit_high = { name = prefix .. 'Bombin de alta seguridad', category = 'kit', weight = 1, usable = 'cylinder' },
    os_car_lock_kit = { name = prefix .. 'Cierre centralizado (vehiculo)', category = 'kit', weight = 2, usable = 'car' },
    os_car_alarm_kit = { name = prefix .. 'Alarma de vehiculo', category = 'kit', weight = 2, usable = 'car' },
    os_tracker_kit = { name = prefix .. 'Kit localizador', category = 'kit', weight = 1 },
    os_lockpick = { name = prefix .. 'Ganzua', category = 'tool', weight = 0, usable = 'lockpick' },
    os_drill = { name = prefix .. 'Taladro', category = 'tool', weight = 2 },
    os_screwdriver = { name = prefix .. 'Destornillador', category = 'tool', weight = 1 },
    os_battery = { name = prefix .. 'Bateria', category = 'material', weight = 1 },
    os_metal_detector = { name = 'Arco detector de metales', category = 'kit', weight = 8, usable = 'detector' }
}
for _, definition in pairs(OSSecurity.ItemCatalog) do definition.metadataSchema = {} end
