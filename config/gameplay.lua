-- Solo servidor. Los puntos de montaje se dan de alta expresamente mediante ACE.
OSSecurity.GameplayConfig = {
    StorageBase = 'data/inventory', MaxAccounts = 256, MaxItemQuantity = 100, MaxTotalItems = 500,
    MaxInstallations = 1000, MaxAnchors = 128, MaxGrantsPerAccount = 1000, MaxFileBytes = 8 * 1024 * 1024,
    SessionSeconds = 90, PlacementSeconds = 180, PageSize = 12, RequestWindow = 10, RequestsPerWindow = 25,
    OpenRequestsPerWindow = 3, PlacementDistance = 4.0, AnchorAimDistance = 10.0, MaxPlacementMove = 6.0, MinDepth = -0.15, MaxDepth = 0.3,
    StreamDistance = 80.0, MaxStreamedProps = 40, CameraModel = 'prop_cctv_cam_01a',
    Models = { prop_cctv_cam_01a = true, prop_ld_keypad_01 = true },
    Materials = { os_cctv_kit = 1, os_battery = 1 }, Tools = { 'os_drill', 'os_screwdriver' },
    -- Productos instalables: el kit que se "usa" decide el dispositivo, el modelo y los materiales.
    -- El modelo del teclado se comprueba en el juego; si no existe, cambiarlo aqui por otro prop.
    Products = {
        os_cctv_kit = { deviceType = 'cctv_camera', model = 'prop_cctv_cam_01a', materials = { os_cctv_kit = 1, os_battery = 1 } },
        os_alarm_kit = { deviceType = 'alarm_panel', model = 'prop_ld_keypad_01', materials = { os_alarm_kit = 1, os_battery = 1 } }
    },
    -- Alarmas (central con teclado). Zona: esfera alrededor del teclado.
    Alarm = {
        Radius = 10.0, InteractDistance = 2.0, ExitDelay = 30, EntryDelay = 30, SirenSeconds = 90,
        PinMin = 4, PinMax = 6, MaxPinAttempts = 3, LockoutSeconds = 60, MaxTags = 10, MaxEvents = 20,
        NotifyRadius = 150.0,
        Siren = { name = 'Burglar_Bell', set = 'Generic_Alarms' } -- sonido de GTA; sin comprobar, configurable
    },
    Ace = {
        client = 'ossecurity.g6.client', operations = 'ossecurity.g6.operations',
        technician = 'ossecurity.g6.technician', supervisor = 'ossecurity.g6.supervisor', admin = 'ossecurity.admin'
    },
    -- Perfil profesional por empleo del personaje activo (adaptador opcional), ademas de los ACE.
    -- Solo de servicio. 'admin' y la tablet Client nunca se obtienen por empleo.
    Employment = {
        Job = 'gruppe6', RequireDuty = true,
        Ranks = { tecnico = 'technician', supervisor = 'supervisor' }
    },
    Profiles = {
        client = { view = true },
        technician = { view = true, inspect = true, repair = true, replace = true, provision = true, install = true },
        supervisor = { view = true, inspect = true, beginMaintenance = true },
        admin = { view = true, inspect = true, repair = true, replace = true, provision = true, beginMaintenance = true, install = true }
    }
}
