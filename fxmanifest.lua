fx_version 'adamant'

game 'gta5'

shared_script '@ox_lib/init.lua'

client_scripts {
		'NativeUI.lua',
		'Config.lua',
		'Client/*.lua'
}

server_scripts {
		'Config.lua',
		'@mysql-async/lib/MySQL.lua',
		'Server/*.lua'
}

dependency 'ox_lib'
dependency 'ox_target'
