-- Tienda Gruppe Sechs (compartido: el cliente dibuja el mostrador, el servidor valida todo).
-- Productos 'public' para cualquiera; 'staff' solo para personal G6 de servicio (o ACE tecnico,
-- supervisor o admin). Los precios se cobran al personaje activo (banco o efectivo) con el proveedor
-- de dinero (ossecurity_money_resource, por defecto os_devtools). La ganzua no se vende aqui.
OSSecurity.ShopConfig = {
    Distance = 2.5,          -- metros al mostrador para abrir y para pagar
    MaxQuantity = 10,        -- unidades por producto y compra
    MaxLines = 16,           -- productos distintos por compra
    Accounts = { 'bank', 'cash' },
    Locations = {
        { id = 'union', label = 'Gruppe Sechs · Union Depository', x = 10.17, y = -671.55, z = 33.45, blip = true }
    },
    Products = {
        { item = 'g6_client_tablet', price = 1500, audience = 'public' },
        { item = 'os_lock_kit', price = 850, audience = 'public' },
        { item = 'os_lock_kit_high', price = 2400, audience = 'public' },
        { item = 'os_car_lock_kit', price = 1250, audience = 'public' },
        { item = 'os_car_alarm_kit', price = 1900, audience = 'public' },
        { item = 'os_screwdriver', price = 60, audience = 'public' },
        { item = 'os_battery', price = 45, audience = 'public' },
        { item = 'os_cctv_kit', price = 950, audience = 'staff' },
        { item = 'os_cctv_kit_mini', price = 700, audience = 'staff' },
        { item = 'os_cctv_kit_dome', price = 1350, audience = 'staff' },
        { item = 'os_alarm_kit', price = 1650, audience = 'staff' },
        { item = 'os_alarm_kit_panel', price = 1950, audience = 'staff' },
        { item = 'os_drill', price = 380, audience = 'staff' },
        { item = 'g6_operations_tablet', price = 2500, audience = 'staff' }
    }
}
