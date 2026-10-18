local TRACE_ID_LENGTH <const> = 32
local SPAN_ID_LENGTH <const> = 16
local NAME_MAX <const> = 256
local KINDS <const> = { internal = true, server = true, client = true }

local settings <const> = internal.settings
local clock <const> = internal.clock
local clamp <const> = internal.clamp

local log <const> = {}
local contexts <const> = setmetatable({}, { __mode = 'k' })

local function randomHex(length)
  local parts <const> = {}

  for i = 1, length // 8 do
    parts[i] = ('%08x'):format(math.random(0, 0xFFFFFFFF))
  end

  return table.concat(parts)
end

local function current()
  return contexts[coroutine.running()]
end

local function sampled()
  local span <const> = current()

  if span and span.trace.sampled then
    return span
  end

  return nil
end

local function traceOf(parent, remote, rate)
  if remote and type(remote.trace) == 'string' and #remote.trace == TRACE_ID_LENGTH then
    return { id = remote.trace, sampled = remote.sampled ~= false, count = 0 }
  end

  if parent then
    return parent.trace
  end

  return { id = randomHex(TRACE_ID_LENGTH), sampled = math.random() < (rate or settings.sampleRate), count = 0 }
end

local function start(name, kind, attributes, remote, rate)
  local parent <const> = current()
  local trace <const> = traceOf(parent, remote, rate)

  trace.count = trace.count + 1

  local span <const> = {
    trace = trace,
    id = randomHex(SPAN_ID_LENGTH),
    parent = remote and remote.span or (parent and parent.id) or nil,
    name = clamp(tostring(name), NAME_MAX),
    kind = KINDS[kind] and kind or 'internal',
    startedAt = clock.now(),
    startedUs = clock.micros(),
    attrs = internal.sanitizeAttributes(attributes),
    open = true,
    previous = parent,
    emit = trace.sampled and trace.count <= settings.maxSpans,
  }

  contexts[coroutine.running()] = span

  return span
end

local function finish(span, ok, err)
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

  local duration <const> = math.max(clock.micros() - span.startedUs, 0)
  local startUs <const> = span.startedAt * 1000

  internal.push({
    k = 'span',
    trace = span.trace.id,
    span = span.id,
    parent = span.parent,
    name = span.name,
    kind = span.kind,
    start = startUs,
    ['end'] = startUs + duration,
    status = ok == false and 'error' or 'ok',
    err = ok == false and clamp(tostring(err), settings.message) or nil,
    res = Siku.name,
    attrs = span.attrs,
  })
end

local function traceback(err)
  local span <const> = current()

  if span and span.emit then
    span.attrs = span.attrs or {}
    span.attrs['exception.stacktrace'] = clamp(debug.traceback('', 2), settings.stack)
  end

  return err
end

local function run(span, fn, ...)
  local results <const> = table.pack(xpcall(fn, traceback, ...))

  finish(span, results[1], results[2])

  if not results[1] then
    error(results[2], 0)
  end

  return table.unpack(results, 2, results.n)
end

local function inherit(fn)
  local span <const> = current()

  if not span then
    return fn
  end

  return function(...)
    contexts[coroutine.running()] = span
    return fn(...)
  end
end

function log.span(name, fn, options, ...)
  if not Siku.isCallable(fn) then
    error('Siku.log.span needs a function', 2)
  end

  if not settings.tracing then
    return fn(...)
  end

  local opts <const> = type(options) == 'table' and options or {}
  local span <const> = start(name, opts.kind or 'internal', opts.attributes, opts.remote, opts.auto and settings.autoSampleRate or nil)

  return run(span, fn, ...)
end

function log.context()
  local span <const> = sampled()

  if not span then
    return nil
  end

  return { trace = span.trace.id, span = span.id, sampled = true }
end

function log.setAttribute(key, value)
  local span <const> = current()

  if not span or type(key) ~= 'string' then
    return false
  end

  span.attrs = span.attrs or {}

  local attributes <const> = internal.sanitizeAttributes({ [key] = value })

  if attributes then
    span.attrs[key] = attributes[key]
  end

  return true
end

if settings.tracing then
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

internal.trace = {
  start = start,
  finish = finish,
  current = current,
  sampled = sampled,
}

return log
