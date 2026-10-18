fx_version 'cerulean'
game 'gta5'

author 'SIKU'
description 'The core of the SIKU ecosystem.'
version '1.6.0'

name 'siku_core'

lua54 'yes'

shared_scripts {
  'init.lua',
  'config/translation.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'config/migration.lua',
  'config/permissions.lua',
  'config/connection.lua',
  'config/jobs.lua',
  'config/accounts.lua',
  'config/licenses.lua',
  'server/init.lua',
  'server/classes/**/*.lua',
  'server/services/*.lua',
  'server/modules/**/*.lua',
  'server/export.lua',
}

client_scripts {
  'config/world.lua',
  'client/modules/**/*.lua',
}

files {
  'init.lua',
  'lib/**/*.lua',
  'config/callback.lua',
  'config/spatial.lua',
  'config/camera.lua',
  'config/version.lua',
  'config/jobs.lua',
  'config/accounts.lua',
  'config/licenses.lua',
  'config/log.lua',
  'translations/*.lua',
}

dependencies {
  'oxmysql'
}
