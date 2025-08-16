fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'tls_sickness'
author 'Anyname'
description 'DayZ-style wet sickness + cannibal madness for QBCore with HUD exports, gradual cures, progress bars, cooldowns, DB/file persistence, proximity laughter, debug, logging, and admin commands'
version '0.4'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/nui.js',
    'html/*.ogg',
    'README.md'
}

shared_scripts {
    'config.lua',
    '@qb-core/shared/locale.lua',
    '@ox_lib/init.lua',
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}
