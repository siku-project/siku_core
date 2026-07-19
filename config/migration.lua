MigrationConfig = {
  --- Whether this resource migrates its own schema on startup.
  ---
  --- • true: the schema below is created or repaired at boot
  --- • false: nothing is inspected and no query is sent
  ---
  --- Every resource that wants auto-migration ships its own copy of
  --- this file and passes it to Siku.RunMigration.
  enabled = true,

  --- Whether a schema whose version was already applied is still
  --- inspected for elements that went missing.
  ---
  --- • true (default): missing tables, columns and foreign keys are
  ---   recreated even when the version has not changed, which repairs
  ---   a database someone edited by hand
  --- • false: nothing happens until the version below changes
  detectMissing = true,

  --- Resources whose schema must be fully applied before this one runs.
  ---
  --- • {} (default): this schema depends on nobody
  --- • { 'siku_core' }: wait until siku_core finished migrating
  ---
  --- Declare here every resource owning a table referenced by a foreign
  --- key below, or holding a table this schema alters. Start order in
  --- server.cfg then stops mattering: a resource that starts early simply
  --- waits for the ones it needs, whatever order they boot in.
  ---
  --- A dependency that is not installed fails immediately. One that never
  --- finishes gives up after 30 seconds, and this schema is not applied.
  dependencies = {},

  schema = {
    --- Bump this whenever the tables below change.
    ---
    --- The pair (resource, version) is recorded in `siku_migrations`
    --- once applied, and a version already recorded is never replayed.
    version = '1.0.0',

    --- The tables this resource owns.
    ---
    --- Each entry accepts:
    ---   name         string, the table name
    ---   columns      list of column definitions, at least one
    ---   indexes      optional list of { name, columns, unique? }
    ---   foreignKeys  optional list of { column, references = { table, column }, onDelete?, onUpdate? }
    ---
    --- Each column accepts:
    ---   name          string, the column name
    ---   type          string, the raw SQL type such as 'VARCHAR(64)'
    ---   primaryKey    optional boolean
    ---   autoIncrement optional boolean
    ---   notNull       optional boolean
    ---   unique        optional boolean
    ---   unsigned      optional boolean
    ---   default       optional value, 'NULL' and 'CURRENT_TIMESTAMP' are passed through raw
    ---
    --- Migration is additive: tables, columns and foreign keys that are
    --- missing get created. Existing ones are never altered or dropped,
    --- so changing a column type still needs a manual migration.
    ---
    --- These names are unprefixed, so this schema expects a database it
    --- owns. Pointing it at one where another framework already created
    --- a `users` table would make migration add these columns to that
    --- existing table instead of creating its own.
    tables = {
      {
        name = 'users',
        columns = {
          { name = 'id', type = 'INT', unsigned = true, autoIncrement = true, primaryKey = true },
          { name = 'license', type = 'VARCHAR(64)', notNull = true, unique = true },
          { name = 'discord_id', type = 'VARCHAR(30)', default = 'NULL' },
          { name = 'ip', type = 'VARCHAR(45)', default = 'NULL' },
          { name = 'last_played_character', type = 'INT', unsigned = true, default = 'NULL' },
          { name = 'total_playtime', type = 'INT', unsigned = true, notNull = true, default = 0 },
          { name = 'last_seen', type = 'TIMESTAMP', default = 'CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP' },
          { name = 'created_at', type = 'TIMESTAMP', default = 'CURRENT_TIMESTAMP' },
        },
        indexes = {
          { name = 'idx_users_discord_id', columns = { 'discord_id' } },
          { name = 'idx_users_last_seen', columns = { 'last_seen' } },
        },
      },
      {
        name = 'characters',
        columns = {
          { name = 'id', type = 'INT', unsigned = true, autoIncrement = true, primaryKey = true },
          { name = 'user_id', type = 'INT', unsigned = true, notNull = true },
          { name = 'firstname', type = 'VARCHAR(50)', notNull = true },
          { name = 'lastname', type = 'VARCHAR(50)', notNull = true },
          { name = 'date_of_birth', type = 'DATE', default = 'NULL' },
          { name = 'gender', type = 'VARCHAR(20)', default = 'NULL' },
          { name = 'ped_model', type = 'VARCHAR(60)', notNull = true },
          { name = 'x', type = 'FLOAT', notNull = true },
          { name = 'y', type = 'FLOAT', notNull = true },
          { name = 'z', type = 'FLOAT', notNull = true },
          { name = 'heading', type = 'FLOAT', notNull = true },
          { name = 'is_dead', type = 'BOOLEAN', notNull = true, default = 0 },
          { name = 'playtime', type = 'INT', unsigned = true, notNull = true, default = 0 },
          { name = 'last_played', type = 'TIMESTAMP', default = 'CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP' },
          { name = 'created_at', type = 'TIMESTAMP', default = 'CURRENT_TIMESTAMP' },
        },
        indexes = {
          { name = 'idx_characters_user_id', columns = { 'user_id' } },
          { name = 'idx_characters_name', columns = { 'lastname', 'firstname' } },
        },
        foreignKeys = {
          {
            column = 'user_id',
            references = { table = 'users', column = 'id' },
            onDelete = 'CASCADE',
            onUpdate = 'CASCADE',
          },
        },
      },
    },
  },
}
