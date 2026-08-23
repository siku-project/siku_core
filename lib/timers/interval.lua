local STOPPED <const> = -1

local intervals = {}

--- Update the delay of an existing interval.
---@param id number The interval ID.
---@param ms any The new delay in milliseconds.
---@return number id The interval ID.
local function updateInterval(id, ms)
  if type(ms) ~= 'number' then
    Siku.print.throw(('setInterval update expects a number as second argument, got %s'):format(type(ms)))
  end

  intervals[id] = ms

  return id
end

--- Create a recurring interval that calls a function repeatedly at a fixed delay.
--- Can also be used to update the interval of an existing timer by passing its ID as first argument.
---@param ms number|function The delay in milliseconds, or an existing interval ID to update.
---@param cb function|number The callback function, or the new delay when updating.
---@param ... any Additional arguments passed to the callback on each tick.
---@return number id The interval ID used to clear or update it later.
local function setInterval(ms, cb, ...)
  if type(ms) == 'number' and intervals[ms] then
    return updateInterval(ms, cb)
  end

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
        if hasArgs then
          cb(table.unpack(args))
        else
          cb()
        end
      end
    until not intervals[id]

    intervals[id] = nil
  end)

  return id
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
  clearInterval = clearInterval,
  isIntervalActive = isIntervalActive,
}
