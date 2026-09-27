local internal <const> = _SikuInternal.accounts
local state <const> = internal.state

local EVENT_CREATED <const> = 'created'
local EVENT_STATE_CHANGED <const> = 'stateChanged'
local EVENT_METADATA_CHANGED <const> = 'metadataChanged'
local EVENT_DELETED <const> = 'deleted'
local REASON_OPENING <const> = 'opening'

--- Turns a metadata column into a table.
---@param raw any The stored text.
---@return table metadata The decoded table, empty when there was none.
local function decodeMetadata(raw)
  if type(raw) ~= 'string' or raw == '' then
    return {}
  end

  local ok <const>, decoded <const> = pcall(json.decode, raw)

  return ok and type(decoded) == 'table' and decoded or {}
end

--- Builds a cache entry for an `accounts` row.
---@param row table The row.
---@return table entry The entry.
local function createEntry(row)
  return {
    id = row.id,
    ownerType = row.owner_type,
    ownerId = row.owner_id,
    balance = math.tointeger(row.balance) or 0,
    state = row.state,
    allowNegative = row.allow_negative == 1 or row.allow_negative == true,
    resource = row.resource,
    metadata = decodeMetadata(row.metadata),
    createdAt = row.created_at,
    closedAt = row.closed_at,
  }
end

--- Puts an entry in the cache, replacing the one it stands for.
---@param entry table The entry.
---@return nil
local function cache(entry)
  local previous <const> = state.byId[entry.id]

  if previous then
    internal.unindexOwner(previous)
  end

  state.byId[entry.id] = entry
  internal.indexOwner(entry)
end

--- Reads one account from the database into the cache.
---@param accountId number The account id.
---@return table? entry The fresh entry, or nil when the row is gone.
function internal.reload(accountId)
  local row <const> = MySQL.single.await('SELECT * FROM accounts WHERE id = ?', { accountId })

  if not row then
    return nil
  end

  local entry <const> = createEntry(row)

  cache(entry)

  return entry
end

--- Reads every account and every grant from the database.
---@return number count The number of accounts loaded.
local function loadAll()
  state.byId = {}
  state.byOwner = { [internal.OWNER_CHARACTER] = {}, [internal.OWNER_JOB] = {} }
  state.access = { byAccount = {}, byCharacter = {} }

  local rows <const> = MySQL.query.await('SELECT * FROM accounts')

  for index = 1, #rows do
    cache(createEntry(rows[index]))
  end

  local grants <const> = MySQL.query.await('SELECT account_id, character_id, permission FROM account_access')

  for index = 1, #grants do
    internal.cacheGrant(grants[index].account_id, grants[index].character_id, grants[index].permission)
  end

  return #rows
end

--- Whether a character row exists, for an account aimed at someone offline.
---@param characterId number The character id.
---@return boolean exists Whether the character is in the database.
local function characterExists(characterId)
  if Siku.cache.getCharacter(characterId) then
    return true
  end

  return MySQL.scalar.await('SELECT id FROM characters WHERE id = ?', { characterId }) ~= nil
end

--- Resolves and checks the owner of a new account.
---@param ownerType any The owner type.
---@param owner any The character id, or the job id or name.
---@return number? ownerId The owner id, nil when refused.
---@return string? reason Why it was refused.
local function resolveOwner(ownerType, owner)
  if not internal.isValidOwnerType(ownerType) then
    return nil, 'invalid_owner_type'
  end

  if ownerType == internal.OWNER_JOB then
    local jobId <const> = internal.resolveJobId(owner)

    if not jobId then
      return nil, 'unknown_owner'
    end

    return jobId, nil
  end

  local characterId <const> = internal.toInteger(owner)

  if not characterId or characterId <= 0 or not characterExists(characterId) then
    return nil, 'unknown_owner'
  end

  return characterId, nil
end

--- Validates the options of a new account.
---@param options any The options passed.
---@return table? normalized { allowNegative, metadata, balance }, nil when refused.
---@return string? reason Why it was refused.
local function normalizeOptions(options)
  if options ~= nil and type(options) ~= 'table' then
    return nil, 'invalid_options'
  end

  local given <const> = options or {}

  if given.metadata ~= nil and type(given.metadata) ~= 'table' then
    return nil, 'invalid_metadata'
  end

  local balance = 0

  if given.balance ~= nil then
    balance = internal.toInteger(given.balance)

    if not balance then
      return nil, 'invalid_amount'
    end
  end

  local allowNegative <const> = given.allowNegative == true or (given.allowNegative == nil and AccountsConfig.allowNegative == true)

  if balance < 0 and not allowNegative then
    return nil, 'insufficient_balance'
  end

  return {
    allowNegative = allowNegative,
    metadata = given.metadata and Siku.table.deepClone(given.metadata) or {},
    balance = balance,
  }, nil
end

--- Creates an account for an owner, on behalf of the calling resource. The
--- core checks the owner exists and the options make sense, nothing else:
--- whether the owner may open an account is the caller's business.
---@param ownerType string `character` or `job`.
---@param owner number|string The character id, or the job id or name.
---@param options? table { allowNegative?, metadata?, balance? }.
---@return number? accountId The new account id, nil when refused.
---@return string? reason Why it was refused.
function Siku.accounts.create(ownerType, owner, options)
  local resource <const> = GetInvokingResource() or GetCurrentResourceName()

  if not internal.waitReady() then
    return nil, 'not_ready'
  end

  local ownerId <const>, ownerReason <const> = resolveOwner(ownerType, owner)

  if not ownerId then
    return nil, ownerReason
  end

  local normalized <const>, reason <const> = normalizeOptions(options)

  if not normalized then
    return nil, reason
  end

  local accountId <const> = MySQL.insert.await(
    'INSERT INTO accounts (owner_type, owner_id, balance, state, allow_negative, resource, metadata) VALUES (?, ?, ?, ?, ?, ?, ?)',
    {
      ownerType,
      ownerId,
      normalized.balance,
      internal.STATE_ACTIVE,
      normalized.allowNegative and 1 or 0,
      resource,
      next(normalized.metadata) and json.encode(normalized.metadata) or nil,
    }
  )

  if not accountId then
    return nil, 'write_failed'
  end

  if normalized.balance ~= 0 then
    internal.journal(Siku.math.randomUUIDv7(), accountId, normalized.balance, normalized.balance, REASON_OPENING, resource, nil)
  end

  local entry <const> = internal.reload(accountId)

  if not entry then
    return nil, 'reload_failed'
  end

  internal.emit(EVENT_CREATED, entry.id, internal.publicAccount(entry))
  internal.pushWatchers(entry)

  return entry.id, nil
end

--- Moves an account to another state. Closing needs an empty balance, and a
--- closed account never comes back: delete it, or open another one.
---@param accountId number The account id.
---@param newState string `active`, `frozen` or `closed`.
---@param performedBy? number The character acting, for the trace.
---@return boolean changed Whether the state moved.
---@return string? reason Why it did not.
function Siku.accounts.setState(accountId, newState, performedBy)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return false, 'unknown_account'
  end

  if not internal.isValidState(newState) then
    return false, 'invalid_state'
  end

  if entry.state == newState then
    return false, 'unchanged'
  end

  if entry.state == internal.STATE_CLOSED then
    return false, 'closed'
  end

  if newState == internal.STATE_CLOSED and entry.balance ~= 0 then
    return false, 'balance_not_zero'
  end

  local closing <const> = newState == internal.STATE_CLOSED

  MySQL.update.await(
    closing
      and 'UPDATE accounts SET state = ?, closed_at = NOW(), updated_at = NOW() WHERE id = ?'
      or 'UPDATE accounts SET state = ?, updated_at = NOW() WHERE id = ?',
    { newState, entry.id }
  )

  local previous <const> = entry.state
  local fresh <const> = internal.reload(entry.id)

  if not fresh then
    return false, 'reload_failed'
  end

  internal.emit(EVENT_STATE_CHANGED, fresh.id, fresh.state, previous, performedBy)
  internal.pushWatchers(fresh)

  return true, nil
end

--- Freezes an account: it keeps its balance and refuses every mutation.
---@param accountId number The account id.
---@param performedBy? number The character acting.
---@return boolean frozen, string? reason Whether it happened, and why not.
function Siku.accounts.freeze(accountId, performedBy)
  return Siku.accounts.setState(accountId, internal.STATE_FROZEN, performedBy)
end

--- Reopens a frozen account to mutations.
---@param accountId number The account id.
---@param performedBy? number The character acting.
---@return boolean unfrozen, string? reason Whether it happened, and why not.
function Siku.accounts.unfreeze(accountId, performedBy)
  return Siku.accounts.setState(accountId, internal.STATE_ACTIVE, performedBy)
end

--- Closes an account for good. Its balance must be zero.
---@param accountId number The account id.
---@param performedBy? number The character acting.
---@return boolean closed, string? reason Whether it happened, and why not.
function Siku.accounts.close(accountId, performedBy)
  return Siku.accounts.setState(accountId, internal.STATE_CLOSED, performedBy)
end

--- Removes a closed account and its trace from the database. Kept for
--- cleanup and maintenance: closing is the normal end of an account.
---@param accountId number The account id.
---@return boolean deleted Whether the row went.
---@return string? reason Why it did not.
function Siku.accounts.delete(accountId)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return false, 'unknown_account'
  end

  if entry.state ~= internal.STATE_CLOSED then
    return false, 'not_closed'
  end

  MySQL.update.await('DELETE FROM accounts WHERE id = ?', { entry.id })

  internal.unindexOwner(entry)
  internal.forgetGrantsOf(entry.id)
  state.byId[entry.id] = nil

  internal.emit(EVENT_DELETED, entry.id, internal.publicAccount(entry))

  return true, nil
end

--- Replaces the free metadata of an account, the space a consumer keeps its
--- own facts in: a public number, a product name, whatever it needs.
---@param accountId number The account id.
---@param metadata table The new metadata, whole.
---@return boolean changed Whether it was written.
---@return string? reason Why it was not.
function Siku.accounts.setMetadata(accountId, metadata)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return false, 'unknown_account'
  end

  if type(metadata) ~= 'table' then
    return false, 'invalid_metadata'
  end

  MySQL.update.await(
    'UPDATE accounts SET metadata = ?, updated_at = NOW() WHERE id = ?',
    { next(metadata) and json.encode(metadata) or nil, entry.id }
  )

  entry.metadata = Siku.table.deepClone(metadata)

  internal.emit(EVENT_METADATA_CHANGED, entry.id, Siku.table.deepClone(entry.metadata))
  internal.pushWatchers(entry)

  return true, nil
end

--- Allows or forbids a negative balance on one account, whatever the
--- configuration says for the others.
---@param accountId number The account id.
---@param allowed boolean Whether the balance may go under zero.
---@return boolean changed Whether it was written.
---@return string? reason Why it was not.
function Siku.accounts.setNegativeAllowed(accountId, allowed)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return false, 'unknown_account'
  end

  local wanted <const> = allowed == true

  if entry.allowNegative == wanted then
    return false, 'unchanged'
  end

  MySQL.update.await('UPDATE accounts SET allow_negative = ?, updated_at = NOW() WHERE id = ?', { wanted and 1 or 0, entry.id })

  entry.allowNegative = wanted

  internal.pushWatchers(entry)

  return true, nil
end

--- Reads the accounts from the database and opens the engine.
---@return nil
function _SikuInternal.InitAccounts()
  local count <const> = loadAll()

  state.ready = true

  Siku.print.success(('Accounts engine initialized with %d account(s)'):format(count))
end
