local internal <const> = _SikuInternal.jobs
local state <const> = internal.state

local EVENT_ALLOWANCE <const> = 'unemploymentAllowance'
local INVENTORY_RESOURCE <const> = 'siku_inventory'
local STARTED <const> = 'started'
local MINIMUM_INTERVAL_MS <const> = 60000

--- TEMPORARY, until the economy exists: hands the allowance over as an
--- inventory item when the inventory is there to take it.
---@param characterId number The character id.
---@param amount number The allowance.
---@return boolean paid Whether the item went in.
local function payWithInventory(characterId, amount)
  local item <const> = JobsConfig.unemployment.allowance.item

  if type(item) ~= 'string' or item == '' or GetResourceState(INVENTORY_RESOURCE) ~= STARTED then
    return false
  end

  local ok <const>, added <const> = pcall(function()
    return exports[INVENTORY_RESOURCE]:AddItem(characterId, item, amount)
  end)

  return ok and type(added) == 'number' and added > 0
end

--- Pays every unemployed character in play, announcing each allowance so
--- the economy can take over the payment when it exists.
---@return nil
local function payAllowances()
  local amount <const> = JobsConfig.unemployment.allowance.amount

  if type(amount) ~= 'number' or amount <= 0 then
    return
  end

  for characterId, sessionId in pairs(state.sessions) do
    if Siku.jobs.isUnemployed(characterId) then
      internal.emit(EVENT_ALLOWANCE, sessionId, characterId, amount)

      if payWithInventory(characterId, amount) then
        Siku.notification.show(sessionId, {
          type = 'info',
          title = T('jobs_allowance_title'),
          description = T('jobs_allowance_received', amount),
        })
      end
    end
  end
end

if JobsConfig.unemployment.allowance.enabled then
  local interval <const> = math.max(tonumber(JobsConfig.unemployment.allowance.interval) or MINIMUM_INTERVAL_MS, MINIMUM_INTERVAL_MS)

  Siku.timers.setInterval(interval, payAllowances)
end
