local PROGRESS_RESOURCE <const> = 'siku_progress'

--- Check that the progress resource is started before forwarding a call.
---@return boolean ready Whether the progress resource is available.
local function isReady()
  if GetResourceState(PROGRESS_RESOURCE) == 'started' then
    return true
  end

  Siku.print.warn(("'%s' is not started, the controlled progress call was ignored"):format(PROGRESS_RESOURCE))

  return false
end

--- Build a controlled payload from the caller's data, forcing the shape,
--- guaranteeing the control table and stripping the other family fields.
---@param data table The caller payload.
---@param shape string The forced shape: 'bar' or 'circle'.
---@return table payload The controlled payload.
local function buildPayload(data, shape)
  local payload = {}
  for key, value in pairs(data) do
    payload[key] = value
  end

  payload.shape = shape
  payload.indeterminate = nil
  payload.control = type(data.control) == 'table' and data.control or {}
  payload.steps = nil

  return payload
end

--- Show a controlled progress bar on a player, driven from code through
--- Siku.SetProgressValue, Siku.SetProgressHeld and Siku.PulseProgress.
---@param source number The player's server id.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ControlledProgressBar(source, data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ControlledProgressBar expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(source, buildPayload(data, 'bar'), onFinish)
end

--- Show a controlled progress circle on a player, driven from code through
--- Siku.SetProgressValue, Siku.SetProgressHeld and Siku.PulseProgress.
---@param source number The player's server id.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ControlledProgressCircle(source, data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ControlledProgressCircle expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(source, buildPayload(data, 'circle'), onFinish)
end

--- Set the value of the active controlled progress of a player ('direct' behavior).
---@param source number The player's server id.
---@param value number The gauge value to apply, between 0 and 1.
---@return boolean applied Whether the value was forwarded.
function Siku.SetProgressValue(source, value)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:SetValue(source, value)
end

--- Set the held state of the active controlled progress of a player ('hold' behavior).
---@param source number The player's server id.
---@param held boolean Whether the gauge is currently held.
---@return boolean applied Whether the state was forwarded.
function Siku.SetProgressHeld(source, held)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:SetHeld(source, held)
end

--- Send one pulse to the active controlled progress of a player ('pulse' behavior).
---@param source number The player's server id.
---@return boolean pulsed Whether the pulse was forwarded.
function Siku.PulseProgress(source)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Pulse(source)
end
