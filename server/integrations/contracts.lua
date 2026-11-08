-- Contratos de extension, sin adaptadores ficticios ni datos de ejemplo.
OSSecurity.IntegrationContracts = {
    version = 1,
    inventory = { methods = { 'load', 'get', 'has', 'grant', 'reserve', 'finish', 'cancel', 'status' },
        consistency = 'persistent_reservations_and_idempotent_compensation',
        adapters = { standalone = 'implemented', os_inventory = 'implemented', esx = 'unavailable', qbcore = 'unavailable', qbox = 'unavailable', ox_inventory = 'unavailable' } },
    properties = { status = 'unavailable', requires = { 'stableId', 'serverOwnership', 'accessScope' } },
    vehicles = { status = 'unavailable', requires = { 'stableId', 'serverOwnership', 'routingBucket' } },
    contracts = { status = 'unavailable', requires = { 'contractId', 'principal', 'scopes', 'validUntil' } },
    personnel = { status = 'ace_only', requires = { 'principal', 'serverProfile', 'deviceGrants' } },
    installations = { status = 'cctv_only', requires = { 'installationId', 'deviceId', 'installer', 'owner', 'anchorId' } },
    maintenance = { status = 'implemented', requires = { 'deviceId', 'componentSlot', 'serverAuthorization' } },
    cctv = { registry = true, authorization = true, sessions = true, imageRenderer = false, signalTransport = false, remoteVideo = false },
    bodycams = { registry = true, authorization = false, sessions = false, imageRenderer = false, signalTransport = false },
    alarms = { status = 'unavailable' }, locks = { status = 'unavailable' },
    oneSync = { requiresValidationInGame = true, serverWorldRaycast = false, placementPolicy = 'admin_surveyed_mounts' }
}
