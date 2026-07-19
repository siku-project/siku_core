Siku.print = {}

local RESOURCE_NAME <const> = GetCurrentResourceName()
local DEFAULT_LEVEL <const> = 'info'
local RESET <const> = '^7'
local INDENT <const> = '  '
local MAX_DEPTH <const> = 4
local CONVAR_LEVEL <const> = 'siku:logLevel'

local LEVELS <const> = {
  error = { severity = 1, label = 'ERROR', color = '^1' },
  warn = { severity = 2, label = 'WARN', color = '^3' },
  success = { severity = 3, label = 'SUCCESS', color = '^2' },
  info = { severity = 3, label = 'INFO', color = '^5' },
  debug = { severity = 4, label = 'DEBUG', color = '^6' },
}

local configuredLevel <const> = GetConvar(CONVAR_LEVEL, DEFAULT_LEVEL)
local resolvedLevel <const> = LEVELS[configuredLevel]
local activeLevel <const> = resolvedLevel and configuredLevel or DEFAULT_LEVEL
local activeSeverity <const> = LEVELS[activeLevel].severity

--- Serialize any Lua value into a readable representation.
---@param value any The value to serialize.
---@param depth number The current nesting depth, used to bound recursion.
---@param seen table Tracks the tables being walked so cycles are broken.
---@return string serialized The readable representation of the value.
local function serialize(value, depth, seen)
  local valueType <const> = type(value)

  if valueType == 'string' then
    return ('%q'):format(value)
  end

  if valueType ~= 'table' then
    return tostring(value)
  end

  if seen[value] then
    return '<cycle>'
  end

  local meta <const> = getmetatable(value)

  if meta and meta.__tostring then
    return tostring(value)
  end

  if depth >= MAX_DEPTH then
    return '<...>'
  end

  seen[value] = true

  local parts <const> = {}
  local padding <const> = INDENT:rep(depth + 1)

  for key, entry in pairs(value) do
    parts[#parts + 1] = ('%s[%s] = %s'):format(
      padding,
      serialize(key, depth + 1, seen),
      serialize(entry, depth + 1, seen)
    )
  end

  seen[value] = nil

  if #parts == 0 then
    return '{}'
  end

  return ('{\n%s\n%s}'):format(table.concat(parts, ',\n'), INDENT:rep(depth))
end

--- Join every argument into a single printable message.
---@param ... any The values to format.
---@return string message The joined message.
local function formatArgs(...)
  local count <const> = select('#', ...)
  local parts <const> = {}

  for i = 1, count do
    local value <const> = select(i, ...)
    parts[i] = type(value) == 'string' and value or serialize(value, 0, {})
  end

  return table.concat(parts, ' ')
end

--- Resolve which resource asked for the log line.
---@return string resource The invoking resource, or siku_core when called internally.
local function resolveSource()
  return GetInvokingResource() or RESOURCE_NAME
end

--- Write a line to the console when its level passes the active filter.
---@param level table The level descriptor holding severity, label and color.
---@param ... any The values to log.
local function write(level, ...)
  if level.severity > activeSeverity then
    return
  end

  print(('%s[%s] [%s]%s %s'):format(level.color, resolveSource(), level.label, RESET, formatArgs(...)))
end

--- Log a successful outcome.
---@param ... any The values to log.
function Siku.print.success(...)
  write(LEVELS.success, ...)
end

--- Log an informational message.
---@param ... any The values to log.
function Siku.print.info(...)
  write(LEVELS.info, ...)
end

--- Log a recoverable problem that does not stop execution.
---@param ... any The values to log.
function Siku.print.warn(...)
  write(LEVELS.warn, ...)
end

--- Log a failure. This never raises, so the caller keeps control.
---@param ... any The values to log.
function Siku.print.error(...)
  write(LEVELS.error, ...)
end

--- Log a diagnostic message, hidden unless the active level is 'debug'.
---@param ... any The values to log.
function Siku.print.debug(...)
  write(LEVELS.debug, ...)
end

--- Raise a Lua error carrying the caller's resource name and a stack trace.
---@param ... any The values describing the failure.
function Siku.print.throw(...)
  error(('[%s] %s'):format(resolveSource(), formatArgs(...)), 2)
end

--- Get the level currently filtering console output.
---@return string level The active level name, set by the 'siku:logLevel' convar.
function Siku.print.getLevel()
  return activeLevel
end

if not resolvedLevel then
  Siku.print.warn(("Unknown log level '%s' in convar '%s', using '%s'"):format(
    configuredLevel,
    CONVAR_LEVEL,
    DEFAULT_LEVEL
  ))
end
