fx_version 'cerulean'
game 'gta5'

author 'SIKU'
description 'The core of the SIKU ecosystem.'
version '0.2.0'

name 'siku_core'

lua54 'yes'

shared_scripts {
  'shared/init.lua',
  'config/callback.lua',
  'config/spatial.lua',
  'config/translation.lua',
  'shared/utils/locale.lua',
  'shared/lib/**/*.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/init.lua',
  'config/version.lua',
  'config/migration.lua',
  'config/permissions.lua',
  'config/connection.lua',
  'server/modules/**/*.lua',
  'server/lib/**/*.lua',
  'server/classes/**/*.lua',
}

client_scripts {
  'config/world.lua',
  'config/camera.lua',
  'client/lib/**/*.lua',
  'client/modules/**/*.lua',
}

files {
  'init.lua',
  'translations/*.lua',
}

dependencies {
  'oxmysql'
}
