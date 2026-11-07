-- Solo servidor. Los limites incluyen los dispositivos retirados.
OSSecurity.ServerConfig = {
    AdminAce = 'ossecurity.admin',
    AdminAuthorizationResource = 'os_devtools', -- Opcional; false mantiene solo ACE.
    StorageBase = 'data/devices',
    MaxDevices = 1000,
    DefaultPageSize = 20,
    MaxPageSize = 100,
    MaxHistory = 256,
    MaxMaintenanceEvents = 128,
    MaxFileBytes = 8 * 1024 * 1024,
    RateWindowSeconds = 10,
    ReadRequestsPerWindow = 30,
    WriteRequestsPerWindow = 5
}
