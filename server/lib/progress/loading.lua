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

--- Build a loading payload from the caller's data, forcing the shape and
--- stripping the other family fields.
---@param data table The caller payload.
---@param shape string The forced shape: 'bar' or 'circle'.
---@return table payload The loading payload.
local function buildPayload(data, shape)
  local payload = {}
  for key, value in pairs(data) do
    payload[key] = value
  end

  payload.shape = shape
  payload.indeterminate = true
  payload.control = nil
  payload.steps = nil

  return payload
end

--- Show a loading bar on a player. It never ends on its own — close it
--- through Siku.StopProgress (success), Siku.CancelProgress or Siku.ClearProgress.
---@param source number The player's server id.
---@param data table The loading payload (label, icon, duration, direction, color, showTime, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done' or 'cancelled'.
---@return boolean started Whether the loading was accepted.
function Siku.LoadingBar(source, data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('LoadingBar expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(source, buildPayload(data, 'bar'), onFinish)
end

--- Show a loading circle on a player. It never ends on its own — close it
--- through Siku.StopProgress (success), Siku.CancelProgress or Siku.ClearProgress.
---@param source number The player's server id.
---@param data table The loading payload (label, icon, labelPosition, duration, direction, color, showTime, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done' or 'cancelled'.
---@return boolean started Whether the loading was accepted.
function Siku.LoadingCircle(source, data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('LoadingCircle expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(source, buildPayload(data, 'circle'), onFinish)
end
