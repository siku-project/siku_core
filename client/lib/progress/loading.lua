local PROGRESS_RESOURCE <const> = 'siku_progress'

--- Check that the progress resource is started before forwarding a call.
---@return boolean ready Whether the progress resource is available.
local function isReady()
  if GetResourceState(PROGRESS_RESOURCE) == 'started' then
    return true
  end

  Siku.print.warn(("'%s' is not started, the loading call was ignored"):format(PROGRESS_RESOURCE))

  return false
end

--- Start a loading on this client. It never ends on its own — close it
--- through Siku.StopProgress (success), Siku.CancelProgress or Siku.ClearProgress.
---@param data table The loading payload (shape, label, icon, labelPosition, duration, direction, color, showTime, background, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done' or 'cancelled'.
---@return boolean started Whether the loading was accepted.
function Siku.Loading(data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('Loading expected a table payload, got %s'):format(type(data)))
    return false
  end

  local payload = {}
  for key, value in pairs(data) do
    payload[key] = value
  end
  payload.indeterminate = true

  return exports[PROGRESS_RESOURCE]:Start(payload, onFinish)
end
