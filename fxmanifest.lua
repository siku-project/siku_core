fx_version 'cerulean'
game 'gta5'

author 'SIKU'
description 'The core of the SIKU ecosystem.'
version '0.0.1'

name 'siku_core'

lua54 'yes'

shared_scripts {
  'shared/init.lua',
  'config/callback.lua',
  'shared/lib/**/*.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'config/version.lua',
  'config/migration.lua',
  'server/modules/**/*.lua',
  'server/lib/**/*.lua',
  'server/init.lua',
}

client_scripts {
  'client/lib/**/*.lua',
}

files {
  'init.lua',
}

dependencies {
  'oxmysql'
}
