local PROGRESS_RESOURCE <const> = 'siku_progress'

--- Check that the progress resource is started before forwarding a call.
---@return boolean ready Whether the progress resource is available.
local function isReady()
  if GetResourceState(PROGRESS_RESOURCE) == 'started' then
    return true
  end

  Siku.print.warn(("'%s' is not started, the progress call was ignored"):format(PROGRESS_RESOURCE))

  return false
end

--- Build a timed payload from the caller's data, forcing the shape and
--- stripping the other family fields.
---@param data table The caller payload.
---@param shape string The forced shape: 'bar' or 'circle'.
---@return table payload The timed payload.
local function buildPayload(data, shape)
  local payload = {}
  for key, value in pairs(data) do
    payload[key] = value
  end

  payload.shape = shape
  payload.indeterminate = nil
  payload.control = nil
  payload.steps = nil

  return payload
end

--- Show a timed progress bar on a player. It replaces any active progress,
--- which is settled as cancelled.
---@param source number The player's server id.
---@param data table The progress payload (label, icon, duration, direction, mode, color, showPercentage, showTime, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ProgressBar(source, data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ProgressBar expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(source, buildPayload(data, 'bar'), onFinish)
end

--- Show a timed progress circle on a player. It replaces any active
--- progress, which is settled as cancelled.
---@param source number The player's server id.
---@param data table The progress payload (label, icon, labelPosition, duration, direction, mode, color, showPercentage, showTime, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ProgressCircle(source, data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ProgressCircle expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(source, buildPayload(data, 'circle'), onFinish)
end

--- End the active progress of a player in success — the gauge snaps to full.
---@param source number The player's server id.
---@return boolean stopped Whether the stop was forwarded.
function Siku.StopProgress(source)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Stop(source)
end

--- End the active progress of a player as cancelled.
---@param source number The player's server id.
---@return boolean cancelled Whether the cancel was forwarded.
function Siku.CancelProgress(source)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Cancel(source)
end

--- End the active progress of a player in failure. No effect on a loading.
---@param source number The player's server id.
---@return boolean failed Whether the fail was forwarded.
function Siku.FailProgress(source)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Fail(source)
end

--- Pause the active progress of a player. No effect on a loading.
---@param source number The player's server id.
---@param autoResumeMs? number Automatic resume delay in milliseconds.
---@return boolean paused Whether the pause was forwarded.
function Siku.PauseProgress(source, autoResumeMs)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Pause(source, autoResumeMs)
end

--- Resume the active paused progress of a player.
---@param source number The player's server id.
---@return boolean resumed Whether the resume was forwarded.
function Siku.ResumeProgress(source)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Resume(source)
end

--- Clear the active progress of a player instantly.
---@param source number The player's server id.
---@return boolean cleared Whether the clear was forwarded.
function Siku.ClearProgress(source)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Clear(source)
end

--- Check whether a server-initiated progress is pending for a player.
---@param source number The player's server id.
---@return boolean active Whether a server-initiated progress is pending.
function Siku.IsProgressActive(source)
  if GetResourceState(PROGRESS_RESOURCE) ~= 'started' then
    return false
  end

  return exports[PROGRESS_RESOURCE]:IsActive(source)
end
