local CORE <const> = 'siku_core'
local INGEST_EXPORT <const> = 'logIngest'
local CALIBRATION_WAIT <const> = 0
local CALIBRATION_MAX_MS <const> = 1500
local MICRO <const> = 1000
local SQL_SPAN <const> = 'db.query'
local SQL_STATEMENT_MAX <const> = 512
local SQL_METHODS <const> = { 'query', 'single', 'scalar', 'insert', 'update', 'prepare', 'rawExecute', 'transaction' }

local config <const> = Siku.config.log
local tracing <const> = config.tracing or {}
local isCore <const> = Siku.name == CORE

local epochMs = os.time() * 1000
local baseTimer = GetGameTimer()
local calibrated = false
local microtime <const> = type(os.microtime) == 'function' and os.microtime or nil

internal.allowAudit = true
internal.allowSystem = isCore
internal.setOrigin('server')

internal.now = function()
  return epochMs + (GetGameTimer() - baseTimer)
end

if microtime then
  internal.monotonicUs = function()
    return math.floor(microtime())
  end
else
  internal.monotonicUs = function()
    return GetGameTimer() * MICRO
  end
end

local function calibrate()
  local started <const> = GetGameTimer()
  local second <const> = os.time()

  while os.time() == second do
    if GetGameTimer() - started > CALIBRATION_MAX_MS then
      return
    end

    Wait(CALIBRATION_WAIT)
  end

  epochMs = os.time() * 1000
  baseTimer = GetGameTimer()
  calibrated = true
end

Citizen.CreateThreadNow(calibrate)

local pendingCore = {}

local function deliverCore(batch)
  local service <const> = _SikuInternal and _SikuInternal.log

  if not service then
    if #pendingCore < 50 then
      pendingCore[#pendingCore + 1] = batch
    end

    return
  end

  if #pendingCore > 0 then
    local waiting <const> = pendingCore
    pendingCore = {}

    for i = 1, #waiting do
      service.ingest(waiting[i], CORE, 'server')
    end
  end

  service.ingest(batch, CORE, 'server')
end

local function deliverExport(batch)
  local ok <const> = pcall(function()
    exports[CORE][INGEST_EXPORT](batch)
  end)

  return ok
end

internal.send = isCore and deliverCore or deliverExport

local wrapped = false

local function statement(query)
  if type(query) ~= 'string' then
    return nil
  end

  return internal.clamp(query, SQL_STATEMENT_MAX)
end

local function wrapAwait(original)
  return function(query, ...)
    if not internal.currentSpan() then
      return original(query, ...)
    end

    local span <const> = internal.startSpan(SQL_SPAN, 'client', { ['db.system'] = 'mysql', ['db.statement'] = statement(query) })
    local results <const> = table.pack(pcall(original, query, ...))

    internal.endSpan(span, results[1], results[2])

    if not results[1] then
      error(results[2], 0)
    end

    return table.unpack(results, 2, results.n)
  end
end

local function wrapCall(original)
  return function(query, parameters, callback, ...)
    if not internal.currentSpan() then
      return original(query, parameters, callback, ...)
    end

    local span <const> = internal.startSpan(SQL_SPAN, 'client', { ['db.system'] = 'mysql', ['db.statement'] = statement(query) })

    if Siku.isCallable(callback) then
      return original(query, parameters, function(...)
        internal.endSpan(span, true)
        return callback(...)
      end, ...)
    end

    if Siku.isCallable(parameters) then
      return original(query, function(...)
        internal.endSpan(span, true)
        return parameters(...)
      end, callback, ...)
    end

    local results <const> = table.pack(pcall(original, query, parameters, callback, ...))

    internal.endSpan(span, results[1], results[2])

    if not results[1] then
      error(results[2], 0)
    end

    return table.unpack(results, 2, results.n)
  end
end

local function wrapMySQL()
  if wrapped or tracing.sql == false or type(MySQL) ~= 'table' then
    return
  end

  wrapped = true

  for i = 1, #SQL_METHODS do
    local name <const> = SQL_METHODS[i]
    local method <const> = MySQL[name]

    if type(method) == 'table' and Siku.isCallable(method.await) then
      local call <const> = wrapCall(function(...)
        return method(...)
      end)
      local proxy <const> = setmetatable({ await = wrapAwait(method.await) }, {
        __call = function(_, ...)
          return call(...)
        end,
        __index = method,
      })

      MySQL[name] = proxy
    elseif Siku.isCallable(method) then
      MySQL[name] = wrapCall(method)
    end
  end
end

internal.instrumentSql = wrapMySQL

wrapMySQL()

if not wrapped then
  SetTimeout(0, wrapMySQL)
end

internal.flushLoop()

return {
  isCalibrated = function()
    return calibrated
  end,
}
