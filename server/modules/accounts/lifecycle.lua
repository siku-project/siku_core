local internal <const> = _SikuInternal.accounts

local CALLBACK_MY_ACCOUNTS <const> = 'siku:callback:myAccounts'
local CALLBACK_ACCOUNT <const> = 'siku:callback:account'
local CALLBACK_JOB_ACCOUNTS <const> = 'siku:callback:jobAccounts'
local CALLBACK_ACCOUNT_MUTATIONS <const> = 'siku:callback:accountMutations'
local PERMISSION_ANY <const> = '*'

--- Sends a character entering play what it can see.
---@param sessionId number The player server ID.
---@param characterData table The character row.
---@return nil
local function handleCharacterReady(sessionId, characterData)
  if type(sessionId) ~= 'number' or type(characterData) ~= 'table' or type(characterData.id) ~= 'number' then
    return
  end

  if not internal.waitReady() then
    return
  end

  internal.push(characterData.id)
end

--- The character a session plays, for the callbacks.
---@param sessionId number The player server ID.
---@return number? characterId The character id, or nil between two.
local function characterOf(sessionId)
  return Siku.cache.getCurrentCharacterId(sessionId)
end

--- Whether a character may look at an account: its owner, a grant holder,
--- or any member of the owning job.
---@param entry table The cached account.
---@param characterId number The character id.
---@return boolean allowed Whether the view is answered.
local function maySee(entry, characterId)
  if entry.ownerType == internal.OWNER_CHARACTER then
    return entry.ownerId == characterId or internal.grantsOf(entry.id, characterId) ~= nil
  end

  if internal.grantsOf(entry.id, characterId) then
    return true
  end

  local jobName <const> = internal.jobNameOf(entry.ownerId)

  return jobName ~= nil and Siku.jobs.hasJob(characterId, jobName)
end

Siku.callback.register(CALLBACK_MY_ACCOUNTS, function(sessionId)
  local characterId <const> = characterOf(sessionId)

  if not characterId then
    return {}
  end

  return Siku.accounts.getAccessible(characterId)
end)

Siku.callback.register(CALLBACK_ACCOUNT, function(sessionId, accountId)
  local characterId <const> = characterOf(sessionId)
  local entry <const> = internal.getEntry(accountId)

  if not characterId or not entry or not maySee(entry, characterId) then
    return nil
  end

  return internal.viewFor(entry, characterId)
end)

Siku.callback.register(CALLBACK_JOB_ACCOUNTS, function(sessionId, jobName)
  local characterId <const> = characterOf(sessionId)

  if not characterId or type(jobName) ~= 'string' or not Siku.jobs.hasJob(characterId, jobName) then
    return nil
  end

  return Siku.accounts.getJobAccounts(jobName)
end)

Siku.callback.register(CALLBACK_ACCOUNT_MUTATIONS, function(sessionId, accountId, limit)
  local characterId <const> = characterOf(sessionId)
  local entry <const> = internal.getEntry(accountId)

  if not characterId or not entry then
    return nil
  end

  if not Siku.accounts.canAct(entry.id, characterId, PERMISSION_ANY) and not maySee(entry, characterId) then
    return nil
  end

  return Siku.accounts.getMutations(entry.id, limit)
end)

AddEventHandler('siku:server:createCharacterInstance', handleCharacterReady)
