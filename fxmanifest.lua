name 'fish_missions'
author 'fish'
version '1.0.0'
fx_version 'cerulean'
game 'gta5'
ui_page 'dist/web/index.html'

files {
	'locales/*.json',
	'dist/web/assets/index.css',
	'dist/web/assets/index.js',
	'dist/web/index.html',
	'locales/en.json',
}

dependencies {
	'ox_core',
	'ox_lib',
	'ox_target',
	'oxmysql',
	'/server:13068',
	'/onesync',
}

shared_scripts {
	'@ox_lib/init.lua',
	'shared/config.lua',
}

client_scripts {
	'client/main.lua',
	'client/missions/*.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/main.lua',
}
