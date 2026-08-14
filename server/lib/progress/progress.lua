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

--- Start a timed progress on a player. It replaces any active progress,
--- which is settled as cancelled.
---@param source number The player's server id.
---@param data table The progress payload (shape, label, icon, labelPosition, duration, direction, mode, color, showPercentage, showTime, background, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.Progress(source, data, onFinish)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(source, data, onFinish)
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
