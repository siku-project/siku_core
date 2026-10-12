local CLIENT_EVENT <const> = internal.CLIENT_EVENT
local CALLBACKS <const> = internal.CALLBACKS
local STATES <const> = internal.STATES

local holdings = {}
local listeners <const> = {}
local synced = false

local function apply(list)
  holdings = type(list) == 'table' and list or {}
  synced = true

  for index = 1, #listeners do
    local ok <const>, err <const> = pcall(listeners[index], holdings)

    if not ok then
      Siku.print.error(('Licenses listener failed: %s'):format(tostring(err)))
    end
  end
end

local function getMine()
  return holdings
end

local function get(licenseName)
  return internal.findHolding(holdings, licenseName)
end

local function has(licenseName)
  return get(licenseName) ~= nil
end

local function isValid(licenseName)
  local holding <const> = get(licenseName)

  return holding ~= nil and holding.state == STATES.VALID
end

local function getPoints(licenseName)
  local holding <const> = get(licenseName)

  return holding and holding.points or nil
end

local function isSynced()
  return synced
end

local function onChanged(handler)
  if not Siku.isCallable(handler) then
    return false
  end

  listeners[#listeners + 1] = handler

  return true
end

local function getDefinition(licenseName)
  local ok <const>, definition <const> = Siku.callback.triggerServer(CALLBACKS.DEFINITION, licenseName)

  return ok and definition or nil
end

local function getAll(group)
  local ok <const>, definitions <const> = Siku.callback.triggerServer(CALLBACKS.DEFINITIONS, group)

  return ok and definitions or nil
end

RegisterNetEvent(CLIENT_EVENT, apply)

CreateThread(function()
  local ok <const>, list <const> = Siku.callback.triggerServer(CALLBACKS.MY_LICENSES)

  if ok and not synced then
    apply(list)
  end
end)

return {
  getMine = getMine,
  get = get,
  has = has,
  isValid = isValid,
  getPoints = getPoints,
  isSynced = isSynced,
  onChanged = onChanged,
  getDefinition = getDefinition,
  getAll = getAll,
}
