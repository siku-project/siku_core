local DATABASE_POLL_INTERVAL <const> = 100

_SikuInternal = {}

local databaseReady = false

MySQL.ready(function()
  databaseReady = true
end)

CreateThread(function()
  while not databaseReady do
    Wait(DATABASE_POLL_INTERVAL)
  end

  Siku.version.checkRelease('siku-project/siku_core')
  Siku.migration.run(MigrationConfig)
  _SikuInternal.InitPermissions()

  Siku.print.success('Siku core initialization finished ! Framework Ready')
end)
