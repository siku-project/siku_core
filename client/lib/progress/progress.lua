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

--- Show a timed progress bar on this client. It replaces any active
--- progress, which is settled as cancelled.
---@param data table The progress payload (label, icon, duration, direction, mode, color, showPercentage, showTime, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ProgressBar(data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ProgressBar expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(buildPayload(data, 'bar'), onFinish)
end

--- Show a timed progress circle on this client. It replaces any active
--- progress, which is settled as cancelled.
---@param data table The progress payload (label, icon, labelPosition, duration, direction, mode, color, showPercentage, showTime, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.ProgressCircle(data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' then
    Siku.print.error(('ProgressCircle expected a table payload, got %s'):format(type(data)))
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(buildPayload(data, 'circle'), onFinish)
end

--- End the active progress in success — the gauge snaps to full.
---@return boolean stopped Whether an active progress was stopped.
function Siku.StopProgress()
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Stop()
end

--- End the active progress as cancelled.
---@return boolean cancelled Whether an active progress was cancelled.
function Siku.CancelProgress()
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Cancel()
end

--- End the active progress in failure. No effect on a loading.
---@return boolean failed Whether an active progress was failed.
function Siku.FailProgress()
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Fail()
end

--- Pause the active progress. No effect on a loading.
---@param autoResumeMs? number Automatic resume delay in milliseconds.
---@return boolean paused Whether the pause was forwarded.
function Siku.PauseProgress(autoResumeMs)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Pause(autoResumeMs)
end

--- Resume the active paused progress.
---@return boolean resumed Whether the resume was forwarded.
function Siku.ResumeProgress()
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Resume()
end

--- Clear the active progress instantly, settled as cancelled.
---@return boolean cleared Whether an active progress was cleared.
function Siku.ClearProgress()
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Clear()
end

--- Check whether a progress is currently active on this client.
---@return boolean active Whether a progress is active.
function Siku.IsProgressActive()
  if GetResourceState(PROGRESS_RESOURCE) ~= 'started' then
    return false
  end

  return exports[PROGRESS_RESOURCE]:IsActive()
end
