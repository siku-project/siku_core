local CLIENT_EVENT <const> = internal.CLIENT_EVENT
local CALLBACKS <const> = internal.CALLBACKS

local accounts = {}
local listeners <const> = {}
local synced = false

--- Replaces the local copy and tells whoever asked to know.
---@param list table The views the server sent.
---@return nil
local function apply(list)
  accounts = type(list) == 'table' and list or {}
  synced = true

  for index = 1, #listeners do
    local ok <const>, err <const> = pcall(listeners[index], accounts)

    if not ok then
      Siku.print.error(('Accounts listener failed: %s'):format(tostring(err)))
    end
  end
end

--- Every account the local character owns or holds a grant on, as the
--- server last sent them.
---@return table accounts The views, each with `owned` and `grants`.
local function getMine()
  return accounts
end

--- One account of the local copy.
---@param accountId number The account id.
---@return table? account The view, or nil.
local function get(accountId)
  return internal.findAccount(accounts, accountId)
end

--- The balance of an account of the local copy.
---@param accountId number The account id.
---@return number? balance The balance, or nil when the account is not in the copy.
local function getBalance(accountId)
  local account <const> = get(accountId)

  return account and account.balance or nil
end

--- The accounts the local character owns, out of the local copy.
---@return table accounts The views.
local function getOwned()
  local owned <const> = {}

  for index = 1, #accounts do
    if accounts[index].owned then
      owned[#owned + 1] = accounts[index]
    end
  end

  return owned
end

--- Whether the server has sent the accounts yet.
---@return boolean synced Whether the local copy is meaningful.
local function isSynced()
  return synced
end

--- Registers a function called with the accounts each time they change.
---@param handler function The listener.
---@return boolean registered Whether it was stored.
local function onChanged(handler)
  if not Siku.isCallable(handler) then
    return false
  end

  listeners[#listeners + 1] = handler

  return true
end

--- Asks the server one account, answered to its owner, a grant holder or a
--- member of the owning job.
---@param accountId number The account id.
---@return table? account The view, nil when refused or unanswered.
local function fetch(accountId)
  local ok <const>, account <const> = Siku.callback.triggerServer(CALLBACKS.ACCOUNT, accountId)

  return ok and account or nil
end

--- Asks the server the accounts of a job, answered to its members.
---@param jobName string The job name.
---@return table? accounts The public accounts, nil when refused or unanswered.
local function getJobAccounts(jobName)
  local ok <const>, list <const> = Siku.callback.triggerServer(CALLBACKS.JOB_ACCOUNTS, jobName)

  return ok and list or nil
end

--- Asks the server the last mutations of an account, answered to whoever
--- may see it.
---@param accountId number The account id.
---@param limit? number How many at most.
---@return table? mutations The journal lines, nil when refused or unanswered.
local function getMutations(accountId, limit)
  local ok <const>, list <const> = Siku.callback.triggerServer(CALLBACKS.MUTATIONS, accountId, limit)

  return ok and list or nil
end

RegisterNetEvent(CLIENT_EVENT, apply)

CreateThread(function()
  local ok <const>, list <const> = Siku.callback.triggerServer(CALLBACKS.MY_ACCOUNTS)

  if ok and not synced then
    apply(list)
  end
end)

return {
  getMine = getMine,
  get = get,
  getBalance = getBalance,
  getOwned = getOwned,
  isSynced = isSynced,
  onChanged = onChanged,
  fetch = fetch,
  getJobAccounts = getJobAccounts,
  getMutations = getMutations,
}
