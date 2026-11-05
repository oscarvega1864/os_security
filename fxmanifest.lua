fx_version 'cerulean'
game 'gta5'

author 'OS Security'
description 'Recurso standalone de seguridad privada - fase 0.1'

-- La version se define en config/config.lua para mantener una unica fuente.
shared_scripts {
    'shared/constants.lua',
    'config/config.lua'
}

client_script 'client/main.lua'
server_script 'server/main.lua'
