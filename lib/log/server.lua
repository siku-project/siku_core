local CORE <const> = 'siku_core'
local INGEST_EXPORT <const> = 'logIngest'
local PENDING_MAX <const> = 50
local CALIBRATION_MAX_MS <const> = 1500
local SQL_SPAN <const> = 'db.query'
local SQL_STATEMENT_MAX <const> = 512
local SQL_METHODS <const> = { 'query', 'single', 'scalar', 'insert', 'update', 'prepare', 'rawExecute', 'transaction' }

local settings <const> = internal.settings
local clock <const> = internal.clock
local trace <const> = internal.trace
local isCore <const> = Siku.name == CORE

local epochMs = os.time() * 1000
local baseTimer = GetGameTimer()
local pending = {}
local instrumented = false

clock.now = function()
  return epochMs + (GetGameTimer() - baseTimer)
end

if type(os.microtime) == 'function' then
  clock.micros = function()
    return math.floor(os.microtime())
  end
end

local function calibrate()
  local started <const> = GetGameTimer()
  local second <const> = os.time()

  while os.time() == second do
    if GetGameTimer() - started > CALIBRATION_MAX_MS then
      return
    end

    Wait(0)
  end

  epochMs = os.time() * 1000
  baseTimer = GetGameTimer()
end

local function deliverCore(batch)
  local service <const> = _SikuInternal and _SikuInternal.log

  if not service or not service.ingest then
    if #pending < PENDING_MAX then
      pending[#pending + 1] = batch
    end

    return
  end

  if #pending > 0 then
    local waiting <const> = pending

    pending = {}

    for i = 1, #waiting do
      service.ingest(waiting[i], CORE, 'server')
    end
  end

  service.ingest(batch, CORE, 'server')
end

local function deliverExport(batch)
  pcall(function()
    exports[CORE][INGEST_EXPORT](batch)
  end)
end

local function statement(query)
  if type(query) ~= 'string' then
    return nil
  end

  return internal.clamp(query, SQL_STATEMENT_MAX)
end

local function startQuery(query)
  return trace.start(SQL_SPAN, 'client', { ['db.system'] = 'mysql', ['db.statement'] = statement(query) })
end

local function finishCall(span, results)
  trace.finish(span, results[1], results[2])

  if not results[1] then
    error(results[2], 0)
  end

  return table.unpack(results, 2, results.n)
end

local function wrapAwait(original)
  return function(query, ...)
    if not trace.current() then
      return original(query, ...)
    end

    local span <const> = startQuery(query)

    return finishCall(span, table.pack(pcall(original, query, ...)))
  end
end

local function wrapCall(original)
  return function(query, parameters, callback, ...)
    if not trace.current() then
      return original(query, parameters, callback, ...)
    end

    local span <const> = startQuery(query)

    if Siku.isCallable(callback) then
      return original(query, parameters, function(...)
        trace.finish(span, true)
        return callback(...)
      end, ...)
    end

    if Siku.isCallable(parameters) then
      return original(query, function(...)
        trace.finish(span, true)
        return parameters(...)
      end, callback, ...)
    end

    return finishCall(span, table.pack(pcall(original, query, parameters, callback, ...)))
  end
end

local function instrumentSql()
  if instrumented or type(MySQL) ~= 'table' then
    return
  end

  instrumented = true

  for i = 1, #SQL_METHODS do
    local name <const> = SQL_METHODS[i]
    local method <const> = MySQL[name]

    if type(method) == 'table' and Siku.isCallable(method.await) then
      local call <const> = wrapCall(function(...)
        return method(...)
      end)

      MySQL[name] = setmetatable({ await = wrapAwait(method.await) }, {
        __call = function(_, ...)
          return call(...)
        end,
        __index = method,
      })
    elseif Siku.isCallable(method) then
      MySQL[name] = wrapCall(method)
    end
  end
end

Citizen.CreateThreadNow(calibrate)

if settings.tracing and settings.sql then
  instrumentSql()

  if not instrumented then
    SetTimeout(0, instrumentSql)
  end
end

internal.startDelivery(isCore and deliverCore or deliverExport, settings.flushMs)

return {}
