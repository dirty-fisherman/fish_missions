name 'fish_missions'
author 'fish'
version '2.0.0'
fx_version 'cerulean'
game 'gta5'
ui_page 'dist/web/index.html'

files {
	'dist/web/assets/index.css',
	'dist/web/assets/index.js',
	'dist/web/index.html',
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
	'shared/helpers.lua',
}

client_scripts {
	'client/helpers.lua',
	'client/lifecycle.lua',
	'client/npc.lua',
	'client/nui.lua',
	'client/admin/*.lua',
	'client/missions/*.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/helpers.lua',
	'server/db.lua',
	'server/rewards.lua',
	'server/tracker.lua',
	'server/missions.lua',
	'server/lifecycle.lua',
	'server/assassination.lua',
	'server/admin.lua',
	'server/init.lua',
}
