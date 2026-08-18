local intervals = {}

--- Create a recurring interval that calls a function repeatedly at a fixed delay.
--- Can also be used to update the interval of an existing timer by passing its ID as first argument.
---@param ms number|function The delay in milliseconds, or an existing interval ID to update.
---@param cb function|number The callback function, or the new delay when updating.
---@param ... any Additional arguments passed to the callback on each tick.
---@return number id The interval ID used to clear or update it later.
function Siku.SetInterval(ms, cb, ...)
  if type(ms) == 'number' and intervals[ms] then
    if type(cb) ~= 'number' then
      Siku.print.throw(('SetInterval update expects a number as second argument, got %s'):format(type(cb)))
    end
    intervals[ms] = cb
    return ms
  end

  if type(ms) ~= 'number' then
    Siku.print.throw(('SetInterval expects a number as first argument, got %s'):format(type(ms)))
  end

  if not _SikuInternal.IsCallable(cb) then
    Siku.print.throw(('SetInterval expects a function as second argument, got %s'):format(type(cb)))
  end

  local args <const> = { ... }
  local hasArgs <const> = #args > 0
  local id

  Citizen.CreateThreadNow(function(ref)
    id = ref
    intervals[id] = ms

    repeat
      local current <const> = intervals[id]
      if not current or current < 0 then break end
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
---@param id number The interval ID returned by SetInterval.
function Siku.ClearInterval(id)
  if type(id) ~= 'number' then
    Siku.print.throw(('ClearInterval expects a number, got %s'):format(type(id)))
  end

  if not intervals[id] then return end

  intervals[id] = -1
end

--- Check if an interval is currently active.
---@param id number The interval ID.
---@return boolean active Whether the interval is running.
function Siku.IsIntervalActive(id)
  return intervals[id] ~= nil and intervals[id] >= 0
end
