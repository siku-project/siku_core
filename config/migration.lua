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
    version = '1.1.0',

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
      {
        name = 'roles',
        columns = {
          { name = 'id', type = 'INT', unsigned = true, autoIncrement = true, primaryKey = true },
          { name = 'name', type = 'VARCHAR(50)', notNull = true, unique = true },
          { name = 'label', type = 'VARCHAR(100)', notNull = true },
          { name = 'is_primary', type = 'BOOLEAN', notNull = true, default = 0 },
          { name = 'inherits_from', type = 'INT', unsigned = true, default = 'NULL' },
          { name = 'created_at', type = 'TIMESTAMP', default = 'CURRENT_TIMESTAMP' },
        },
        indexes = {
          { name = 'idx_roles_is_primary', columns = { 'is_primary' } },
        },
        foreignKeys = {
          {
            column = 'inherits_from',
            references = { table = 'roles', column = 'id' },
            onDelete = 'SET NULL',
            onUpdate = 'CASCADE',
          },
        },
      },
      {
        name = 'permissions',
        columns = {
          { name = 'id', type = 'INT', unsigned = true, autoIncrement = true, primaryKey = true },
          { name = 'name', type = 'VARCHAR(100)', notNull = true, unique = true },
          { name = 'description', type = 'VARCHAR(255)', default = 'NULL' },
        },
      },
      {
        name = 'role_permissions',
        columns = {
          { name = 'role_id', type = 'INT', unsigned = true, notNull = true, primaryKey = true },
          { name = 'permission_id', type = 'INT', unsigned = true, notNull = true, primaryKey = true },
        },
        foreignKeys = {
          {
            column = 'role_id',
            references = { table = 'roles', column = 'id' },
            onDelete = 'CASCADE',
            onUpdate = 'CASCADE',
          },
          {
            column = 'permission_id',
            references = { table = 'permissions', column = 'id' },
            onDelete = 'CASCADE',
            onUpdate = 'CASCADE',
          },
        },
      },
      {
        name = 'character_roles',
        columns = {
          { name = 'character_id', type = 'INT', unsigned = true, notNull = true, primaryKey = true },
          { name = 'role_id', type = 'INT', unsigned = true, notNull = true, primaryKey = true },
          { name = 'assigned_at', type = 'TIMESTAMP', default = 'CURRENT_TIMESTAMP' },
          { name = 'expires_at', type = 'TIMESTAMP', default = 'NULL' },
        },
        foreignKeys = {
          {
            column = 'character_id',
            references = { table = 'characters', column = 'id' },
            onDelete = 'CASCADE',
            onUpdate = 'CASCADE',
          },
          {
            column = 'role_id',
            references = { table = 'roles', column = 'id' },
            onDelete = 'CASCADE',
            onUpdate = 'CASCADE',
          },
        },
      },
      {
        name = 'rbac_audit_log',
        columns = {
          { name = 'id', type = 'INT', unsigned = true, autoIncrement = true, primaryKey = true },
          { name = 'action', type = 'VARCHAR(50)', notNull = true },
          { name = 'target_type', type = 'VARCHAR(50)', notNull = true },
          { name = 'target_id', type = 'VARCHAR(100)', notNull = true },
          { name = 'performed_by', type = 'INT', unsigned = true, default = 'NULL' },
          { name = 'details', type = 'TEXT', default = 'NULL' },
          { name = 'created_at', type = 'TIMESTAMP', default = 'CURRENT_TIMESTAMP' },
        },
        indexes = {
          { name = 'idx_audit_action', columns = { 'action' } },
          { name = 'idx_audit_target', columns = { 'target_type', 'target_id' } },
          { name = 'idx_audit_created_at', columns = { 'created_at' } },
        },
      },
    },
  },
}
