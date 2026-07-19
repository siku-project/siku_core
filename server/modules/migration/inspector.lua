--- Build a comma separated list of placeholders for an IN clause.
---@param count number How many placeholders are needed.
---@return string placeholders The rendered list.
local function placeholders(count)
  local marks <const> = {}

  for i = 1, count do
    marks[i] = '?'
  end

  return table.concat(marks, ', ')
end

--- Collect the names of the schema tables that already exist.
---@param database string The database being inspected.
---@param names table The table names declared by the schema.
---@return table existing A set of the table names found.
local function fetchExistingTables(database, names)
  local rows <const> = MySQL.query.await(
    ('SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME IN (%s)'):format(placeholders(#names)),
    { database, table.unpack(names) }
  )

  local existing <const> = {}

  for i = 1, #(rows or {}) do
    existing[rows[i].TABLE_NAME] = true
  end

  return existing
end

--- Collect every column of the schema tables, keyed by table then column.
---@param database string The database being inspected.
---@param names table The table names to look at.
---@return table columns A set of columns per table.
local function fetchExistingColumns(database, names)
  local rows <const> = MySQL.query.await(
    ('SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME IN (%s)'):format(placeholders(#names)),
    { database, table.unpack(names) }
  )

  local columns <const> = {}

  for i = 1, #(rows or {}) do
    local row <const> = rows[i]

    columns[row.TABLE_NAME] = columns[row.TABLE_NAME] or {}
    columns[row.TABLE_NAME][row.COLUMN_NAME] = true
  end

  return columns
end

--- Collect every foreign key of the schema tables, keyed by the relation it enforces.
---@param database string The database being inspected.
---@param names table The table names to look at.
---@return table foreignKeys A set of relations per table, independent of constraint names.
local function fetchExistingForeignKeys(database, names)
  local rows <const> = MySQL.query.await(
    ([[
      SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
      FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = ? AND REFERENCED_TABLE_NAME IS NOT NULL AND TABLE_NAME IN (%s)
    ]]):format(placeholders(#names)),
    { database, table.unpack(names) }
  )

  local foreignKeys <const> = {}

  for i = 1, #(rows or {}) do
    local row <const> = rows[i]
    local relation <const> = ('%s>%s.%s'):format(row.COLUMN_NAME, row.REFERENCED_TABLE_NAME, row.REFERENCED_COLUMN_NAME)

    foreignKeys[row.TABLE_NAME] = foreignKeys[row.TABLE_NAME] or {}
    foreignKeys[row.TABLE_NAME][relation] = true
  end

  return foreignKeys
end

--- Read the name of the database the server is connected to.
---@return string? database The database name, or nil when it cannot be read.
function _SikuInternal.GetDatabaseName()
  return MySQL.scalar.await('SELECT DATABASE()')
end

--- Compare a declared schema against the live database in three grouped queries.
---@param database string The database to inspect.
---@param tables table The table definitions declared by the schema.
---@return table missing The tables, columns and foreign keys that are absent.
function _SikuInternal.InspectSchema(database, tables)
  local missing <const> = { tables = {}, columns = {}, foreignKeys = {} }
  local names <const> = {}

  for i = 1, #tables do
    names[i] = tables[i].name
  end

  if #names == 0 then
    return missing
  end

  local existingTables <const> = fetchExistingTables(database, names)
  local existingColumns <const> = fetchExistingColumns(database, names)
  local existingForeignKeys <const> = fetchExistingForeignKeys(database, names)

  for i = 1, #tables do
    local tableDef <const> = tables[i]
    local declaredKeys <const> = tableDef.foreignKeys or {}

    if not existingTables[tableDef.name] then
      missing.tables[#missing.tables + 1] = tableDef
    else
      local presentColumns <const> = existingColumns[tableDef.name] or {}
      local absentColumns <const> = {}

      for j = 1, #tableDef.columns do
        if not presentColumns[tableDef.columns[j].name] then
          absentColumns[#absentColumns + 1] = tableDef.columns[j]
        end
      end

      if #absentColumns > 0 then
        missing.columns[#missing.columns + 1] = { tableName = tableDef.name, columns = absentColumns }
      end
    end

    local presentKeys <const> = existingForeignKeys[tableDef.name] or {}
    local absentKeys <const> = {}

    for j = 1, #declaredKeys do
      local foreignKey <const> = declaredKeys[j]
      local references <const> = foreignKey.references or {}
      local relation <const> = ('%s>%s.%s'):format(
        tostring(foreignKey.column),
        tostring(references.table),
        tostring(references.column)
      )

      if not presentKeys[relation] then
        absentKeys[#absentKeys + 1] = foreignKey
      end
    end

    if #absentKeys > 0 then
      missing.foreignKeys[#missing.foreignKeys + 1] = { tableName = tableDef.name, foreignKeys = absentKeys }
    end
  end

  return missing
end
