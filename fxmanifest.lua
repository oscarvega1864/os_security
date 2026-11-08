fx_version 'cerulean'
game 'gta5'

author 'OS Security'
description 'Gruppe Sechs - dual tablets, standalone inventory and CCTV placement'

-- La version se define en config/config.lua para mantener una unica fuente.
shared_scripts {
    'config/brand.lua',
    'shared/constants.lua',
    'config/config.lua',
    'shared/items.lua'
}

client_scripts {
    'client/main.lua',
    'client/tablet.lua',
    'client/view.lua',
    'client/placement.lua',
    'client/props.lua',
    'client/notify.lua',
    'client/boot.lua'
}

ui_page 'web/index.html'
nui_callback_strict_mode 'true'
files { 'web/index.html', 'web/style.css', 'web/app.js' }
server_scripts {
    'config/server.lua',
    'config/components.lua',
    'config/gameplay.lua',
    'server/core/util.lua',
    'server/devices/catalog.lua',
    'server/devices/states.lua',
    'server/components/wear.lua',
    'server/components/catalog.lua',
    'server/components/migration.lua',
    'server/components/lifecycle.lua',
    'server/components/validation.lua',
    'server/devices/validation.lua',
    'server/storage/codec.lua',
    'server/storage/resource_files.lua',
    'server/storage/json.lua',
    'server/security/permissions.lua',
    'server/security/admin_access.lua',
    'server/security/employment.lua',
    'server/devices/registry.lua',
    'server/commands/devices.lua',
    'server/commands/maintenance.lua',
    'server/security/identity.lua',
    'server/integrations/contracts.lua',
    'server/integrations/sites.lua',
    'server/inventory/state.lua',
    'server/inventory/standalone.lua',
    'server/inventory/external.lua',
    'server/tablet/authorization.lua',
    'server/tablet/sessions.lua',
    'server/installation/service.lua',
    'server/tablet/service.lua',
    'server/tablet/controller.lua',
    'server/commands/gameplay.lua',
    'server/gameplay.lua',
    'server/main.lua'
}
