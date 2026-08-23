local INPUT_GROUP <const> = 0

local callers = {}
local controls = {}
local suppressed = {}
local tickActive = false

--- Resolve the caller name from an explicit argument, or this resource.
---@param caller? string An explicit caller name.
---@return string caller The resolved caller name.
local function resolveCaller(caller)
  return caller or Siku.name
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
          DisableControlAction(INPUT_GROUP, key, true)
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

--- Disable one or more control keys for this resource.
---@param ... number The control key(s) to disable.
local function disable(...)
  local caller <const> = resolveCaller()
  local keys <const> = { ... }

  for i = 1, #keys do
    linkControl(caller, keys[i])
  end

  ensureTick()
end

--- Re-enable one or more control keys this resource disabled. A key stays
--- disabled while another caller still holds it.
---@param ... number The control key(s) to re-enable.
local function enable(...)
  local caller <const> = resolveCaller()
  local keys <const> = { ... }

  for i = 1, #keys do
    unlinkControl(caller, keys[i])
  end
end

--- Clear every disabled control for a specific caller, or for this resource.
---@param caller? string The caller name to clear. Defaults to this resource.
local function clear(caller)
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
local function clearAll()
  callers = {}
  controls = {}
  suppressed = {}
end

--- Temporarily suppress one or more disabled controls. They stay registered but stop being disabled.
---@param ... number The control key(s) to suppress.
local function suppress(...)
  local keys <const> = { ... }

  for i = 1, #keys do
    if controls[keys[i]] then
      suppressed[keys[i]] = true
    end
  end
end

--- Remove suppression on one or more disabled controls. They resume being disabled.
---@param ... number The control key(s) to unsuppress.
local function unsuppress(...)
  local keys <const> = { ... }

  for i = 1, #keys do
    suppressed[keys[i]] = nil
  end
end

--- Check whether a control key is currently disabled.
---@param key number The control key to check.
---@return boolean disabled Whether the control is disabled.
local function isDisabled(key)
  return controls[key] ~= nil
end

--- Check whether a disabled control key is currently suppressed.
---@param key number The control key to check.
---@return boolean suppressed Whether the control is suppressed.
local function isSuppressed(key)
  return suppressed[key] == true
end

--- Get every caller name that has disabled a specific control key.
---@param key number The control key to check.
---@return table callers A list of caller names.
local function getCallers(key)
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
local function getAll()
  local result <const> = {}

  for key in pairs(controls) do
    result[#result + 1] = key
  end

  return result
end

return {
  disable = disable,
  enable = enable,
  clear = clear,
  clearAll = clearAll,
  suppress = suppress,
  unsuppress = unsuppress,
  isDisabled = isDisabled,
  isSuppressed = isSuppressed,
  getCallers = getCallers,
  getAll = getAll,
}
