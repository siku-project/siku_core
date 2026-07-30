local callers = {}
local controls = {}
local suppressed = {}
local tickActive = false

--- Resolve the caller name from an explicit argument, the invoking resource, or the current resource.
---@param caller? string An explicit caller name.
---@return string caller The resolved caller name.
local function resolveCaller(caller)
  if caller then
    return caller
  end

  local invoker <const> = GetInvokingResource()

  if invoker then
    return invoker
  end

  return Siku.name
end

--- Start the internal tick loop if not already running. Stops automatically when no controls remain.
local function ensureTick()
  if tickActive then
    return
  end

  tickActive = true

  CreateThread(function()
    while next(controls) do
      for key in pairs(controls) do
        if not suppressed[key] then
          DisableControlAction(0, key, true)
        end
      end

      Wait(0)
    end

    tickActive = false
  end)
end

--- Link a control key to a caller, keeping both tracking tables in sync.
---@param caller string The caller name.
---@param key number The control key to link.
local function linkControl(caller, key)
  if not callers[caller] then
    callers[caller] = {}
  end

  callers[caller][key] = true

  if not controls[key] then
    controls[key] = {}
  end

  controls[key][caller] = true
end

--- Unlink a control key from a caller, cleaning up both tracking tables.
---@param caller string The caller name.
---@param key number The control key to unlink.
local function unlinkControl(caller, key)
  if callers[caller] then
    callers[caller][key] = nil

    if not next(callers[caller]) then
      callers[caller] = nil
    end
  end

  if controls[key] then
    controls[key][caller] = nil

    if not next(controls[key]) then
      controls[key] = nil
      suppressed[key] = nil
    end
  end
end

--- Disable one or more control keys for the calling resource.
---@param ... number The control key(s) to disable.
function Siku.AddDisabledControl(...)
  local caller <const> = resolveCaller()
  local keys <const> = { ... }

  for i = 1, #keys do
    linkControl(caller, keys[i])
  end

  ensureTick()
end

--- Re-enable one or more previously disabled control keys for the calling resource.
---@param ... number The control key(s) to re-enable.
function Siku.RemoveDisabledControl(...)
  local caller <const> = resolveCaller()
  local keys <const> = { ... }

  for i = 1, #keys do
    unlinkControl(caller, keys[i])
  end
end

--- Clear every disabled control for a specific caller, or for the calling resource.
---@param caller? string The caller name to clear. Defaults to the calling resource.
function Siku.ClearDisabledControl(caller)
  local resolved <const> = resolveCaller(caller)
  local callerKeys <const> = callers[resolved]

  if not callerKeys then
    return
  end

  for key in pairs(callerKeys) do
    if controls[key] then
      controls[key][resolved] = nil

      if not next(controls[key]) then
        controls[key] = nil
        suppressed[key] = nil
      end
    end
  end

  callers[resolved] = nil
end

--- Clear every disabled control from every caller.
function Siku.ClearAllDisabledControls()
  callers = {}
  controls = {}
  suppressed = {}
end

--- Temporarily suppress one or more disabled controls. They stay registered but stop being disabled.
---@param ... number The control key(s) to suppress.
function Siku.SuppressDisabledControl(...)
  local keys <const> = { ... }

  for i = 1, #keys do
    if controls[keys[i]] then
      suppressed[keys[i]] = true
    end
  end
end

--- Remove suppression on one or more disabled controls. They resume being disabled.
---@param ... number The control key(s) to unsuppress.
function Siku.UnsuppressDisabledControl(...)
  local keys <const> = { ... }

  for i = 1, #keys do
    suppressed[keys[i]] = nil
  end
end

--- Check whether a control key is currently disabled.
---@param key number The control key to check.
---@return boolean disabled Whether the control is disabled.
function Siku.HasDisabledControl(key)
  return controls[key] ~= nil
end

--- Check whether a disabled control key is currently suppressed.
---@param key number The control key to check.
---@return boolean suppressed Whether the control is suppressed.
function Siku.IsDisabledControlSuppressed(key)
  return suppressed[key] == true
end

--- Get every caller name that has disabled a specific control key.
---@param key number The control key to check.
---@return table callers A list of caller names.
function Siku.GetDisabledControlCallers(key)
  local result <const> = {}

  if controls[key] then
    for caller in pairs(controls[key]) do
      result[#result + 1] = caller
    end
  end

  return result
end

--- Get every control key that is currently disabled.
---@return table keys A list of disabled control keys.
function Siku.GetAllDisabledControls()
  local result <const> = {}

  for key in pairs(controls) do
    result[#result + 1] = key
  end

  return result
end

AddEventHandler('onResourceStop', function(resource)
  Siku.ClearDisabledControl(resource)
end)
