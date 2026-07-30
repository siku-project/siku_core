Siku.bucket = {}
Siku.cron = {}
Siku.permissions = {}

MySQL.ready(function()
  Siku.VersionCheck('siku-project/siku_core')
  Siku.RunMigration(MigrationConfig)
  _SikuInternal.InitPermissions()

  Siku.print.success('Siku core initialization finished ! Framework Ready')
end)
