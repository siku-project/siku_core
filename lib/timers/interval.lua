local STOPPED <const> = -1

local intervals = {}

--- Run one interval tick, keeping the loop alive when the callback throws.
---@param id number The interval ID, named in the error report.
---@param cb function The callback.
---@param args table The extra arguments captured at creation.
---@param hasArgs boolean Whether extra arguments were given.
local function runTick(id, cb, args, hasArgs)
  local ok, err

  if hasArgs then
    ok, err = pcall(cb, table.unpack(args))
  else
    ok, err = pcall(cb)
  end

  if not ok then
    Siku.print.error(('Interval %d callback failed: %s'):format(id, tostring(err)))
  end
end

--- Create a recurring interval that calls a function repeatedly at a fixed delay.
--- A callback that throws is reported and the interval keeps ticking.
---@param ms number The delay in milliseconds.
---@param cb function The callback function.
---@param ... any Additional arguments passed to the callback on each tick.
---@return number id The interval ID used to clear or retime it later.
local function setInterval(ms, cb, ...)
  if type(ms) ~= 'number' then
    Siku.print.throw(('setInterval expects a number as first argument, got %s'):format(type(ms)))
  end

  if not Siku.isCallable(cb) then
    Siku.print.throw(('setInterval expects a function as second argument, got %s'):format(type(cb)))
  end

  local args <const> = { ... }
  local hasArgs <const> = #args > 0
  local id

  Citizen.CreateThreadNow(function(ref)
    id = ref
    intervals[id] = ms

    repeat
      local current <const> = intervals[id]

      if not current or current < 0 then
        break
      end

      Wait(current)

      if intervals[id] and intervals[id] >= 0 then
        runTick(id, cb, args, hasArgs)
      end
    until not intervals[id]

    intervals[id] = nil
  end)

  return id
end

--- Change the delay of a running interval, applied from its next tick.
---@param id number The interval ID returned by setInterval.
---@param ms number The new delay in milliseconds.
---@return boolean applied Whether the interval existed and was retimed.
local function updateInterval(id, ms)
  if type(ms) ~= 'number' or ms < 0 then
    Siku.print.throw(('updateInterval expects a positive number as second argument, got %s'):format(tostring(ms)))
  end

  if not intervals[id] then
    return false
  end

  intervals[id] = ms

  return true
end

--- Stop a recurring interval.
---@param id number The interval ID returned by setInterval.
local function clearInterval(id)
  if type(id) ~= 'number' then
    Siku.print.throw(('clearInterval expects a number, got %s'):format(type(id)))
  end

  if not intervals[id] then
    return
  end

  intervals[id] = STOPPED
end

--- Check if an interval is currently active.
---@param id number The interval ID.
---@return boolean active Whether the interval is running.
local function isIntervalActive(id)
  return intervals[id] ~= nil and intervals[id] >= 0
end

return {
  setInterval = setInterval,
  updateInterval = updateInterval,
  clearInterval = clearInterval,
  isIntervalActive = isIntervalActive,
}
