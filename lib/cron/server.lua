local TICK_INTERVAL <const> = 30000
local SECONDS_PER_MINUTE <const> = 60
local RERUN_GUARD_SECONDS <const> = 59
local SEARCH_HORIZON_MINUTES <const> = 366 * 24 * 60
local CRON_FIELD_COUNT <const> = 5
local SUNDAY_WDAY <const> = 1
local ISO_SUNDAY <const> = 7

local RANGES <const> = {
  minute = { min = 0, max = 59 },
  hour = { min = 0, max = 23 },
  day = { min = 1, max = 31 },
  month = { min = 1, max = 12 },
  weekday = { min = 1, max = 7 },
}

local WEEKDAY_NAMES <const> = {
  mon = '1', tue = '2', wed = '3', thu = '4',
  fri = '5', sat = '6', sun = '7',
}

local MONTH_NAMES <const> = {
  jan = '1', feb = '2', mar = '3', apr = '4',
  may = '5', jun = '6', jul = '7', aug = '8',
  sep = '9', oct = '10', nov = '11', dec = '12',
}

local SHORTCUTS <const> = {
  ['@yearly']   = '0 0 1 1 *',
  ['@annually'] = '0 0 1 1 *',
  ['@monthly']  = '0 0 1 * *',
  ['@weekly']   = '0 0 * * 1',
  ['@daily']    = '0 0 * * *',
  ['@midnight'] = '0 0 * * *',
  ['@hourly']   = '0 * * * *',
}

local entries = {}
local nextId = 1
local lastTickMinute = -1

local cron <const> = {}

--- Replace weekday/month names with their numeric equivalents.
---@param expr string The expression to process.
---@param map table The name-to-number mapping.
---@return string result The expression with names replaced.
local function replaceNames(expr, map)
  return expr:lower():gsub('%a+', function(match)
    return map[match] or match
  end)
end

--- Get the last day of a given month/year.
---@param year number The year.
---@param month number The month (1-12).
---@return number lastDay The last day of the month.
local function getLastDayOfMonth(year, month)
  return os.date('*t', os.time({ year = year, month = month + 1, day = 0 })).day
end

local parseField

--- Build a matcher for a stepped field expression such as '*/5' or '1-10/2'.
---@param expr string The field expression containing a step.
---@param field string The field name (minute, hour, day, month, weekday).
---@return function matcher A function(value) that returns true if the value matches.
local function parseStep(expr, field)
  local rangeExpr <const>, stepStr <const> = expr:match('(.+)/(%d+)')
  local step <const> = tonumber(stepStr)

  if not step or step <= 0 then
    Siku.print.throw(('Invalid step \'%s\' in %s'):format(stepStr or '', field))
  end

  if rangeExpr == '*' then
    local min <const> = RANGES[field].min

    return function(v)
      return (v - min) % step == 0
    end
  end

  local start <const>, finish <const> = rangeExpr:match('(%d+)-(%d+)')

  if start and finish then
    local s <const> = tonumber(start)
    local f <const> = tonumber(finish)

    return function(v)
      return v >= s and v <= f and (v - s) % step == 0
    end
  end

  Siku.print.throw(('Invalid step expression \'%s\' in %s'):format(expr, field))
end

--- Build a matcher for a range field expression such as '1-5', tolerating a wrapping range.
---@param expr string The field expression containing a range.
---@param field string The field name (minute, hour, day, month, weekday).
---@return function matcher A function(value) that returns true if the value matches.
local function parseRange(expr, field)
  local startStr <const>, finishStr <const> = expr:match('(%d+)-(%d+)')

  if not startStr or not finishStr then
    Siku.print.throw(('Invalid range \'%s\' in %s'):format(expr, field))
  end

  local s <const> = tonumber(startStr)
  local f <const> = tonumber(finishStr)

  if f < s then
    return function(v)
      return v >= s or v <= f
    end
  end

  return function(v)
    return v >= s and v <= f
  end
end

--- Parse a single cron field expression into a matcher function.
---@param expr string The field expression.
---@param field string The field name (minute, hour, day, month, weekday).
---@return function matcher A function(value, dateTable) that returns true if the value matches.
parseField = function(expr, field)
  expr = expr:match('^%s*(.-)%s*$')

  if expr == '*' then
    return function()
      return true
    end
  end

  if field == 'day' and expr:lower() == 'l' then
    return function(_, dt)
      return dt.day == getLastDayOfMonth(dt.year, dt.month)
    end
  end

  if field == 'weekday' then
    expr = replaceNames(expr, WEEKDAY_NAMES)
  end

  if field == 'month' then
    expr = replaceNames(expr, MONTH_NAMES)
  end

  if expr:find(',') then
    local matchers <const> = {}

    for part in expr:gmatch('[^,]+') do
      matchers[#matchers + 1] = parseField(part, field)
    end

    return function(v, dt)
      for i = 1, #matchers do
        if matchers[i](v, dt) then
          return true
        end
      end

      return false
    end
  end

  if expr:find('/') then
    return parseStep(expr, field)
  end

  if expr:find('-') then
    return parseRange(expr, field)
  end

  local num <const> = tonumber(expr)

  if not num then
    Siku.print.throw(('Invalid value \'%s\' in %s'):format(expr, field))
  end

  return function(v)
    return v == num
  end
end

--- Parse a full cron expression into field matchers.
---@param expression string The cron expression (5 fields or shortcut like @daily).
---@return table fields { minute, hour, day, month, weekday } matcher functions.
local function parseExpression(expression)
  local resolved <const> = SHORTCUTS[expression:lower()] or expression
  local parts <const> = {}

  for part in resolved:gmatch('%S+') do
    parts[#parts + 1] = part
  end

  if #parts ~= CRON_FIELD_COUNT then
    Siku.print.throw(('Invalid cron expression \'%s\': expected %d fields, got %d'):format(expression, CRON_FIELD_COUNT, #parts))
  end

  return {
    minute = parseField(parts[1], 'minute'),
    hour = parseField(parts[2], 'hour'),
    day = parseField(parts[3], 'day'),
    month = parseField(parts[4], 'month'),
    weekday = parseField(parts[5], 'weekday'),
  }
end

--- Check if an os.date table matches the parsed cron fields.
---@param fields table The parsed cron fields.
---@param dt table An os.date('*t') table.
---@return boolean matches Whether the date matches.
local function matchesCron(fields, dt)
  local wday <const> = dt.wday == SUNDAY_WDAY and ISO_SUNDAY or dt.wday - 1

  return fields.minute(dt.min, dt)
    and fields.hour(dt.hour, dt)
    and fields.day(dt.day, dt)
    and fields.month(dt.month, dt)
    and fields.weekday(wday, dt)
end

--- Find the next run time for a parsed cron expression.
---@param fields table The parsed cron fields.
---@return table|nil nextRun An os.date('*t') table or nil if not found within 366 days.
local function findNextRun(fields)
  local t = os.time() + SECONDS_PER_MINUTE

  for _ = 1, SEARCH_HORIZON_MINUTES do
    local dt <const> = os.date('*t', t)
    dt.sec = 0

    if matchesCron(fields, dt) then
      return dt
    end

    t = t + SECONDS_PER_MINUTE
  end

  return nil
end

--- Create a new cron task.
---@param expression string The cron expression (e.g. '*/5 * * * *', '@daily').
---@param job function The function to execute (receives the cron task instance).
---@param debug? boolean Enable debug logging (default: false).
---@return table task The cron task { id, expression, isActive(), run(), stop(), getNextRun(), getLastRun() }.
function cron.create(expression, job, debug)
  local fields <const> = parseExpression(expression)
  local id <const> = nextId
  nextId = nextId + 1

  local entry <const> = {
    active = true,
    lastRun = nil,
    fields = fields,
    job = job,
    debug = debug or false,
  }

  local task <const> = {
    id = id,
    expression = expression,
  }

  --- Check if the task is currently active.
  ---@return boolean active Whether the task is active.
  function task.isActive()
    return entry.active
  end

  --- Activate the task.
  function task.run()
    entry.active = true

    if entry.debug then
      Siku.print.info(('Cron task %d started'):format(id))
    end
  end

  --- Deactivate the task.
  function task.stop()
    entry.active = false

    if entry.debug then
      Siku.print.info(('Cron task %d stopped'):format(id))
    end
  end

  --- Get the next run time.
  ---@return table|nil nextRun An os.date table or nil.
  function task.getNextRun()
    return findNextRun(entry.fields)
  end

  --- Get the last run time.
  ---@return number|nil lastRun The os.time timestamp of the last run or nil.
  function task.getLastRun()
    return entry.lastRun
  end

  entries[id] = { entry = entry, task = task }

  if entry.debug then
    local nextRun <const> = findNextRun(fields)
    local nextStr <const> = nextRun and os.date('%Y-%m-%d %H:%M', os.time(nextRun)) or 'none'
    Siku.print.info(('Cron task %d created: \'%s\' — next: %s'):format(id, expression, nextStr))
  end

  return task
end

--- Remove a cron task by ID.
---@param id number The task ID.
---@return boolean removed Whether the task was found and removed.
function cron.remove(id)
  local data <const> = entries[id]

  if not data then
    return false
  end

  data.entry.active = false
  entries[id] = nil

  return true
end

--- Run every due task for the current minute.
---@param now number The current os.time timestamp.
local function runDueTasks(now)
  local dt <const> = os.date('*t', now)

  for id, data in pairs(entries) do
    local entry <const> = data.entry
    local recentlyRan <const> = entry.lastRun and now - entry.lastRun < RERUN_GUARD_SECONDS

    if entry.active and not recentlyRan and matchesCron(entry.fields, dt) then
      entry.lastRun = now

      if entry.debug then
        Siku.print.debug(('Cron task %d executing'):format(id))
      end

      entry.job(data.task)
    end
  end
end

CreateThread(function()
  while true do
    Wait(TICK_INTERVAL)

    local now <const> = os.time()
    local minuteStamp <const> = now // SECONDS_PER_MINUTE

    if minuteStamp ~= lastTickMinute then
      lastTickMinute = minuteStamp
      runDueTasks(now)
    end
  end
end)

return cron
