Siku.accounts = {}

local OWNER_CHARACTER <const> = 'character'
local OWNER_JOB <const> = 'job'
local STATE_ACTIVE <const> = 'active'
local STATE_FROZEN <const> = 'frozen'
local STATE_CLOSED <const> = 'closed'
local EVENT_FORMAT <const> = 'siku:accounts:%s'
local CLIENT_EVENT <const> = 'siku:client:accountsUpdated'
local READY_POLL_MS <const> = 100
local READY_TIMEOUT_MS <const> = 30000
local LOCK_POLL_MS <const> = 10

local state <const> = {
  ready = false,
  byId = {},
  byOwner = {
    [OWNER_CHARACTER] = {},
    [OWNER_JOB] = {},
  },
  access = {
    byAccount = {},
    byCharacter = {},
  },
  locks = {},
}

_SikuInternal.accounts = {
  state = state,
  OWNER_CHARACTER = OWNER_CHARACTER,
  OWNER_JOB = OWNER_JOB,
  STATE_ACTIVE = STATE_ACTIVE,
  STATE_FROZEN = STATE_FROZEN,
  STATE_CLOSED = STATE_CLOSED,
  CLIENT_EVENT = CLIENT_EVENT,
}

--- Fires one engine event, prefixed the way every other core event is.
---@param name string The event name after `siku:accounts:`.
---@vararg any The payload.
---@return nil
function _SikuInternal.accounts.emit(name, ...)
  TriggerEvent(EVENT_FORMAT:format(name), ...)
end

--- Blocks the calling thread until the accounts have been read from the
--- database, which happens once at boot.
---@return boolean ready Whether the engine came up in time.
function _SikuInternal.accounts.waitReady()
  if state.ready then
    return true
  end

  local start <const> = GetGameTimer()

  while not state.ready do
    if GetGameTimer() - start > READY_TIMEOUT_MS then
      return false
    end

    Wait(READY_POLL_MS)
  end

  return true
end

--- Whether an owner type is one the engine knows.
---@param ownerType any The candidate.
---@return boolean valid Whether it is a character or a job.
function _SikuInternal.accounts.isValidOwnerType(ownerType)
  return ownerType == OWNER_CHARACTER or ownerType == OWNER_JOB
end

--- Whether a state name is one the engine knows.
---@param name any The candidate.
---@return boolean valid Whether it is active, frozen or closed.
function _SikuInternal.accounts.isValidState(name)
  return name == STATE_ACTIVE or name == STATE_FROZEN or name == STATE_CLOSED
end

--- A whole number out of anything the caller passed, or nil.
---@param value any The candidate.
---@return number? amount The integer, or nil when it is not one.
function _SikuInternal.accounts.toInteger(value)
  if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end

  return math.tointeger(value)
end

--- The account id out of anything the caller passed, or nil.
---@param value any The candidate.
---@return number? accountId The id, or nil when it is not one.
function _SikuInternal.accounts.toAccountId(value)
  local id <const> = _SikuInternal.accounts.toInteger(tonumber(value))

  if not id or id <= 0 then
    return nil
  end

  return id
end

--- A cached account by id.
---@param accountId any The account id.
---@return table? account The cached entry, or nil.
function _SikuInternal.accounts.getEntry(accountId)
  local id <const> = _SikuInternal.accounts.toAccountId(accountId)

  return id and state.byId[id] or nil
end

--- Resolves a job owner: a job id or a job name, to the job id.
---@param value any The id or name.
---@return number? jobId The job id, or nil when the job is unknown.
function _SikuInternal.accounts.resolveJobId(value)
  if type(value) == 'string' then
    local job <const> = _SikuInternal.jobs.getJob(value)

    return job and job.id or nil
  end

  local id <const> = _SikuInternal.accounts.toInteger(value)

  return id and _SikuInternal.jobs.state.byId[id] and id or nil
end

--- The name of a job by id, for the public view of a job account.
---@param jobId number The job id.
---@return string? jobName The name, or nil for an unknown job.
function _SikuInternal.accounts.jobNameOf(jobId)
  local job <const> = _SikuInternal.jobs.state.byId[jobId]

  return job and job.name or nil
end

--- Indexes an entry under its owner.
---@param entry table The cached account.
---@return nil
function _SikuInternal.accounts.indexOwner(entry)
  local owners <const> = state.byOwner[entry.ownerType]

  owners[entry.ownerId] = owners[entry.ownerId] or {}
  owners[entry.ownerId][entry.id] = true
end

--- Forgets an entry under its owner.
---@param entry table The cached account.
---@return nil
function _SikuInternal.accounts.unindexOwner(entry)
  local owned <const> = state.byOwner[entry.ownerType][entry.ownerId]

  if not owned then
    return
  end

  owned[entry.id] = nil

  if not next(owned) then
    state.byOwner[entry.ownerType][entry.ownerId] = nil
  end
end

--- The grants a character holds on an account, as a set of patterns.
---@param accountId number The account id.
---@param characterId number The character id.
---@return table? grants The set, or nil when there is none.
function _SikuInternal.accounts.grantsOf(accountId, characterId)
  local holders <const> = state.access.byAccount[accountId]

  return holders and holders[characterId] or nil
end

--- The public view of an account: a copy nobody can write back through.
---@param entry table The cached account.
---@return table public { id, ownerType, ownerId, ownerName?, balance, state, allowNegative, resource, metadata, createdAt, closedAt }.
function _SikuInternal.accounts.publicAccount(entry)
  return {
    id = entry.id,
    ownerType = entry.ownerType,
    ownerId = entry.ownerId,
    ownerName = entry.ownerType == OWNER_JOB and _SikuInternal.accounts.jobNameOf(entry.ownerId) or nil,
    balance = entry.balance,
    state = entry.state,
    allowNegative = entry.allowNegative,
    resource = entry.resource,
    metadata = Siku.table.deepClone(entry.metadata),
    createdAt = entry.createdAt,
    closedAt = entry.closedAt,
  }
end

--- The public view of an account as a character sees it: the account, whether
--- the character owns it, and the grants it holds on it.
---@param entry table The cached account.
---@param characterId number The character looking.
---@return table view The public account plus `owned` and `grants`.
function _SikuInternal.accounts.viewFor(entry, characterId)
  local view <const> = _SikuInternal.accounts.publicAccount(entry)
  local grants <const> = _SikuInternal.accounts.grantsOf(entry.id, characterId)
  local list <const> = {}

  for pattern in pairs(grants or {}) do
    list[#list + 1] = pattern
  end

  table.sort(list)

  view.owned = entry.ownerType == OWNER_CHARACTER and entry.ownerId == characterId
  view.grants = list

  return view
end

--- Sends a character every account it owns or holds a grant on, and nobody
--- else: a balance is not for every client to read off a state bag.
---@param characterId number The character id.
---@return nil
function _SikuInternal.accounts.push(characterId)
  local sessionId <const> = Siku.cache.getSessionByCharacter(characterId)

  if not sessionId then
    return
  end

  TriggerClientEvent(CLIENT_EVENT, sessionId, Siku.accounts.getAccessible(characterId))
end

--- Sends the fresh view to everyone who sees an account: its owning
--- character and every character holding a grant on it.
---@param entry table The cached account.
---@return nil
function _SikuInternal.accounts.pushWatchers(entry)
  local pushed <const> = {}

  if entry.ownerType == OWNER_CHARACTER then
    pushed[entry.ownerId] = true
    _SikuInternal.accounts.push(entry.ownerId)
  end

  for characterId in pairs(state.access.byAccount[entry.id] or {}) do
    if not pushed[characterId] then
      pushed[characterId] = true
      _SikuInternal.accounts.push(characterId)
    end
  end
end

--- Holds the locks of a list of accounts, in id order so two batches that
--- overlap never wait on each other forever.
---@param ids table The account ids, sorted ascending.
---@return nil
function _SikuInternal.accounts.lock(ids)
  for index = 1, #ids do
    while state.locks[ids[index]] do
      Wait(LOCK_POLL_MS)
    end

    state.locks[ids[index]] = true
  end
end

--- Releases the locks of a list of accounts.
---@param ids table The account ids.
---@return nil
function _SikuInternal.accounts.unlock(ids)
  for index = 1, #ids do
    state.locks[ids[index]] = nil
  end
end

--- Whether an account is known, whatever its state.
---@param accountId number The account id.
---@return boolean exists Whether the account is registered.
function Siku.accounts.exists(accountId)
  return _SikuInternal.accounts.getEntry(accountId) ~= nil
end

--- One account.
---@param accountId number The account id.
---@return table? account The public account, or nil.
function Siku.accounts.getAccount(accountId)
  local entry <const> = _SikuInternal.accounts.getEntry(accountId)

  return entry and _SikuInternal.accounts.publicAccount(entry) or nil
end

--- The balance of an account.
---@param accountId number The account id.
---@return number? balance The balance, or nil for an unknown account.
function Siku.accounts.getBalance(accountId)
  local entry <const> = _SikuInternal.accounts.getEntry(accountId)

  return entry and entry.balance or nil
end

--- The state of an account.
---@param accountId number The account id.
---@return string? state `active`, `frozen` or `closed`, nil for an unknown account.
function Siku.accounts.getState(accountId)
  local entry <const> = _SikuInternal.accounts.getEntry(accountId)

  return entry and entry.state or nil
end

--- Whether an account accepts mutations right now.
---@param accountId number The account id.
---@return boolean active Whether the account is active.
function Siku.accounts.isActive(accountId)
  local entry <const> = _SikuInternal.accounts.getEntry(accountId)

  return entry ~= nil and entry.state == STATE_ACTIVE
end

--- Every account of an owner, sorted by id.
---@param ownerType string `character` or `job`.
---@param ownerId number|string The character id, or the job id or name.
---@param includeClosed? boolean Whether closed accounts are listed too.
---@return table accounts The public accounts, empty for an unknown owner.
function Siku.accounts.getByOwner(ownerType, ownerId, includeClosed)
  if not _SikuInternal.accounts.isValidOwnerType(ownerType) then
    return {}
  end

  local id <const> = ownerType == OWNER_JOB
    and _SikuInternal.accounts.resolveJobId(ownerId)
    or _SikuInternal.accounts.toInteger(ownerId)

  if not id then
    return {}
  end

  local accounts <const> = {}

  for accountId in pairs(state.byOwner[ownerType][id] or {}) do
    local entry <const> = state.byId[accountId]

    if entry and (includeClosed or entry.state ~= STATE_CLOSED) then
      accounts[#accounts + 1] = _SikuInternal.accounts.publicAccount(entry)
    end
  end

  table.sort(accounts, function(a, b)
    return a.id < b.id
  end)

  return accounts
end

--- The accounts a character owns.
---@param characterId number The character id.
---@param includeClosed? boolean Whether closed accounts are listed too.
---@return table accounts The public accounts.
function Siku.accounts.getCharacterAccounts(characterId, includeClosed)
  return Siku.accounts.getByOwner(OWNER_CHARACTER, characterId, includeClosed)
end

--- The accounts a job owns.
---@param job number|string The job id or name.
---@param includeClosed? boolean Whether closed accounts are listed too.
---@return table accounts The public accounts.
function Siku.accounts.getJobAccounts(job, includeClosed)
  return Siku.accounts.getByOwner(OWNER_JOB, job, includeClosed)
end

--- Every account a character can see: the ones it owns and the ones it holds
--- a grant on, each with `owned` and `grants`, sorted by id. Closed accounts
--- are left out.
---@param characterId number The character id.
---@return table accounts The views.
function Siku.accounts.getAccessible(characterId)
  local id <const> = _SikuInternal.accounts.toInteger(characterId)

  if not id then
    return {}
  end

  local seen <const> = {}
  local views <const> = {}

  local function add(accountId)
    local entry <const> = state.byId[accountId]

    if entry and not seen[accountId] and entry.state ~= STATE_CLOSED then
      seen[accountId] = true
      views[#views + 1] = _SikuInternal.accounts.viewFor(entry, id)
    end
  end

  for accountId in pairs(state.byOwner[OWNER_CHARACTER][id] or {}) do
    add(accountId)
  end

  for accountId in pairs(state.access.byCharacter[id] or {}) do
    add(accountId)
  end

  table.sort(views, function(a, b)
    return a.id < b.id
  end)

  return views
end

--- How many accounts an owner holds, closed ones left out.
---@param ownerType string `character` or `job`.
---@param ownerId number|string The character id, or the job id or name.
---@return number count The number of accounts.
function Siku.accounts.count(ownerType, ownerId)
  return #Siku.accounts.getByOwner(ownerType, ownerId, false)
end
