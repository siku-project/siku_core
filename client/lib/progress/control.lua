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

--- Show a controlled progress bar on this client, driven from code through
--- Siku.SetProgressValue, Siku.SetProgressHeld and Siku.PulseProgress.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ControlledProgressBar(data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ControlledProgressBar expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(buildPayload(data, 'bar'), onFinish)
end

--- Show a controlled progress circle on this client, driven from code through
--- Siku.SetProgressValue, Siku.SetProgressHeld and Siku.PulseProgress.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ControlledProgressCircle(data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ControlledProgressCircle expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(buildPayload(data, 'circle'), onFinish)
end

--- Set the value of the active controlled progress ('direct' behavior).
---@param value number The gauge value to apply, between 0 and 1.
---@return boolean applied Whether the value was forwarded.
function Siku.SetProgressValue(value)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:SetValue(value)
end

--- Set the held state of the active controlled progress ('hold' behavior).
---@param held boolean Whether the gauge is currently held.
---@return boolean applied Whether the state was forwarded.
function Siku.SetProgressHeld(held)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:SetHeld(held)
end

--- Send one pulse to the active controlled progress ('pulse' behavior).
---@return boolean pulsed Whether the pulse was forwarded.
function Siku.PulseProgress()
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Pulse()
end
