-- fxmanifest.lua
fx_version 'cerulean'
game 'gta5'

name 'lv_laitonyritys'
author 'You'
description 'Illegal businesses system (meth, coke, weed, counterfeit, forgery)'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/core.lua',
    'server/production.lua',
    'server/raids.lua',
    'server/missions.lua',
    'server/ui_callbacks.lua',
    'server/routing.lua'
}

client_scripts {
    'client/main.lua',
    'client/npc.lua',
    'client/production_props.lua',
    'client/employees.lua',
    'client/ui_missions.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/images/*.png'
}