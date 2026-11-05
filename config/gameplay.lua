-- Solo servidor. Los puntos de montaje se dan de alta expresamente mediante ACE.
OSSecurity.GameplayConfig = {
    StorageBase = 'data/inventory', MaxAccounts = 256, MaxItemQuantity = 100, MaxTotalItems = 500,
    MaxInstallations = 1000, MaxAnchors = 128, MaxGrantsPerAccount = 1000, MaxFileBytes = 8 * 1024 * 1024,
    SessionSeconds = 90, PlacementSeconds = 90, PageSize = 12, RequestWindow = 10, RequestsPerWindow = 25,
    OpenRequestsPerWindow = 3, PlacementDistance = 4.0, MaxPlacementMove = 6.0,
    StreamDistance = 80.0, MaxStreamedProps = 40, CameraModel = 'prop_cctv_cam_01a', Models = { prop_cctv_cam_01a = true },
    Materials = { os_cctv_kit = 1, os_battery = 1 }, Tools = { 'os_drill', 'os_screwdriver' },
    Ace = {
        client = 'ossecurity.g6.client', operations = 'ossecurity.g6.operations',
        technician = 'ossecurity.g6.technician', supervisor = 'ossecurity.g6.supervisor', admin = 'ossecurity.admin'
    },
    Profiles = {
        client = { view = true },
        technician = { view = true, inspect = true, repair = true, replace = true, provision = true, install = true },
        supervisor = { view = true, inspect = true, beginMaintenance = true },
        admin = { view = true, inspect = true, repair = true, replace = true, provision = true, beginMaintenance = true, install = true }
    }
}
