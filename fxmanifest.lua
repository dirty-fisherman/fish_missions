name 'fivem-typescript-boilerplate'
author 'Overextended'
version '0.0.0'
repository 'https://github.com/communityox/fivem-typescript-boilerplate.git'
fx_version 'cerulean'
game 'gta5'
ui_page 'dist/web/index.html'
node_version '22'

files {
	'locales/*.json',
	'dist/web/assets/index.css',
	'dist/web/assets/index.js',
	'dist/web/index.html',
	'static/config.json',
	'locales/en.json',
}

dependencies {
	'ox_lib',
	'ox_target',
	'/server:13068',
	'/onesync',
}

client_scripts {
	'dist/client.js',
}

server_scripts {
	'dist/server.js',
}
