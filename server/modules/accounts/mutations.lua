local internal <const> = _SikuInternal.accounts
local state <const> = internal.state

local EVENT_BALANCE_CHANGED <const> = 'balanceChanged'
local REASON_MAX_LENGTH <const> = 128
local REASON_SET <const> = 'set'

--- Writes one line of the mutation journal when it is enabled.
---@param batch string The batch id the mutation belongs to.
---@param accountId number The account.
---@param delta number The amount moved.
---@param balanceAfter number The balance once applied.
---@param reason? string The reason the caller gave.
---@param resource string The resource that asked.
---@param performedBy? number The character acting.
---@return nil
function internal.journal(batch, accountId, delta, balanceAfter, reason, resource, performedBy)
  if not AccountsConfig.journal then
    return
  end

  MySQL.insert.await(
    'INSERT INTO account_mutations (batch, account_id, delta, balance_after, reason, resource, performed_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
    { batch, accountId, delta, balanceAfter, reason, resource, performedBy }
  )
end

--- The journal line of a mutation, as a query of the batch transaction.
---@param batch string The batch id.
---@param accountId number The account.
---@param delta number The amount moved.
---@param balanceAfter number The balance once applied.
---@param context table The normalized context.
---@return table query { query, values }.
local function journalQuery(batch, accountId, delta, balanceAfter, context)
  return {
    query = 'INSERT INTO account_mutations (batch, account_id, delta, balance_after, reason, resource, performed_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
    values = { batch, accountId, delta, balanceAfter, context.reason, context.resource, context.performedBy },
  }
end

--- Validates the context of a batch.
---@param context any The context passed.
---@param resource string The resource that asked.
---@return table? normalized { reason?, performedBy?, resource }, nil when refused.
---@return string? reason Why it was refused.
local function normalizeContext(context, resource)
  if context ~= nil and type(context) ~= 'table' then
    return nil, 'invalid_context'
  end

  local given <const> = context or {}

  if given.reason ~= nil and (type(given.reason) ~= 'string' or #given.reason > REASON_MAX_LENGTH) then
    return nil, 'invalid_reason'
  end

  if given.performedBy ~= nil and not internal.toInteger(given.performedBy) then
    return nil, 'invalid_context'
  end

  return {
    reason = given.reason,
    performedBy = given.performedBy,
    resource = resource,
  }, nil
end

--- Validates one mutation of a batch against the cache, without touching it.
---@param mutation any The mutation passed.
---@param seen table The account ids the batch already touched.
---@return table? normalized { id, delta, entry }, nil when refused.
---@return string? reason Why it was refused.
local function normalizeMutation(mutation, seen)
  if type(mutation) ~= 'table' then
    return nil, 'invalid_batch'
  end

  local accountId <const> = internal.toAccountId(mutation.account)

  if not accountId then
    return nil, 'unknown_account'
  end

  if seen[accountId] then
    return nil, 'duplicate_account'
  end

  local entry <const> = state.byId[accountId]

  if not entry then
    return nil, 'unknown_account'
  end

  if entry.state ~= internal.STATE_ACTIVE then
    return nil, entry.state
  end

  local delta <const> = internal.toInteger(mutation.delta)

  if not delta or delta == 0 then
    return nil, 'invalid_amount'
  end

  local limit <const> = internal.toInteger(AccountsConfig.maxAmount)

  if limit and limit > 0 and math.abs(delta) > limit then
    return nil, 'amount_limit'
  end

  seen[accountId] = true

  return { id = accountId, delta = delta, entry = entry }, nil
end

--- Validates a whole batch.
---@param mutations any The list passed.
---@return table? normalized The list of { id, delta, entry }, sorted by id.
---@return string? reason Why it was refused.
local function normalizeBatch(mutations)
  if type(mutations) ~= 'table' or #mutations == 0 then
    return nil, 'invalid_batch'
  end

  if #mutations > AccountsConfig.maxBatchSize then
    return nil, 'batch_too_large'
  end

  local seen <const> = {}
  local normalized <const> = {}

  for index = 1, #mutations do
    local mutation <const>, reason <const> = normalizeMutation(mutations[index], seen)

    if not mutation then
      return nil, reason
    end

    normalized[#normalized + 1] = mutation
  end

  table.sort(normalized, function(a, b)
    return a.id < b.id
  end)

  return normalized, nil
end

--- Checks every resulting balance against the negative rule, under the lock,
--- so the cache the check reads is the cache the write will move.
---@param normalized table The sorted list.
---@return boolean ok Whether every balance stays allowed.
---@return string? reason Why it does not.
local function checkBalances(normalized)
  for index = 1, #normalized do
    local mutation <const> = normalized[index]
    local after <const> = mutation.entry.balance + mutation.delta

    if after < 0 and not mutation.entry.allowNegative then
      return false, 'insufficient_balance'
    end
  end

  return true, nil
end

--- Applies a batch of balance mutations, all of them or none. Each mutation
--- names an account and a delta; the core checks the accounts are active,
--- the amounts are whole and the balances stay allowed, then writes every
--- balance and every journal line in one transaction, moves the cache and
--- tells the ecosystem. What the batch means is the caller's business.
---@param mutations table The list of { account, delta }.
---@param context? table { reason?, performedBy? }.
---@return boolean applied Whether the batch went through.
---@return string? reason Why it was refused.
---@return table? result { batch, balances = { [accountId] = balance } } when applied.
function Siku.accounts.apply(mutations, context)
  local resource <const> = GetInvokingResource() or GetCurrentResourceName()

  if not internal.waitReady() then
    return false, 'not_ready', nil
  end

  local normalizedContext <const>, contextReason <const> = normalizeContext(context, resource)

  if not normalizedContext then
    return false, contextReason, nil
  end

  local normalized <const>, reason <const> = normalizeBatch(mutations)

  if not normalized then
    return false, reason, nil
  end

  local ids <const> = {}

  for index = 1, #normalized do
    ids[index] = normalized[index].id
  end

  internal.lock(ids)

  local ok <const>, balanceReason <const> = checkBalances(normalized)

  if not ok then
    internal.unlock(ids)
    return false, balanceReason, nil
  end

  local batch <const> = Siku.math.randomUUIDv7()
  local queries <const> = {}
  local balances <const> = {}

  for index = 1, #normalized do
    local mutation <const> = normalized[index]
    local after <const> = mutation.entry.balance + mutation.delta

    balances[mutation.id] = after
    queries[#queries + 1] = {
      query = 'UPDATE accounts SET balance = balance + ?, updated_at = NOW() WHERE id = ?',
      values = { mutation.delta, mutation.id },
    }

    if AccountsConfig.journal then
      queries[#queries + 1] = journalQuery(batch, mutation.id, mutation.delta, after, normalizedContext)
    end
  end

  local written <const> = MySQL.transaction.await(queries)

  if not written then
    internal.unlock(ids)
    Siku.print.error(('Accounts batch %s from %q was not written'):format(batch, resource))
    return false, 'write_failed', nil
  end

  for index = 1, #normalized do
    normalized[index].entry.balance = balances[normalized[index].id]
  end

  internal.unlock(ids)

  for index = 1, #normalized do
    local mutation <const> = normalized[index]

    internal.emit(EVENT_BALANCE_CHANGED, mutation.id, mutation.entry.balance, mutation.delta, batch, normalizedContext.reason, normalizedContext.performedBy)
    internal.pushWatchers(mutation.entry)
  end

  return true, nil, { batch = batch, balances = balances }
end

--- Adds an amount to an account.
---@param accountId number The account id.
---@param amount number The amount, whole and positive.
---@param context? table { reason?, performedBy? }.
---@return boolean credited, string? reason, table? result Whether it happened, why not, and the batch.
function Siku.accounts.credit(accountId, amount, context)
  local value <const> = internal.toInteger(amount)

  if not value or value <= 0 then
    return false, 'invalid_amount', nil
  end

  return Siku.accounts.apply({ { account = accountId, delta = value } }, context)
end

--- Takes an amount from an account.
---@param accountId number The account id.
---@param amount number The amount, whole and positive.
---@param context? table { reason?, performedBy? }.
---@return boolean debited, string? reason, table? result Whether it happened, why not, and the batch.
function Siku.accounts.debit(accountId, amount, context)
  local value <const> = internal.toInteger(amount)

  if not value or value <= 0 then
    return false, 'invalid_amount', nil
  end

  return Siku.accounts.apply({ { account = accountId, delta = -value } }, context)
end

--- Moves an amount from one account to another, both or neither.
---@param fromAccountId number The account debited.
---@param toAccountId number The account credited.
---@param amount number The amount, whole and positive.
---@param context? table { reason?, performedBy? }.
---@return boolean transferred, string? reason, table? result Whether it happened, why not, and the batch.
function Siku.accounts.transfer(fromAccountId, toAccountId, amount, context)
  local value <const> = internal.toInteger(amount)

  if not value or value <= 0 then
    return false, 'invalid_amount', nil
  end

  if internal.toAccountId(fromAccountId) == internal.toAccountId(toAccountId) then
    return false, 'same_account', nil
  end

  return Siku.accounts.apply({
    { account = fromAccountId, delta = -value },
    { account = toAccountId, delta = value },
  }, context)
end

--- Sets a balance outright, as a mutation of the difference so the journal
--- and the events stay honest. For administration, not for gameplay.
---@param accountId number The account id.
---@param balance number The balance wanted, whole.
---@param context? table { reason?, performedBy? }.
---@return boolean set, string? reason, table? result Whether it happened, why not, and the batch.
function Siku.accounts.setBalance(accountId, balance, context)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return false, 'unknown_account', nil
  end

  local wanted <const> = internal.toInteger(balance)

  if not wanted then
    return false, 'invalid_amount', nil
  end

  if wanted == entry.balance then
    return false, 'unchanged', nil
  end

  local given <const> = type(context) == 'table' and context or {}

  return Siku.accounts.apply({ { account = entry.id, delta = wanted - entry.balance } }, {
    reason = given.reason or REASON_SET,
    performedBy = given.performedBy,
  })
end

--- The last mutations of an account, newest first, from the journal.
---@param accountId number The account id.
---@param limit? number How many lines at most, 50 by default, 500 at most.
---@return table mutations The list of { id, batch, delta, balanceAfter, reason, resource, performedBy, createdAt }.
function Siku.accounts.getMutations(accountId, limit)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return {}
  end

  local count <const> = math.min(math.max(internal.toInteger(limit) or 50, 1), 500)
  local rows <const> = MySQL.query.await(
    'SELECT id, batch, delta, balance_after, reason, resource, performed_by, created_at FROM account_mutations WHERE account_id = ? ORDER BY id DESC LIMIT ?',
    { entry.id, count }
  )

  local mutations <const> = {}

  for index = 1, #rows do
    local row <const> = rows[index]

    mutations[index] = {
      id = row.id,
      batch = row.batch,
      delta = math.tointeger(row.delta) or 0,
      balanceAfter = math.tointeger(row.balance_after) or 0,
      reason = row.reason,
      resource = row.resource,
      performedBy = row.performed_by,
      createdAt = row.created_at,
    }
  end

  return mutations
end
