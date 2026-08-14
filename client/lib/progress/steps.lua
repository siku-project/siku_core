local PROGRESS_RESOURCE <const> = 'siku_progress'

--- Check that the progress resource is started before forwarding a call.
---@return boolean ready Whether the progress resource is available.
local function isReady()
  if GetResourceState(PROGRESS_RESOURCE) == 'started' then
    return true
  end

  Siku.print.warn(("'%s' is not started, the stepped progress call was ignored"):format(PROGRESS_RESOURCE))

  return false
end

--- Build a stepped payload from the caller's data, forcing the bar shape
--- and stripping the other family fields.
---@param data table The caller payload.
---@return table payload The stepped payload.
local function buildPayload(data)
  local payload = {}
  for key, value in pairs(data) do
    payload[key] = value
  end

  payload.shape = 'bar'
  payload.indeterminate = nil
  payload.control = nil
  payload.steps = data.steps

  return payload
end

--- Show a stepped progress bar on this client, validated step by step
--- through Siku.CompleteProgressStep and Siku.SetProgressSteps.
---@param data table The progress payload; steps (1..10) is required (label, icon, color, showPercentage, background, position).
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.StepProgress(data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' or type(data.steps) ~= 'number' then
    Siku.print.error('StepProgress expected a table payload with a numeric steps field')
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(buildPayload(data), onFinish)
end

--- Validate the next step of the active stepped progress.
---@return boolean completed Whether the step was forwarded.
function Siku.CompleteProgressStep()
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:CompleteStep()
end

--- Set the number of validated steps of the active stepped progress.
---@param count number The number of validated steps to apply.
---@return boolean applied Whether the count was forwarded.
function Siku.SetProgressSteps(count)
  if not isReady() then
    return false
  end

  return exports[PROGRESS_RESOURCE]:SetSteps(count)
end
