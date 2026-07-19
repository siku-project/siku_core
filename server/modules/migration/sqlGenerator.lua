local IDENTIFIER_PATTERN <const> = '^[a-zA-Z_][a-zA-Z0-9_]*$'
local TYPE_PATTERN <const> = "^[%a][%a%d_%s(),']*$"
local TABLE_OPTIONS <const> = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
local RAW_DEFAULTS <const> = { ['NULL'] = true, ['CURRENT_TIMESTAMP'] = true, ['NOW()'] = true }

local REFERENTIAL_ACTIONS <const> = {
  ['CASCADE'] = 'CASCADE',
  ['RESTRICT'] = 'RESTRICT',
  ['SET NULL'] = 'SET NULL',
  ['NO ACTION'] = 'NO ACTION',
  ['SET DEFAULT'] = 'SET DEFAULT',
}

--- Check that an identifier is safe to interpolate into a statement.
---@param value any The candidate table, column or index name.
---@return boolean valid Whether it matches the allowed identifier shape.
local function isValidIdentifier(value)
  return type(value) == 'string' and value:match(IDENTIFIER_PATTERN) ~= nil
end

--- Render a column default, quoting and escaping anything that is not a raw keyword.
---@param default any The declared default value.
---@return string rendered The SQL fragment following the DEFAULT keyword.
local function renderDefault(default)
  local text <const> = tostring(default)
  local upper <const> = text:upper()

  if RAW_DEFAULTS[upper] or upper:find('^CURRENT_TIMESTAMP') then
    return text
  end

  if type(default) == 'number' or type(default) == 'boolean' then
    return text
  end

  return ("'%s'"):format(text:gsub("'", "''"))
end

--- Build the definition of a single column.
---@param column table The column definition.
---@return string? sql, string? reason The fragment, or nil and why it was refused.
local function buildColumn(column)
  if type(column) ~= 'table' then
    return nil, 'column definition must be a table'
  end

  if not isValidIdentifier(column.name) then
    return nil, ("invalid column name '%s'"):format(tostring(column.name))
  end

  if type(column.type) ~= 'string' or not column.type:match(TYPE_PATTERN) then
    return nil, ("invalid type '%s' on column '%s'"):format(tostring(column.type), column.name)
  end

  local parts <const> = { ('`%s`'):format(column.name), column.type }

  if column.unsigned then parts[#parts + 1] = 'UNSIGNED' end
  if column.notNull then parts[#parts + 1] = 'NOT NULL' end
  if column.autoIncrement then parts[#parts + 1] = 'AUTO_INCREMENT' end
  if column.unique then parts[#parts + 1] = 'UNIQUE' end

  if column.default ~= nil then
    parts[#parts + 1] = 'DEFAULT ' .. renderDefault(column.default)
  end

  return table.concat(parts, ' ')
end

--- Build the definition of a single index.
---@param index table The index definition.
---@return string? sql, string? reason The fragment, or nil and why it was refused.
local function buildIndex(index)
  if type(index) ~= 'table' or not isValidIdentifier(index.name) then
    return nil, ("invalid index name '%s'"):format(tostring(type(index) == 'table' and index.name or index))
  end

  if type(index.columns) ~= 'table' or #index.columns == 0 then
    return nil, ("index '%s' needs at least one column"):format(index.name)
  end

  local columns <const> = {}

  for i = 1, #index.columns do
    if not isValidIdentifier(index.columns[i]) then
      return nil, ("invalid column '%s' in index '%s'"):format(tostring(index.columns[i]), index.name)
    end

    columns[i] = ('`%s`'):format(index.columns[i])
  end

  return ('%s `%s` (%s)'):format(
    index.unique and 'UNIQUE KEY' or 'KEY',
    index.name,
    table.concat(columns, ', ')
  )
end

--- Build a CREATE TABLE statement from a table definition.
---@param tableDef table The table definition holding name, columns and optional indexes.
---@return string? sql, string? reason The statement, or nil and why it was refused.
function _SikuInternal.GenerateCreateTableSQL(tableDef)
  if not isValidIdentifier(tableDef.name) then
    return nil, ("invalid table name '%s'"):format(tostring(tableDef.name))
  end

  local lines <const> = {}
  local primaryKeys <const> = {}

  for i = 1, #tableDef.columns do
    local column <const> = tableDef.columns[i]
    local fragment <const>, reason <const> = buildColumn(column)

    if not fragment then
      return nil, ("table '%s': %s"):format(tableDef.name, reason)
    end

    lines[#lines + 1] = fragment

    if column.primaryKey then
      primaryKeys[#primaryKeys + 1] = ('`%s`'):format(column.name)
    end
  end

  if #primaryKeys > 0 then
    lines[#lines + 1] = ('PRIMARY KEY (%s)'):format(table.concat(primaryKeys, ', '))
  end

  for i = 1, #(tableDef.indexes or {}) do
    local fragment <const>, reason <const> = buildIndex(tableDef.indexes[i])

    if not fragment then
      return nil, ("table '%s': %s"):format(tableDef.name, reason)
    end

    lines[#lines + 1] = fragment
  end

  return ('CREATE TABLE IF NOT EXISTS `%s` (\n  %s\n) %s'):format(
    tableDef.name,
    table.concat(lines, ',\n  '),
    TABLE_OPTIONS
  )
end

--- Build an ALTER TABLE statement adding one column.
---@param tableName string The table receiving the column.
---@param column table The column definition.
---@return string? sql, string? reason The statement, or nil and why it was refused.
function _SikuInternal.GenerateAddColumnSQL(tableName, column)
  if not isValidIdentifier(tableName) then
    return nil, ("invalid table name '%s'"):format(tostring(tableName))
  end

  local fragment <const>, reason <const> = buildColumn(column)

  if not fragment then
    return nil, ("table '%s': %s"):format(tableName, reason)
  end

  return ('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, fragment)
end

--- Build an ALTER TABLE statement adding one foreign key.
---@param tableName string The table receiving the constraint.
---@param foreignKey table The foreign key definition.
---@return string? sql, string? reason The statement, or nil and why it was refused.
function _SikuInternal.GenerateAddForeignKeySQL(tableName, foreignKey)
  local references <const> = type(foreignKey) == 'table' and foreignKey.references or nil

  if type(references) ~= 'table' then
    return nil, ("foreign key on '%s' is missing its references block"):format(tostring(tableName))
  end

  local names <const> = { tableName, foreignKey.column, references.table, references.column }

  for i = 1, #names do
    if not isValidIdentifier(names[i]) then
      return nil, ("invalid identifier '%s' in a foreign key on '%s'"):format(tostring(names[i]), tostring(tableName))
    end
  end

  local statement = ('ALTER TABLE `%s` ADD CONSTRAINT `fk_%s_%s` FOREIGN KEY (`%s`) REFERENCES `%s` (`%s`)'):format(
    tableName,
    tableName,
    foreignKey.column,
    foreignKey.column,
    references.table,
    references.column
  )

  if foreignKey.onDelete then
    local action <const> = REFERENTIAL_ACTIONS[tostring(foreignKey.onDelete):upper()]

    if not action then
      return nil, ("invalid onDelete action '%s' on '%s'"):format(tostring(foreignKey.onDelete), tableName)
    end

    statement = ('%s ON DELETE %s'):format(statement, action)
  end

  if foreignKey.onUpdate then
    local action <const> = REFERENTIAL_ACTIONS[tostring(foreignKey.onUpdate):upper()]

    if not action then
      return nil, ("invalid onUpdate action '%s' on '%s'"):format(tostring(foreignKey.onUpdate), tableName)
    end

    statement = ('%s ON UPDATE %s'):format(statement, action)
  end

  return statement
end
