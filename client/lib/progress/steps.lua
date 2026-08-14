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

--- Start a stepped progress on this client, validated step by step through
--- Siku.CompleteProgressStep and Siku.SetProgressSteps.
---@param data table The progress payload; steps (1..10) is required.
---@param onFinish? fun(result: string) Invoked once with 'done', 'cancelled' or 'failed'.
---@return boolean started Whether the progress was accepted.
function Siku.SteppedProgress(data, onFinish)
  if not isReady() then
    return false
  end

  if type(data) ~= 'table' or type(data.steps) ~= 'number' then
    Siku.print.error('SteppedProgress expected a table payload with a numeric steps field')
    return false
  end

  return exports[PROGRESS_RESOURCE]:Start(data, onFinish)
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
