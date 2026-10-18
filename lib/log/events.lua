local DEFAULT_EVENT <const> = 'log'
local EVENT_PATTERN <const> = '^[%l%d_]+[%l%d_%.]*$'
local EVENT_MAX <const> = 96
local OUTCOME_MAX <const> = 32
local FILE_MAX <const> = 256
local MAX_STATES <const> = 2000
local MAX_RECENT <const> = 1000
local STATE_ENTER <const> = '.started'
local STATE_EXIT <const> = '.ended'
local STATE_PREFIX <const> = '^[^:]+'

local LEVELS <const> = internal.LEVELS
local settings <const> = internal.settings
local clock <const> = internal.clock
local categories <const> = internal.categories
local clamp <const> = internal.clamp
local sanitize <const> = internal.sanitize
local sanitizeEntities <const> = internal.sanitizeEntities

local log <const> = {}
local states <const> = {}
local stateCount = 0
local recent = {}
local recentCount = 0

local function build(name, category, level, options)
  local now <const> = clock.now()
  local record <const> = {
    k = 'log',
    id = internal.newId(now),
    t = now,
    cat = category,
    lvl = level,
    ev = name,
    res = Siku.name,
    org = internal.origin,
  }

  if options then
    if options.message ~= nil then
      record.msg = clamp(tostring(options.message), settings.message)
    end

    if type(options.outcome) == 'string' and options.outcome ~= '' then
      record.out = clamp(options.outcome:lower(), OUTCOME_MAX)
    end

    if options.data ~= nil then
      local data <const> = sanitize(options.data, 0)

      record.data = type(data) == 'table' and data or { value = data }
    end

    if options.entities ~= nil then
      record.ents = sanitizeEntities(options.entities)
    end

    if type(options.stack) == 'string' then
      record.stack = clamp(options.stack, settings.stack)
    end

    if type(options.source) == 'number' then
      record.src = options.source
    end

    if type(options.file) == 'string' then
      record.loc = { file = clamp(options.file, FILE_MAX), line = tonumber(options.line) }
    end
  end

  local span <const> = internal.trace.sampled()

  if span then
    record.trace = span.trace.id
    record.span = span.id
  end

  return record
end

local function duplicate(name, options)
  local window <const> = tonumber(options.dedupe)

  if not window or window <= 0 then
    return false, nil
  end

  local key <const> = name .. '|' .. tostring(options.key or '')
  local now <const> = clock.now()
  local entry = recent[key]

  if entry and now - entry.at < window then
    entry.count = entry.count + 1
    return true, nil
  end

  local suppressed <const> = entry and entry.count or 0

  if not entry then
    if recentCount >= MAX_RECENT then
      recent = {}
      recentCount = 0
    end

    recentCount = recentCount + 1
    entry = {}
    recent[key] = entry
  end

  entry.at = now
  entry.count = 0

  return false, suppressed > 0 and suppressed or nil
end

local function emit(name, options, category)
  if not settings.enabled then
    return false
  end

  if type(name) ~= 'string' or #name > EVENT_MAX or not name:match(EVENT_PATTERN) then
    return false
  end

  if options ~= nil and type(options) ~= 'table' then
    options = { message = options }
  end

  local level = LEVELS.info

  if options and options.level then
    level = LEVELS[options.level] or level
  end

  if options and options.dedupe then
    local repeated <const>, suppressed <const> = duplicate(name, options)

    if repeated then
      return false
    end

    if suppressed then
      options.data = type(options.data) == 'table' and options.data or {}
      options.data.suppressed = suppressed
    end
  end

  return internal.push(build(name, category, level, options))
end

local function leveled(level)
  local number <const> = LEVELS[level]

  return function(message, data, options)
    local opts = options

    if type(opts) ~= 'table' then
      opts = {}
    end

    opts.message = message
    opts.level = level

    if data ~= nil then
      opts.data = data
    end

    return emit(opts.event or DEFAULT_EVENT, opts, 'script'), number
  end
end

local function stateCategory(options)
  if options.category == 'audit' and categories.audit then
    return 'audit'
  end

  return 'script'
end

local function stateData(options, value)
  local data <const> = type(options.data) == 'table' and options.data or {}

  data.value = value

  return data
end

local function transition(name, options, data)
  return emit(name, {
    level = options.level,
    message = options.message,
    entities = options.entities,
    data = data,
  }, stateCategory(options))
end

log.trace = leveled('trace')
log.debug = leveled('debug')
log.info = leveled('info')
log.warn = leveled('warn')
log.error = leveled('error')
log.fatal = leveled('fatal')

function log.emit(name, options)
  return emit(name, options, 'script')
end

function log.audit(name, options)
  if categories.audit then
    return emit(name, options, 'audit')
  end

  local opts <const> = type(options) == 'table' and options or {}

  opts.data = type(opts.data) == 'table' and opts.data or {}
  opts.data.declaredAudit = true

  return emit(name, opts, 'script')
end

function log.system(name, options)
  return emit(name, options, categories.system and 'system' or 'script')
end

function log.state(key, active, options)
  if not settings.enabled or type(key) ~= 'string' then
    return false
  end

  options = type(options) == 'table' and options or {}

  local now <const> = clock.now()
  local entry = states[key]
  local value <const> = tonumber(options.value)

  if active then
    if entry then
      entry.lastActive = now

      if value and (not entry.max or value > entry.max) then
        entry.max = value
      end

      return false
    end

    if stateCount >= MAX_STATES then
      return false
    end

    stateCount = stateCount + 1
    states[key] = { since = now, lastActive = now, max = value }

    return transition(options.enter or (key:match(STATE_PREFIX) .. STATE_ENTER), options, stateData(options, value))
  end

  if not entry then
    return false
  end

  local hold <const> = tonumber(options.holdMs) or 0

  if hold > 0 and now - entry.lastActive < hold then
    return false
  end

  states[key] = nil
  stateCount = stateCount - 1

  local data <const> = stateData(options, value)

  data.durationMs = now - entry.since
  data.max = entry.max

  return transition(options.exit or (key:match(STATE_PREFIX) .. STATE_EXIT), options, data)
end

function log.stateClear(key)
  if not states[key] then
    return false
  end

  states[key] = nil
  stateCount = stateCount - 1

  return true
end

function log.stats()
  local queued <const>, dropped <const> = internal.queueStats()

  return { queued = queued, dropped = dropped, states = stateCount }
end

return log
