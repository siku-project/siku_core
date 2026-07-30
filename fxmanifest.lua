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
  'config/spatial.lua',
  'shared/lib/**/*.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/init.lua',
  'config/version.lua',
  'config/migration.lua',
  'config/permissions.lua',
  'server/modules/**/*.lua',
  'server/lib/**/*.lua',
}

client_scripts {
  'config/world.lua',
  'client/lib/**/*.lua',
  'client/modules/**/*.lua',
}

files {
  'init.lua',
}

dependencies {
  'oxmysql'
}
