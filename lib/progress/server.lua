local PROGRESS_RESOURCE <const> = internal.resource
local SHAPES <const> = internal.shapes
local FAMILIES <const> = internal.families
local PAYLOAD_ERROR <const> = 'progress.%s expected a table payload, got %s'
local STEPS_PAYLOAD_ERROR <const> = 'progress.%s expected a table payload with a numeric steps field'

local isStarted <const> = internal.isStarted
local isReady <const> = internal.isReady
local buildPayload <const> = internal.buildPayload

--- Validate a caller payload for one family, reporting what is wrong.
---@param name string The public function name, used in the error message.
---@param family table The family descriptor.
---@param data any The caller payload.
---@return boolean valid Whether the payload can be forwarded.
local function hasValidPayload(name, family, data)
  if type(data) == 'table' and (not family.steps or type(data.steps) == 'number') then
    return true
  end

  if family.steps then
    Siku.print.error(STEPS_PAYLOAD_ERROR:format(name))
  else
    Siku.print.error(PAYLOAD_ERROR:format(name, type(data)))
  end

  return false
end

--- Start a progress of one family on a player, once the resource and the payload are checked.
---@param name string The public function name, used in error messages.
---@param family table The family descriptor.
---@param shape string The forced shape.
---@param source number The player's server id.
---@param data table The caller payload.
---@param onFinish? fun(result: string) Invoked once with the final result.
---@return boolean started Whether the progress was accepted.
local function start(name, family, shape, source, data, onFinish)
  if not isReady(family) then
    return false
  end

  if not hasValidPayload(name, family, data) then
    return false
  end

  local progress <const> = exports[PROGRESS_RESOURCE]

  return progress:Start(source, buildPayload(data, family, shape), onFinish)
end

--- Forward one call to the progress resource, once it is checked as started.
---@param family table The family descriptor named in the warning when the resource is missing.
---@param exportName string The progress export to call.
---@param ... any The arguments forwarded to the export, the player's server id first.
---@return boolean forwarded Whether the call was forwarded.
local function forward(family, exportName, ...)
  if not isReady(family) then
    return false
  end

  local progress <const> = exports[PROGRESS_RESOURCE]

  return progress[exportName](progress, ...)
end

--- Show a timed progress bar on a player. It replaces any active progress,
--- which is settled as cancelled.
---@param source number The player's server id.
---@param data table The progress payload (label, icon, duration, direction, mode, color, showPercentage, showTime, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function bar(source, data, onFinish)
  return start('bar', FAMILIES.timed, SHAPES.BAR, source, data, onFinish)
end

--- Show a timed progress circle on a player. It replaces any active
--- progress, which is settled as cancelled.
---@param source number The player's server id.
---@param data table The progress payload (label, icon, labelPosition, duration, direction, mode, color, showPercentage, showTime, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function circle(source, data, onFinish)
  return start('circle', FAMILIES.timed, SHAPES.CIRCLE, source, data, onFinish)
end

--- End the active progress of a player in success — the gauge snaps to full.
---@param source number The player's server id.
---@return boolean stopped Whether the stop was forwarded.
local function stop(source)
  return forward(FAMILIES.timed, 'Stop', source)
end

--- End the active progress of a player as cancelled.
---@param source number The player's server id.
---@return boolean cancelled Whether the cancel was forwarded.
local function cancel(source)
  return forward(FAMILIES.timed, 'Cancel', source)
end

--- End the active progress of a player in failure. No effect on a loading.
---@param source number The player's server id.
---@return boolean failed Whether the fail was forwarded.
local function fail(source)
  return forward(FAMILIES.timed, 'Fail', source)
end

--- Pause the active progress of a player. No effect on a loading.
---@param source number The player's server id.
---@param autoResumeMs? number Automatic resume delay in milliseconds.
---@return boolean paused Whether the pause was forwarded.
local function pause(source, autoResumeMs)
  return forward(FAMILIES.timed, 'Pause', source, autoResumeMs)
end

--- Resume the active paused progress of a player.
---@param source number The player's server id.
---@return boolean resumed Whether the resume was forwarded.
local function resume(source)
  return forward(FAMILIES.timed, 'Resume', source)
end

--- Clear the active progress of a player instantly.
---@param source number The player's server id.
---@return boolean cleared Whether the clear was forwarded.
local function clear(source)
  return forward(FAMILIES.timed, 'Clear', source)
end

--- Check whether a server-initiated progress is pending for a player.
---@param source number The player's server id.
---@return boolean active Whether a server-initiated progress is pending.
local function isActive(source)
  if not isStarted() then
    return false
  end

  local progress <const> = exports[PROGRESS_RESOURCE]

  return progress:IsActive(source)
end

--- Show a controlled progress bar on a player, driven from code through
--- Siku.progress.setValue, Siku.progress.setHeld and Siku.progress.pulse.
---@param source number The player's server id.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function controlledBar(source, data, onFinish)
  return start('controlledBar', FAMILIES.controlled, SHAPES.BAR, source, data, onFinish)
end

--- Show a controlled progress circle on a player, driven from code through
--- Siku.progress.setValue, Siku.progress.setHeld and Siku.progress.pulse.
---@param source number The player's server id.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function controlledCircle(source, data, onFinish)
  return start('controlledCircle', FAMILIES.controlled, SHAPES.CIRCLE, source, data, onFinish)
end

--- Set the value of the active controlled progress of a player ('direct' behavior).
---@param source number The player's server id.
---@param value number The gauge value to apply, between 0 and 1.
---@return boolean applied Whether the value was forwarded.
local function setValue(source, value)
  return forward(FAMILIES.controlled, 'SetValue', source, value)
end

--- Set the held state of the active controlled progress of a player ('hold' behavior).
---@param source number The player's server id.
---@param held boolean Whether the gauge is currently held.
---@return boolean applied Whether the state was forwarded.
local function setHeld(source, held)
  return forward(FAMILIES.controlled, 'SetHeld', source, held)
end

--- Send one pulse to the active controlled progress of a player ('pulse' behavior).
---@param source number The player's server id.
---@return boolean pulsed Whether the pulse was forwarded.
local function pulse(source)
  return forward(FAMILIES.controlled, 'Pulse', source)
end

--- Show a loading bar on a player. It never ends on its own — close it
--- through Siku.progress.stop (success), Siku.progress.cancel or Siku.progress.clear.
---@param source number The player's server id.
---@param data table The loading payload (label, icon, duration, direction, color, showTime, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done' or 'cancelled'.
---@return boolean started Whether the loading was accepted.
local function loadingBar(source, data, onFinish)
  return start('loadingBar', FAMILIES.loading, SHAPES.BAR, source, data, onFinish)
end

--- Show a loading circle on a player. It never ends on its own — close it
--- through Siku.progress.stop (success), Siku.progress.cancel or Siku.progress.clear.
---@param source number The player's server id.
---@param data table The loading payload (label, icon, labelPosition, duration, direction, color, showTime, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done' or 'cancelled'.
---@return boolean started Whether the loading was accepted.
local function loadingCircle(source, data, onFinish)
  return start('loadingCircle', FAMILIES.loading, SHAPES.CIRCLE, source, data, onFinish)
end

--- Show a stepped progress bar on a player, validated step by step through
--- Siku.progress.completeStep and Siku.progress.setSteps.
---@param source number The player's server id.
---@param data table The progress payload; steps (1..10) is required (label, icon, color, showPercentage, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function steps(source, data, onFinish)
  return start('steps', FAMILIES.stepped, SHAPES.BAR, source, data, onFinish)
end

--- Validate the next step of the active stepped progress of a player.
---@param source number The player's server id.
---@return boolean completed Whether the step was forwarded.
local function completeStep(source)
  return forward(FAMILIES.stepped, 'CompleteStep', source)
end

--- Set the number of validated steps of the active stepped progress of a player.
---@param source number The player's server id.
---@param count number The number of validated steps to apply.
---@return boolean applied Whether the count was forwarded.
local function setSteps(source, count)
  return forward(FAMILIES.stepped, 'SetSteps', source, count)
end

return {
  bar = bar,
  circle = circle,
  stop = stop,
  cancel = cancel,
  fail = fail,
  pause = pause,
  resume = resume,
  clear = clear,
  isActive = isActive,
  controlledBar = controlledBar,
  controlledCircle = controlledCircle,
  setValue = setValue,
  setHeld = setHeld,
  pulse = pulse,
  loadingBar = loadingBar,
  loadingCircle = loadingCircle,
  steps = steps,
  completeStep = completeStep,
  setSteps = setSteps,
}
