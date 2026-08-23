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

--- Start a progress of one family on this client, once the resource and the payload are checked.
---@param name string The public function name, used in error messages.
---@param family table The family descriptor.
---@param shape string The forced shape.
---@param data table The caller payload.
---@param onFinish? fun(result: string) Invoked once with the final result.
---@return boolean started Whether the progress was accepted.
local function start(name, family, shape, data, onFinish)
  if not isReady(family) then
    return false
  end

  if not hasValidPayload(name, family, data) then
    return false
  end

  local progress <const> = exports[PROGRESS_RESOURCE]

  return progress:Start(buildPayload(data, family, shape), onFinish)
end

--- Forward one call to the progress resource, once it is checked as started.
---@param family table The family descriptor named in the warning when the resource is missing.
---@param exportName string The progress export to call.
---@param ... any The arguments forwarded to the export.
---@return boolean forwarded Whether the call was forwarded.
local function forward(family, exportName, ...)
  if not isReady(family) then
    return false
  end

  local progress <const> = exports[PROGRESS_RESOURCE]

  return progress[exportName](progress, ...)
end

--- Show a timed progress bar on this client. It replaces any active
--- progress, which is settled as cancelled.
---@param data table The progress payload (label, icon, duration, direction, mode, color, showPercentage, showTime, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function bar(data, onFinish)
  return start('bar', FAMILIES.timed, SHAPES.BAR, data, onFinish)
end

--- Show a timed progress circle on this client. It replaces any active
--- progress, which is settled as cancelled.
---@param data table The progress payload (label, icon, labelPosition, duration, direction, mode, color, showPercentage, showTime, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function circle(data, onFinish)
  return start('circle', FAMILIES.timed, SHAPES.CIRCLE, data, onFinish)
end

--- End the active progress in success — the gauge snaps to full.
---@return boolean stopped Whether an active progress was stopped.
local function stop()
  return forward(FAMILIES.timed, 'Stop')
end

--- End the active progress as cancelled.
---@return boolean cancelled Whether an active progress was cancelled.
local function cancel()
  return forward(FAMILIES.timed, 'Cancel')
end

--- End the active progress in failure. No effect on a loading.
---@return boolean failed Whether an active progress was failed.
local function fail()
  return forward(FAMILIES.timed, 'Fail')
end

--- Pause the active progress. No effect on a loading.
---@param autoResumeMs? number Automatic resume delay in milliseconds.
---@return boolean paused Whether the pause was forwarded.
local function pause(autoResumeMs)
  return forward(FAMILIES.timed, 'Pause', autoResumeMs)
end

--- Resume the active paused progress.
---@return boolean resumed Whether the resume was forwarded.
local function resume()
  return forward(FAMILIES.timed, 'Resume')
end

--- Clear the active progress instantly, settled as cancelled.
---@return boolean cleared Whether an active progress was cleared.
local function clear()
  return forward(FAMILIES.timed, 'Clear')
end

--- Check whether a progress is currently active on this client.
---@return boolean active Whether a progress is active.
local function isActive()
  if not isStarted() then
    return false
  end

  local progress <const> = exports[PROGRESS_RESOURCE]

  return progress:IsActive()
end

--- Show a controlled progress bar on this client, driven from code through
--- Siku.progress.setValue, Siku.progress.setHeld and Siku.progress.pulse.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function controlledBar(data, onFinish)
  return start('controlledBar', FAMILIES.controlled, SHAPES.BAR, data, onFinish)
end

--- Show a controlled progress circle on this client, driven from code through
--- Siku.progress.setValue, Siku.progress.setHeld and Siku.progress.pulse.
---@param data table The progress payload; control ({ mode, riseRate, fallRate, pulseGain, startAt, completeAtFull, failAtEmpty }) defaults to an empty table.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function controlledCircle(data, onFinish)
  return start('controlledCircle', FAMILIES.controlled, SHAPES.CIRCLE, data, onFinish)
end

--- Set the value of the active controlled progress ('direct' behavior).
---@param value number The gauge value to apply, between 0 and 1.
---@return boolean applied Whether the value was forwarded.
local function setValue(value)
  return forward(FAMILIES.controlled, 'SetValue', value)
end

--- Set the held state of the active controlled progress ('hold' behavior).
---@param held boolean Whether the gauge is currently held.
---@return boolean applied Whether the state was forwarded.
local function setHeld(held)
  return forward(FAMILIES.controlled, 'SetHeld', held)
end

--- Send one pulse to the active controlled progress ('pulse' behavior).
---@return boolean pulsed Whether the pulse was forwarded.
local function pulse()
  return forward(FAMILIES.controlled, 'Pulse')
end

--- Show a loading bar on this client. It never ends on its own — close it
--- through Siku.progress.stop (success), Siku.progress.cancel or Siku.progress.clear.
---@param data table The loading payload (label, icon, duration, direction, color, showTime, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done' or 'cancelled'.
---@return boolean started Whether the loading was accepted.
local function loadingBar(data, onFinish)
  return start('loadingBar', FAMILIES.loading, SHAPES.BAR, data, onFinish)
end

--- Show a loading circle on this client. It never ends on its own — close it
--- through Siku.progress.stop (success), Siku.progress.cancel or Siku.progress.clear.
---@param data table The loading payload (label, icon, labelPosition, duration, direction, color, showTime, size, position).
---@param onFinish? fun(result: string) Invoked once with 'done' or 'cancelled'.
---@return boolean started Whether the loading was accepted.
local function loadingCircle(data, onFinish)
  return start('loadingCircle', FAMILIES.loading, SHAPES.CIRCLE, data, onFinish)
end

--- Show a stepped progress bar on this client, validated step by step
--- through Siku.progress.completeStep and Siku.progress.setSteps.
---@param data table The progress payload; steps (1..10) is required (label, icon, color, showPercentage, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
local function steps(data, onFinish)
  return start('steps', FAMILIES.stepped, SHAPES.BAR, data, onFinish)
end

--- Validate the next step of the active stepped progress.
---@return boolean completed Whether the step was forwarded.
local function completeStep()
  return forward(FAMILIES.stepped, 'CompleteStep')
end

--- Set the number of validated steps of the active stepped progress.
---@param count number The number of validated steps to apply.
---@return boolean applied Whether the count was forwarded.
local function setSteps(count)
  return forward(FAMILIES.stepped, 'SetSteps', count)
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
