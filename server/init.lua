Siku.bucket = {}
Siku.cron = {}
Siku.permissions = {}

local databaseReady = false

--- Nothing of this resource runs in here. A callback handed to another
--- resource is invoked by it, so everything started from inside one is
--- credited to that resource rather than to this one — the name a schema is
--- recorded under, and the name every resource waiting on it waits for. So
--- this only raises the flag.
MySQL.ready(function()
  databaseReady = true
end)

--- The core is the one resource with nothing to wait on: its schema declares
--- no dependency, so the connection is what it waits for. Everything else
--- waits for the core instead, and by then the database has already answered.
CreateThread(function()
  while not databaseReady do
    Wait(100)
  end

  Siku.VersionCheck('siku-project/siku_core')
  Siku.RunMigration(MigrationConfig)
  _SikuInternal.InitPermissions()

  Siku.print.success('Siku core initialization finished ! Framework Ready')
end)
