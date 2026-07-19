Siku.VersionCheck('siku-project/siku_core')

MySQL.ready(function()
    Siku.RunMigration(MigrationConfig)

    Siku.print.success("Siku core initialization finished ! Framework Ready")
end)
