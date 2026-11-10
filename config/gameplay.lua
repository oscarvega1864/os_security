-- Solo servidor. Los puntos de montaje se dan de alta expresamente mediante ACE.
OSSecurity.GameplayConfig = {
    StorageBase = 'data/inventory', MaxAccounts = 256, MaxItemQuantity = 100, MaxTotalItems = 500,
    MaxInstallations = 1000, MaxAnchors = 128, MaxGrantsPerAccount = 1000, MaxFileBytes = 8 * 1024 * 1024,
    SessionSeconds = 90, PlacementSeconds = 180, PageSize = 12, RequestWindow = 10, RequestsPerWindow = 25,
    OpenRequestsPerWindow = 3, PlacementDistance = 4.0, AnchorAimDistance = 10.0, MaxPlacementMove = 6.0, MinDepth = -0.15, MaxDepth = 0.3, MaxPivotOffset = 0.75,
    StreamDistance = 80.0, MaxStreamedProps = 40, CameraModel = 'prop_cctv_cam_01a',
    Models = { prop_cctv_cam_01a = true, hei_prop_bank_cctv_01 = true, prop_cctv_cam_05a = true,
        prop_ld_keypad_01 = true, hei_prop_hei_securitypanel = true },
    Materials = { os_cctv_kit = 1, os_battery = 1 }, Tools = { 'os_drill', 'os_screwdriver' },
    -- Productos instalables: el kit que se "usa" decide el dispositivo, el modelo y los materiales.
    -- El modelo del teclado se comprueba en el juego; si no existe, cambiarlo aqui por otro prop.
    Products = {
        -- Camaras: exterior (brazo de pared), mini de interior y domo 360 (techo). Si un modelo no existe
        -- en el juego, la previsualizacion no aparece: cambiarlo aqui (y en Models) por otro prop.
        os_cctv_kit = { deviceType = 'cctv_camera', model = 'prop_cctv_cam_01a', materials = { os_cctv_kit = 1, os_battery = 1 } },
        os_cctv_kit_mini = { deviceType = 'cctv_camera', model = 'hei_prop_bank_cctv_01', materials = { os_cctv_kit_mini = 1, os_battery = 1 } },
        os_cctv_kit_dome = { deviceType = 'cctv_camera', model = 'prop_cctv_cam_05a', materials = { os_cctv_kit_dome = 1, os_battery = 1 } },
        -- Dos modelos de central de alarma, misma funcion (teclado PIN y lector de chapa): se compra el kit que se quiera.
        os_alarm_kit = { deviceType = 'alarm_panel', model = 'prop_ld_keypad_01', materials = { os_alarm_kit = 1, os_battery = 1 } },
        os_alarm_kit_panel = { deviceType = 'alarm_panel', model = 'hei_prop_hei_securitypanel', materials = { os_alarm_kit_panel = 1, os_battery = 1 } }
    },
    -- Alarmas (central con teclado). Zona: esfera alrededor del teclado.
    Alarm = {
        Radius = 10.0, InteractDistance = 2.0, ExitDelay = 30, EntryDelay = 30, SirenSeconds = 90,
        PinMin = 4, PinMax = 6, MaxPinAttempts = 3, LockoutSeconds = 60, MaxTags = 10, MaxEvents = 20,
        NotifyRadius = 150.0 -- la sirena la genera la NUI de cada cliente; se oye hasta 150 m
    },
    -- Cerraduras de puertas: las puertas reales (mapa o MLO) de cada propiedad o negocio con titular se
    -- detectan solas y quedan con el bombin de serie (las de propiedades, cerradas). El titular abre y cierra con su llave (E) y puede
    -- cambiar el bombin por uno mas seguro con el kit; el nivel queda para robos y ganzuas futuros.
    Locks = {
        InteractDistance = 2.0, ChangeSeconds = 180, MaxDoors = 256, MaxDoorsPerSite = 8, DuplicateDistance = 0.5,
        -- Deteccion automatica: puertas del mapa a DetectRadius del punto de la propiedad, informadas por
        -- un jugador a menos de ReportRange. Las hojas a PairDistance se abren juntas (puertas dobles).
        DetectRadius = 15.0, ReportRange = 60.0, ScanCooldown = 60, PairDistance = 2.6,
        LockedByDefault = { property = true, business = false },
        Tools = { 'os_screwdriver' },
        Tiers = { 'Bombin de serie', 'Bombin de seguridad', 'Bombin de alta seguridad' },
        -- Kit -> nivel. El bombin retirado vuelve al inventario (el de serie se desecha).
        Cylinders = { os_lock_kit = 2, os_lock_kit_high = 3 }
    },
    -- Vehiculos de os_devtools (matricula OS + ID): cierre centralizado (tecla del mando) y alarma, que se
    -- instalan sentado al volante con el motor parado. La alarma necesita el cierre; salta si alguien intenta
    -- entrar con el vehiculo cerrado y avisa al dueno.
    Cars = {
        Kits = { os_car_lock_kit = 'lock', os_car_alarm_kit = 'alarm' }, Tools = { 'os_screwdriver' },
        InstallSeconds = 180, KeyDistance = 15.0, ManualDistance = 3.5, TamperDistance = 8.0, AlarmSeconds = 30, AlarmCooldown = 45,
        AlarmHearing = 150.0, SyncSeconds = 3,
        -- Puente: con destornillador, al volante de un vehiculo ajeno con el motor apagado. Nivel 1 sin kit,
        -- 2 con cierre centralizado, 3 con alarma (que salta al empezar). Decoys: cables de relleno; Band:
        -- ancho de la franja verde del arranque.
        Hotwire = { Tool = 'os_screwdriver', Seconds = 120, MinSeconds = 4,
            Levels = { { decoys = 2, band = 0.26 }, { decoys = 3, band = 0.19 }, { decoys = 3, band = 0.13 } } }
    },
    -- Ganzua: forzar puertas cerradas (segun el bombin) y vehiculos cerrados (manual 1, cierre centralizado 2).
    -- Levels por nivel de seguridad: pines, tamano de la zona verde (0-1) y velocidad del pin.
    Lockpick = {
        Item = 'os_lockpick', Reach = 2.2, VehicleReach = 3.0, Seconds = 60, MinPinSeconds = 0.5, BreakChance = 40,
        Levels = { { pins = 3, zone = 0.22, speed = 0.9 }, { pins = 5, zone = 0.15, speed = 1.15 }, { pins = 7, zone = 0.10, speed = 1.4 } }
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
