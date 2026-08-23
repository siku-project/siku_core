Siku.migration = {}

local MIGRATIONS_TABLE <const> = 'siku_migrations'
local DEPENDENCY_TIMEOUT <const> = 30000
local LOCK_TIMEOUT <const> = 60000
local POLL_INTERVAL <const> = 100

local completed = {}
local busy = false

--- Find a declared dependency that will never complete because it is absent.
---@param dependencies table The resource names this schema waits for.
---@return string? absent The first dependency that is not installed.
local function findAbsentDependency(dependencies)
  for i = 1, #dependencies do
    local dependency <const> = dependencies[i]

    if not completed[dependency] and GetResourceState(dependency) == 'missing' then
      return dependency
    end
  end

  return nil
end

--- List the dependencies that have not finished migrating yet.
---@param dependencies table The resource names this schema waits for.
---@return table pending The names still being waited on.
local function pendingDependencies(dependencies)
  local pending <const> = {}

  for i = 1, #dependencies do
    if not completed[dependencies[i]] then
      pending[#pending + 1] = dependencies[i]
    end
  end

  return pending
end

--- Block until every declared dependency finished migrating.
---@param resource string The resource waiting.
---@param dependencies any The resource names it declared, if any.
---@return boolean ready Whether every dependency completed in time.
local function waitForDependencies(resource, dependencies)
  if type(dependencies) ~= 'table' or #dependencies == 0 then
    return true
  end

  local deadline <const> = GetGameTimer() + DEPENDENCY_TIMEOUT

  while true do
    local absent <const> = findAbsentDependency(dependencies)

    if absent then
      Siku.print.error(("[%s] Depends on '%s' which is not installed, migration skipped"):format(resource, absent))
      return false
    end

    local pending <const> = pendingDependencies(dependencies)

    if #pending == 0 then
      return true
    end

    if GetGameTimer() >= deadline then
      Siku.print.error(("[%s] Gave up after %dms waiting on: %s"):format(resource, DEPENDENCY_TIMEOUT, table.concat(pending, ', ')))
      return false
    end

    Wait(POLL_INTERVAL)
  end
end

--- Take the global migration lock so two resources never apply DDL at once.
---@param resource string The resource asking for the lock.
---@return boolean acquired Whether the lock was taken before the timeout.
local function acquireLock(resource)
  local deadline <const> = GetGameTimer() + LOCK_TIMEOUT

  while busy do
    if GetGameTimer() >= deadline then
      Siku.print.error(("[%s] Gave up waiting for the migration lock"):format(resource))
      return false
    end

    Wait(POLL_INTERVAL)
  end

  busy = true

  return true
end

--- Create the tracking table recording which version each resource applied.
local function ensureMigrationsTable()
  MySQL.query.await(([[
    CREATE TABLE IF NOT EXISTS `%s` (
      `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      `resource` VARCHAR(255) NOT NULL,
      `version` VARCHAR(50) NOT NULL,
      `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY `idx_resource_version` (`resource`, `version`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ]]):format(MIGRATIONS_TABLE))
end

--- Check whether a resource already recorded this exact schema version.
---@param resource string The resource owning the schema.
---@param version string The schema version to look for.
---@return boolean applied Whether the pair was already recorded.
local function isVersionApplied(resource, version)
  local found <const> = MySQL.scalar.await(
    ('SELECT 1 FROM `%s` WHERE resource = ? AND version = ? LIMIT 1'):format(MIGRATIONS_TABLE),
    { resource, version }
  )

  return found ~= nil
end

--- Record that a resource applied a schema version.
---@param resource string The resource owning the schema.
---@param version string The schema version that was applied.
local function recordVersion(resource, version)
  MySQL.query.await(
    ('INSERT IGNORE INTO `%s` (resource, version) VALUES (?, ?)'):format(MIGRATIONS_TABLE),
    { resource, version }
  )
end

--- Run one generated statement, reporting a refusal or a database failure.
---@param resource string The resource the statement belongs to.
---@param sql string? The statement, or nil when generation refused it.
---@param reason string? Why generation refused, when it did.
---@param description string What the statement does, used in logs.
---@return boolean ok Whether the statement ran.
local function runStatement(resource, sql, reason, description)
  if not sql then
    Siku.print.error(("[%s] Refused to build %s: %s"):format(resource, description, reason))
    return false
  end

  local ok <const>, err <const> = pcall(MySQL.query.await, sql)

  if not ok then
    Siku.print.error(("[%s] Failed to apply %s: %s"):format(resource, description, tostring(err)))
    return false
  end

  Siku.print.success(("[%s] Applied %s"):format(resource, description))

  return true
end

--- Create every missing element, stopping at the first failure.
---@param resource string The resource owning the schema.
---@param missing table The elements reported absent by the inspector.
---@return boolean ok, number applied Whether everything ran, and how many statements succeeded.
local function applyMissing(resource, missing)
  local applied = 0

  for i = 1, #missing.tables do
    local tableDef <const> = missing.tables[i]
    local sql <const>, reason <const> = _SikuInternal.GenerateCreateTableSQL(tableDef)

    if not runStatement(resource, sql, reason, ("table `%s`"):format(tableDef.name)) then
      return false, applied
    end

    applied = applied + 1
  end

  for i = 1, #missing.columns do
    local entry <const> = missing.columns[i]

    for j = 1, #entry.columns do
      local column <const> = entry.columns[j]
      local sql <const>, reason <const> = _SikuInternal.GenerateAddColumnSQL(entry.tableName, column)

      if not runStatement(resource, sql, reason, ("column `%s`.`%s`"):format(entry.tableName, tostring(column.name))) then
        return false, applied
      end

      applied = applied + 1
    end
  end

  for i = 1, #missing.foreignKeys do
    local entry <const> = missing.foreignKeys[i]

    for j = 1, #entry.foreignKeys do
      local foreignKey <const> = entry.foreignKeys[j]
      local sql <const>, reason <const> = _SikuInternal.GenerateAddForeignKeySQL(entry.tableName, foreignKey)

      if not runStatement(resource, sql, reason, ("foreign key `%s`.`%s`"):format(entry.tableName, tostring(foreignKey.column))) then
        return false, applied
      end

      applied = applied + 1
    end
  end

  return true, applied
end

--- Check that a table definition carries what the generator needs.
---@param resource string The resource owning the schema.
---@param tableDef any The candidate definition.
---@param index number Its position in the schema, used in messages.
---@return boolean valid Whether the definition is usable.
local function isValidTable(resource, tableDef, index)
  if type(tableDef) ~= 'table' then
    Siku.print.error(("[%s] Table at index %d must be a table"):format(resource, index))
    return false
  end

  if type(tableDef.name) ~= 'string' or tableDef.name == '' then
    Siku.print.error(("[%s] Table at index %d has no name"):format(resource, index))
    return false
  end

  if type(tableDef.columns) ~= 'table' or #tableDef.columns == 0 then
    Siku.print.error(("[%s] Table '%s' needs at least one column"):format(resource, tableDef.name))
    return false
  end

  return true
end

--- Check that a migration config has the shape the runner expects.
---@param resource string The resource owning the config.
---@param config any The candidate config.
---@return boolean valid Whether the config is usable.
local function isValidConfig(resource, config)
  if type(config) ~= 'table' then
    Siku.print.error(("[%s] Migration config must be a table, got %s"):format(resource, type(config)))
    return false
  end

  if type(config.schema) ~= 'table' then
    Siku.print.error(("[%s] Migration config needs a schema table"):format(resource))
    return false
  end

  if type(config.schema.version) ~= 'string' or config.schema.version == '' then
    Siku.print.error(("[%s] Migration schema needs a non-empty version"):format(resource))
    return false
  end

  if type(config.schema.tables) ~= 'table' then
    Siku.print.error(("[%s] Migration schema needs a tables list"):format(resource))
    return false
  end

  for i = 1, #config.schema.tables do
    if not isValidTable(resource, config.schema.tables[i], i) then
      return false
    end
  end

  return true
end

--- Inspect the live database and create whatever the schema declares but lacks.
---@param resource string The resource owning the schema.
---@param config table The validated migration config.
---@return boolean ok, number applied Whether the run succeeded, and how many statements were applied.
local function applySchema(resource, config)
  local schema <const> = config.schema
  local database <const> = _SikuInternal.GetDatabaseName()

  if not database then
    Siku.print.error(("[%s] Unable to read the database name, migration skipped"):format(resource))
    return false, 0
  end

  ensureMigrationsTable()

  local alreadyApplied <const> = isVersionApplied(resource, schema.version)

  if alreadyApplied and not config.detectMissing then
    Siku.print.debug(("[%s] Schema version %s is already applied"):format(resource, schema.version))
    return true, 0
  end

  local missing <const> = _SikuInternal.InspectSchema(database, schema.tables)
  local total <const> = #missing.tables + #missing.columns + #missing.foreignKeys

  if alreadyApplied and total == 0 then
    Siku.print.debug(("[%s] Schema version %s is applied and complete"):format(resource, schema.version))
    return true, 0
  end

  if alreadyApplied then
    Siku.print.warn(("[%s] %d schema element(s) went missing, repairing"):format(resource, total))
  else
    Siku.print.info(("[%s] Applying schema version %s"):format(resource, schema.version))
  end

  local ok <const>, applied <const> = applyMissing(resource, missing)

  if not ok then
    Siku.print.error(("[%s] Migration stopped after %d statement(s), version %s not recorded"):format(resource, applied, schema.version))
    return false, applied
  end

  if not alreadyApplied then
    recordVersion(resource, schema.version)
    Siku.print.success(("[%s] Schema version %s applied, %d statement(s)"):format(resource, schema.version, applied))
  else
    Siku.print.success(("[%s] Schema repaired, %d statement(s)"):format(resource, applied))
  end

  return true, applied
end

--- Create or repair the calling resource's schema from its migration config.
---
--- Migration is additive: absent tables, columns and foreign keys are created,
--- existing ones are never altered or dropped. A version already recorded is
--- replayed only when detectMissing asks for a repair pass.
---
--- Declared dependencies are awaited first, then a global lock is taken, so two
--- resources never apply DDL at the same time and start order stops mattering.
---@param config table The migration config, shaped like the shipped config/migration.lua.
---@return boolean ok, number applied Whether the run succeeded, and how many statements were applied.
function Siku.migration.run(config)
  local resource <const> = GetInvokingResource() or Siku.name

  if not isValidConfig(resource, config) then
    return false, 0
  end

  if not config.enabled then
    Siku.print.debug(("[%s] Auto-migration is disabled"):format(resource))
    completed[resource] = true

    return true, 0
  end

  if #config.schema.tables == 0 then
    Siku.print.debug(("[%s] Migration schema declares no table"):format(resource))
    completed[resource] = true

    return true, 0
  end

  if not waitForDependencies(resource, config.dependencies) then
    return false, 0
  end

  if not acquireLock(resource) then
    return false, 0
  end

  local ok <const>, applied <const> = applySchema(resource, config)

  busy = false

  if ok then
    completed[resource] = true
  end

  return ok, applied
end
