local DEFAULT_TIMEOUT <const> = 1000

--- Wait until a condition returns a non-nil value. Throws when the wait times out.
---@param condition function Called every frame; returns a value to stop waiting, or nil to keep waiting.
---@param message? string The error message raised when the wait times out.
---@param timeout? number|false Maximum time in ms to wait (default 1000). Pass false to wait forever.
---@return any value The first non-nil value the condition returned.
function Siku.WaitFor(condition, message, timeout)
  local value = condition()
  if value ~= nil then
    return value
  end

  local limit
  if timeout == false then
    limit = false
  elseif type(timeout) == 'number' then
    limit = timeout
  else
    limit = DEFAULT_TIMEOUT
  end

  local start <const> = limit and GetGameTimer() or 0

  while value == nil do
    Wait(0)

    if limit then
      local elapsed <const> = GetGameTimer() - start
      if elapsed > limit then
        Siku.print.throw(('%s (waited %dms)'):format(message or 'Siku.WaitFor timed out', elapsed))
      end
    end

    value = condition()
  end

  return value
end
