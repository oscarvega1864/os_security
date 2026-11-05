fx_version 'cerulean'
game 'gta5'

author 'OS Security'
description 'OS Security - persistent device core'

-- La version se define en config/config.lua para mantener una unica fuente.
shared_scripts {
    'shared/constants.lua',
    'config/config.lua'
}

client_script 'client/main.lua'
server_scripts {
    'config/server.lua',
    'server/core/util.lua',
    'server/devices/catalog.lua',
    'server/devices/states.lua',
    'server/devices/validation.lua',
    'server/storage/codec.lua',
    'server/storage/resource_files.lua',
    'server/storage/json.lua',
    'server/security/permissions.lua',
    'server/devices/registry.lua',
    'server/commands/devices.lua',
    'server/main.lua'
}
