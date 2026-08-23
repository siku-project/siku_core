local PROGRESS_RESOURCE <const> = 'siku_progress'
local STARTED <const> = 'started'

local SHAPES <const> = {
  BAR = 'bar',
  CIRCLE = 'circle',
}

local FAMILIES <const> = {
  timed = { label = 'progress', indeterminate = false, control = false, steps = false },
  controlled = { label = 'controlled progress', indeterminate = false, control = true, steps = false },
  loading = { label = 'loading', indeterminate = true, control = false, steps = false },
  stepped = { label = 'stepped progress', indeterminate = false, control = false, steps = true },
}

--- Check whether the progress resource is started, silently.
---@return boolean started Whether the progress resource is available.
local function isStarted()
  return GetResourceState(PROGRESS_RESOURCE) == STARTED
end

--- Check that the progress resource is started before forwarding a call,
--- warning with the family name when it is not.
---@param family table The family descriptor of the call being forwarded.
---@return boolean ready Whether the progress resource is available.
local function isReady(family)
  if isStarted() then
    return true
  end

  Siku.print.warn(("'%s' is not started, the %s call was ignored"):format(PROGRESS_RESOURCE, family.label))

  return false
end

--- Build a payload from the caller's data, forcing the shape and keeping
--- only the fields of the requested family.
---@param data table The caller payload.
---@param family table The family descriptor.
---@param shape string The forced shape: 'bar' or 'circle'.
---@return table payload The family payload.
local function buildPayload(data, family, shape)
  local payload <const> = {}

  for key, value in pairs(data) do
    payload[key] = value
  end

  payload.shape = shape
  payload.indeterminate = family.indeterminate or nil
  payload.control = family.control and (type(data.control) == 'table' and data.control or {}) or nil
  payload.steps = family.steps and data.steps or nil

  return payload
end

internal.resource = PROGRESS_RESOURCE
internal.shapes = SHAPES
internal.families = FAMILIES
internal.isStarted = isStarted
internal.isReady = isReady
internal.buildPayload = buildPayload

return {}
