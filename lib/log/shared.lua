local LOG_EVENT <const> = 'log'
local EVENT_PATTERN <const> = '^[%l%d_]+[%l%d_%.]*$'
local MAX_EVENT <const> = 96
local MAX_OUTCOME <const> = 32
local MAX_QUEUE <const> = 2000
local MAX_STATES <const> = 2000
local MAX_RECENT <const> = 1000
local FLUSH_MIN <const> = 50
local ENTITY_FIELDS <const> = 8
local ENTITY_TYPE <const> = 32
local ENTITY_ID <const> = 64
local ENTITY_ROLE <const> = 32
local ENTITY_LABEL <const> = 128
local DROPPED_EVENT <const> = 'log.dropped'
local DROPPED_EVERY_MS <const> = 60000
local SPAN_KIND <const> = { internal = 'internal', server = 'server', client = 'client' }
local ID_FORMAT <const> = '%012x%08x%08x%04x'

local LEVELS <const> = { trace = 1, debug = 5, info = 9, warn = 13, error = 17, fatal = 21 }
local CATEGORIES <const> = { system = true, script = true, audit = true }

local config <const> = Siku.config.log
local limits <const> = config.limits or {}
local tracing <const> = config.tracing or {}
local enabled <const> = config.enabled ~= false
local tracingEnabled <const> = enabled and tracing.enabled ~= false
local sampleRate <const> = tonumber(tracing.sampleRate) or 1.0
local autoSampleRate <const> = tonumber(tracing.autoSampleRate) or 0.2
local maxSpans <const> = tonumber(tracing.maxSpans) or 200
local maxAttributes <const> = tonumber(tracing.maxAttributes) or 64
local batchSize <const> = math.max(tonumber(config.batchSize) or 100, 1)
local flushMs <const> = math.max(tonumber(config.flushMs) or 200, FLUSH_MIN)

local limitMessage <const> = limits.message or 2048
local limitString <const> = limits.string or 1024
local limitKeys <const> = limits.keys or 32
local limitDepth <const> = limits.depth or 3
local limitList <const> = limits.list or 50
local limitEntities <const> = limits.entities or 16
local limitStack <const> = limits.stack or 16384

local log <const> = {}
local queue = {}
local queued = 0
local dropped = 0
local droppedAt = 0
local flushPending = false
local states <const> = {}
local stateCount = 0
local recent <const> = {}
local recentCount = 0
local contexts <const> = setmetatable({}, { __mode = 'k' })
local origin = 'server'

internal.levels = LEVELS
internal.now = GetGameTimer
internal.monotonicUs = function()
  return GetGameTimer() * 1000
end
internal.send = nil
internal.flushMs = flushMs
internal.enabled = enabled

local function randomHex(length)
  local parts <const> = {}

  for i = 1, length // 8 do
    parts[i] = ('%08x'):format(math.random(0, 0xFFFFFFFF))
  end

  local rest <const> = length % 8

  if rest > 0 then
    parts[#parts + 1] = ('%08x'):format(math.random(0, 0xFFFFFFFF)):sub(1, rest)
  end

  return table.concat(parts)
end

local function newId(now)
  return ID_FORMAT:format(math.max(now, 0) & 0xFFFFFFFFFFFF, math.random(0, 0xFFFFFFFF), math.random(0, 0xFFFFFFFF), math.random(0, 0xFFFF))
end

local function clamp(value, max)
  if #value > max then
    return value:sub(1, max)
  end

  return value
end

local function isSequence(value)
  local n <const> = #value

  if n == 0 then
    return next(value) == nil
  end

  return next(value, n) == nil
end

local sanitize

local function sanitizeList(value, depth)
  local out <const> = {}
  local n <const> = math.min(#value, limitList)

  for i = 1, n do
    out[i] = sanitize(value[i], depth + 1)
  end

  if #value > limitList then
    out[n + 1] = ('… %d more'):format(#value - limitList)
  end

  return out
end

local function sanitizeMap(value, depth)
  local out <const> = {}
  local count = 0

  for key, entry in pairs(value) do
    count = count + 1

    if count > limitKeys then
      out['…'] = 'truncated'
      break
    end

    out[clamp(tostring(key), 128)] = sanitize(entry, depth + 1)
  end

  return out
end

sanitize = function(value, depth)
  local valueType <const> = type(value)

  if valueType == 'string' then
    return clamp(value, limitString)
  end

  if valueType == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then
      return tostring(value)
    end

    return value
  end

  if valueType == 'boolean' or value == nil then
    return value
  end

  if valueType == 'vector3' or valueType == 'vector4' or valueType == 'vector2' then
    return { x = value.x, y = value.y, z = value.z, w = value.w }
  end

  if valueType ~= 'table' then
    return tostring(value)
  end

  if depth >= limitDepth then
    return '[…]'
  end

  local meta <const> = getmetatable(value)

  if meta and meta.__tostring then
    return tostring(value)
  end

  if isSequence(value) then
    return sanitizeList(value, depth)
  end

  return sanitizeMap(value, depth)
end

local function sanitizeEntity(entity)
  if type(entity) ~= 'table' then
    return nil
  end

  local entityType <const> = type(entity.type) == 'string' and clamp(entity.type:lower(), ENTITY_TYPE) or nil

  if not entityType or entityType == '' then
    return nil
  end

  local id = entity.id

  if entity.session ~= nil and id == nil then
    id = entity.session
  end

  if id == nil or (type(id) ~= 'string' and type(id) ~= 'number') then
    return nil
  end

  local out <const> = { type = entityType, id = type(id) == 'number' and id or clamp(id, ENTITY_ID) }
  local count = 0

  if type(entity.role) == 'string' then
    out.role = clamp(entity.role, ENTITY_ROLE)
  end

  if type(entity.label) == 'string' then
    out.label = clamp(entity.label, ENTITY_LABEL)
  end

  for key, value in pairs(entity) do
    if key ~= 'type' and key ~= 'id' and key ~= 'session' and key ~= 'role' and key ~= 'label' then
      count = count + 1

      if count > ENTITY_FIELDS then
        break
      end

      local kind <const> = type(value)

      if kind == 'string' then
        out[clamp(tostring(key), 32)] = clamp(value, limitString)
      elseif kind == 'number' or kind == 'boolean' then
        out[clamp(tostring(key), 32)] = value
      end
    end
  end

  return out
end

local function sanitizeEntities(entities)
  if type(entities) ~= 'table' then
    return nil
  end

  local out <const> = {}

  for i = 1, math.min(#entities, limitEntities) do
    local entity <const> = sanitizeEntity(entities[i])

    if entity then
      out[#out + 1] = entity
    end
  end

  if #out == 0 then
    return nil
  end

  return out
end

local function scheduleFlush()
  if flushPending then
    return
  end

  flushPending = true

  SetTimeout(0, function()
    flushPending = false
    log.flush()
  end)
end

local function push(record)
  if queued >= MAX_QUEUE then
    dropped = dropped + 1
    return false
  end

  queued = queued + 1
  queue[queued] = record

  if queued >= batchSize then
    scheduleFlush()
  end

  return true
end

internal.push = push

local function currentSpan()
  return contexts[coroutine.running()]
end

local function sampledContext()
  local span <const> = currentSpan()

  if span and span.trace.sampled then
    return span
  end

  return nil
end

local function build(name, category, level, options)
  local now <const> = internal.now()
  local record <const> = {
    k = 'log',
    id = newId(now),
    t = now,
    cat = category,
    lvl = level,
    ev = name,
    res = Siku.name,
    org = origin,
  }

  if options then
    local message <const> = options.message

    if type(message) == 'string' then
      record.msg = clamp(message, limitMessage)
    elseif message ~= nil then
      record.msg = clamp(tostring(message), limitMessage)
    end

    local outcome <const> = options.outcome

    if type(outcome) == 'string' and outcome ~= '' then
      record.out = clamp(outcome:lower(), MAX_OUTCOME)
    end

    if options.data ~= nil then
      local data <const> = sanitize(options.data, 0)

      if type(data) == 'table' then
        record.data = data
      else
        record.data = { value = data }
      end
    end

    if options.entities ~= nil then
      record.ents = sanitizeEntities(options.entities)
    end

    if type(options.stack) == 'string' then
      record.stack = clamp(options.stack, limitStack)
    end

    if type(options.source) == 'number' then
      record.src = options.source
    end

    if type(options.file) == 'string' then
      record.loc = { file = clamp(options.file, 256), line = tonumber(options.line) }
    end
  end

  local span <const> = sampledContext()

  if span then
    record.trace = span.trace.id
    record.span = span.id
  end

  return record
end

local function shouldDedupe(name, options)
  local window <const> = tonumber(options.dedupe)

  if not window or window <= 0 then
    return false, nil
  end

  local key <const> = name .. '|' .. tostring(options.key or '')
  local now <const> = internal.now()
  local entry = recent[key]

  if entry and now - entry.at < window then
    entry.count = entry.count + 1
    return true, nil
  end

  local suppressed <const> = entry and entry.count or 0

  if not entry then
    if recentCount >= MAX_RECENT then
      for k in pairs(recent) do
        recent[k] = nil
      end

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
  if not enabled then
    return false
  end

  if type(name) ~= 'string' or #name > MAX_EVENT or not name:match(EVENT_PATTERN) then
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
    local duplicate <const>, suppressed <const> = shouldDedupe(name, options)

    if duplicate then
      return false
    end

    if suppressed then
      options.data = type(options.data) == 'table' and options.data or {}
      options.data.suppressed = suppressed
    end
  end

  return push(build(name, category or 'script', level, options))
end

internal.emit = emit

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

    return emit(opts.event or LOG_EVENT, opts, 'script'), number
  end
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
  if not internal.allowAudit then
    local opts = type(options) == 'table' and options or {}

    opts.data = type(opts.data) == 'table' and opts.data or {}
    opts.data.declaredAudit = true

    return emit(name, opts, 'script')
  end

  return emit(name, options, 'audit')
end

function log.system(name, options)
  if not internal.allowSystem then
    return emit(name, options, 'script')
  end

  return emit(name, options, 'system')
end

function log.state(key, active, options)
  if not enabled or type(key) ~= 'string' then
    return false
  end

  options = type(options) == 'table' and options or {}

  local now <const> = internal.now()
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

    local data <const> = type(options.data) == 'table' and options.data or {}

    data.value = value

    return emit(options.enter or (key:match('^[^:]+') .. '.started'), {
      level = options.level,
      message = options.message,
      entities = options.entities,
      data = data,
    }, options.category == 'audit' and internal.allowAudit and 'audit' or 'script')
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

  local data <const> = type(options.data) == 'table' and options.data or {}

  data.durationMs = now - entry.since
  data.max = entry.max
  data.value = value

  return emit(options.exit or (key:match('^[^:]+') .. '.ended'), {
    level = options.level,
    message = options.message,
    entities = options.entities,
    data = data,
  }, options.category == 'audit' and internal.allowAudit and 'audit' or 'script')
end

function log.stateClear(key)
  if states[key] then
    states[key] = nil
    stateCount = stateCount - 1
    return true
  end

  return false
end

local function sanitizeAttributes(attributes)
  if type(attributes) ~= 'table' then
    return nil
  end

  local out <const> = {}
  local count = 0

  for key, value in pairs(attributes) do
    count = count + 1

    if count > maxAttributes then
      break
    end

    local kind <const> = type(value)

    if kind == 'string' then
      out[clamp(tostring(key), 128)] = clamp(value, limitString)
    elseif kind == 'number' or kind == 'boolean' then
      out[clamp(tostring(key), 128)] = value
    elseif value ~= nil then
      out[clamp(tostring(key), 128)] = clamp(tostring(value), limitString)
    end
  end

  return out
end

local function startSpan(name, kind, attributes, remote, rate)
  local parent <const> = currentSpan()
  local trace

  if remote and type(remote.trace) == 'string' and #remote.trace == 32 then
    trace = { id = remote.trace, sampled = remote.sampled ~= false, count = 0 }
  elseif parent then
    trace = parent.trace
  else
    trace = { id = randomHex(32), sampled = math.random() < (rate or sampleRate), count = 0 }
  end

  trace.count = trace.count + 1

  local span <const> = {
    trace = trace,
    id = randomHex(16),
    parent = remote and remote.span or (parent and parent.id) or nil,
    name = clamp(tostring(name), 256),
    kind = SPAN_KIND[kind] or SPAN_KIND.internal,
    startedAt = internal.now(),
    startedUs = internal.monotonicUs(),
    attrs = sanitizeAttributes(attributes),
    open = true,
    previous = parent,
    emit = trace.sampled and trace.count <= maxSpans,
  }

  contexts[coroutine.running()] = span

  return span
end

local function endSpan(span, ok, err)
  if not span.open then
    return
  end

  span.open = false

  local co <const> = coroutine.running()

  if contexts[co] == span then
    contexts[co] = span.previous
  end

  if not span.emit then
    return
  end

  local duration <const> = math.max(internal.monotonicUs() - span.startedUs, 0)
  local start <const> = span.startedAt * 1000

  push({
    k = 'span',
    trace = span.trace.id,
    span = span.id,
    parent = span.parent,
    name = span.name,
    kind = span.kind,
    start = start,
    ['end'] = start + duration,
    status = ok == false and 'error' or 'ok',
    err = ok == false and clamp(tostring(err), limitMessage) or nil,
    res = Siku.name,
    attrs = span.attrs,
  })
end

internal.startSpan = startSpan
internal.endSpan = endSpan
internal.currentSpan = currentSpan

local function traceback(err)
  local span <const> = currentSpan()

  if span and span.emit then
    span.attrs = span.attrs or {}
    span.attrs['exception.stacktrace'] = clamp(debug.traceback('', 2), limitStack)
  end

  return err
end

local function runSpan(span, fn, ...)
  local results <const> = table.pack(xpcall(fn, traceback, ...))

  endSpan(span, results[1], results[2])

  if not results[1] then
    error(results[2], 0)
  end

  return table.unpack(results, 2, results.n)
end

function log.span(name, fn, options, ...)
  if not Siku.isCallable(fn) then
    error('Siku.log.span needs a function', 2)
  end

  if not tracingEnabled then
    return fn(...)
  end

  local opts <const> = type(options) == 'table' and options or nil
  local span <const> = startSpan(name, opts and opts.kind or 'internal', opts and opts.attributes, opts and opts.remote, opts and opts.auto and autoSampleRate or nil)

  return runSpan(span, fn, ...)
end

function log.context()
  local span <const> = sampledContext()

  if not span then
    return nil
  end

  return { trace = span.trace.id, span = span.id, sampled = true }
end

function log.setAttribute(key, value)
  local span <const> = currentSpan()

  if not span or type(key) ~= 'string' then
    return false
  end

  span.attrs = span.attrs or {}

  local attributes <const> = sanitizeAttributes({ [key] = value })

  if attributes then
    span.attrs[key] = attributes[key]
  end

  return true
end

function log.flush()
  if queued == 0 then
    return 0
  end

  local batch <const> = queue
  local count <const> = queued

  queue = {}
  queued = 0

  local now <const> = internal.now()

  if dropped > 0 and now - droppedAt >= DROPPED_EVERY_MS then
    droppedAt = now
    batch[count + 1] = build(DROPPED_EVENT, 'system', LEVELS.warn, { data = { dropped = dropped } })
    dropped = 0
  end

  if internal.send then
    internal.send(batch)
  else
    dropped = dropped + #batch
  end

  return count
end

function log.stats()
  return { queued = queued, dropped = dropped, states = stateCount }
end

function log.levels()
  return LEVELS
end

function log.now()
  return internal.now()
end

function log.isEnabled()
  return enabled
end

local function inherit(fn)
  local span <const> = currentSpan()

  if not span then
    return fn
  end

  return function(...)
    contexts[coroutine.running()] = span
    return fn(...)
  end
end

internal.inherit = inherit

if tracingEnabled then
  local createThread <const> = Citizen.CreateThread
  local createThreadNow <const> = Citizen.CreateThreadNow
  local setTimeout <const> = Citizen.SetTimeout

  Citizen.CreateThread = function(fn)
    return createThread(inherit(fn))
  end

  Citizen.CreateThreadNow = function(fn, name)
    return createThreadNow(inherit(fn), name)
  end

  Citizen.SetTimeout = function(ms, fn)
    return setTimeout(ms, inherit(fn))
  end

  _G.CreateThread = Citizen.CreateThread
  _G.SetTimeout = Citizen.SetTimeout
end

internal.setOrigin = function(value)
  origin = value
end

internal.categories = CATEGORIES
internal.sanitize = sanitize
internal.sanitizeEntities = sanitizeEntities
internal.clamp = clamp
internal.build = build
internal.flushLoop = function()
  Citizen.CreateThreadNow(function()
    while true do
      Wait(internal.flushMs)
      log.flush()
    end
  end)
end

AddEventHandler('onResourceStop', function(resource)
  if resource == Siku.name then
    log.flush()
  end
end)

return log
