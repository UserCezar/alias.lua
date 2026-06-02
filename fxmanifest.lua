fx_version 'cerulean'
game 'gta5'

author 'YourServer'
description 'Alias / Identity Label System - persistent aliases saved to MySQL'
version '3.0.0'

shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_core',
}
