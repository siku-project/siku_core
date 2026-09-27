local internal <const> = _SikuInternal.accounts
local state <const> = internal.state

local EVENT_ACCESS_CHANGED <const> = 'accessChanged'

--- Remembers a grant in both indexes.
---@param accountId number The account id.
---@param characterId number The character id.
---@param permission string The pattern granted.
---@return nil
function internal.cacheGrant(accountId, characterId, permission)
  local byAccount = state.access.byAccount[accountId]

  if not byAccount then
    byAccount = {}
    state.access.byAccount[accountId] = byAccount
  end

  byAccount[characterId] = byAccount[characterId] or {}
  byAccount[characterId][permission] = true

  local byCharacter = state.access.byCharacter[characterId]

  if not byCharacter then
    byCharacter = {}
    state.access.byCharacter[characterId] = byCharacter
  end

  byCharacter[accountId] = byCharacter[accountId] or {}
  byCharacter[accountId][permission] = true
end

--- Forgets a grant, or every grant of a character on an account.
---@param accountId number The account id.
---@param characterId number The character id.
---@param permission? string The pattern, nil for all of them.
---@return nil
local function uncacheGrant(accountId, characterId, permission)
  local holders <const> = state.access.byAccount[accountId]
  local held <const> = state.access.byCharacter[characterId]

  if holders and holders[characterId] then
    if permission then
      holders[characterId][permission] = nil
    end

    if not permission or not next(holders[characterId]) then
      holders[characterId] = nil
    end

    if not next(holders) then
      state.access.byAccount[accountId] = nil
    end
  end

  if held and held[accountId] then
    if permission then
      held[accountId][permission] = nil
    end

    if not permission or not next(held[accountId]) then
      held[accountId] = nil
    end

    if not next(held) then
      state.access.byCharacter[characterId] = nil
    end
  end
end

--- Forgets every grant on an account, when it goes.
---@param accountId number The account id.
---@return nil
function internal.forgetGrantsOf(accountId)
  for characterId in pairs(state.access.byAccount[accountId] or {}) do
    uncacheGrant(accountId, characterId, nil)
  end
end

--- Whether a character row exists.
---@param characterId number The character id.
---@return boolean exists Whether the character is in the database.
local function characterExists(characterId)
  if Siku.cache.getCharacter(characterId) then
    return true
  end

  return MySQL.scalar.await('SELECT id FROM characters WHERE id = ?', { characterId }) ~= nil
end

--- Gives a character a permission on an account it does not own. The name
--- is the caller's: the core stores it and answers whether it is there.
---@param accountId number The account id.
---@param characterId number The character id.
---@param permission string The pattern granted, wildcards allowed.
---@param performedBy? number The character acting.
---@return boolean granted Whether the grant was written.
---@return string? reason Why it was not.
function Siku.accounts.grant(accountId, characterId, permission, performedBy)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return false, 'unknown_account'
  end

  local id <const> = internal.toInteger(characterId)

  if not id or id <= 0 or not characterExists(id) then
    return false, 'unknown_character'
  end

  if not _SikuInternal.jobs.isValidPermission(permission) then
    return false, 'invalid_permission'
  end

  local grants <const> = internal.grantsOf(entry.id, id)

  if grants and grants[permission] then
    return false, 'unchanged'
  end

  MySQL.insert.await(
    'INSERT INTO account_access (account_id, character_id, permission, granted_by) VALUES (?, ?, ?, ?)',
    { entry.id, id, permission, performedBy }
  )

  internal.cacheGrant(entry.id, id, permission)
  internal.emit(EVENT_ACCESS_CHANGED, entry.id, id, permission, true, performedBy)
  internal.push(id)

  return true, nil
end

--- Takes a permission away from a character on an account, or every one
--- of them when no pattern is named.
---@param accountId number The account id.
---@param characterId number The character id.
---@param permission? string The pattern, nil for all of them.
---@param performedBy? number The character acting.
---@return boolean revoked Whether something was removed.
---@return string? reason Why nothing was.
function Siku.accounts.revoke(accountId, characterId, permission, performedBy)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return false, 'unknown_account'
  end

  local id <const> = internal.toInteger(characterId)
  local grants <const> = id and internal.grantsOf(entry.id, id) or nil

  if not grants or (permission and not grants[permission]) then
    return false, 'unchanged'
  end

  if permission then
    MySQL.update.await(
      'DELETE FROM account_access WHERE account_id = ? AND character_id = ? AND permission = ?',
      { entry.id, id, permission }
    )
  else
    MySQL.update.await('DELETE FROM account_access WHERE account_id = ? AND character_id = ?', { entry.id, id })
  end

  local removed <const> = {}

  for pattern in pairs(grants) do
    if not permission or pattern == permission then
      removed[#removed + 1] = pattern
    end
  end

  uncacheGrant(entry.id, id, permission)

  for index = 1, #removed do
    internal.emit(EVENT_ACCESS_CHANGED, entry.id, id, removed[index], false, performedBy)
  end

  internal.push(id)

  return true, nil
end

--- The grants held on an account, by character.
---@param accountId number The account id.
---@return table grants The list of { characterId, permissions }, sorted by character.
function Siku.accounts.getGrants(accountId)
  local entry <const> = internal.getEntry(accountId)

  if not entry then
    return {}
  end

  local grants <const> = {}

  for characterId, patterns in pairs(state.access.byAccount[entry.id] or {}) do
    local permissions <const> = {}

    for pattern in pairs(patterns) do
      permissions[#permissions + 1] = pattern
    end

    table.sort(permissions)
    grants[#grants + 1] = { characterId = characterId, permissions = permissions }
  end

  table.sort(grants, function(a, b)
    return a.characterId < b.characterId
  end)

  return grants
end

--- The patterns a character holds on an account.
---@param accountId number The account id.
---@param characterId number The character id.
---@return table permissions The sorted list, empty when there is none.
function Siku.accounts.getGrantsOf(accountId, characterId)
  local entry <const> = internal.getEntry(accountId)
  local grants <const> = entry and internal.grantsOf(entry.id, internal.toInteger(characterId) or 0) or nil
  local permissions <const> = {}

  for pattern in pairs(grants or {}) do
    permissions[#permissions + 1] = pattern
  end

  table.sort(permissions)

  return permissions
end

--- Whether a character holds a permission on an account through a grant,
--- wildcards and negation resolved like every other permission of the core.
---@param accountId number The account id.
---@param characterId number The character id.
---@param permission string The permission asked.
---@return boolean granted Whether a grant answers it.
function Siku.accounts.hasGrant(accountId, characterId, permission)
  local entry <const> = internal.getEntry(accountId)
  local grants <const> = entry and internal.grantsOf(entry.id, internal.toInteger(characterId) or 0) or nil

  if not grants or type(permission) ~= 'string' then
    return false
  end

  return _SikuInternal.MatchPermission(grants, permission)
end

--- Whether a character owns an account.
---@param accountId number The account id.
---@param characterId number The character id.
---@return boolean owner Whether the account belongs to the character.
function Siku.accounts.isOwner(accountId, characterId)
  local entry <const> = internal.getEntry(accountId)

  return entry ~= nil
    and entry.ownerType == internal.OWNER_CHARACTER
    and entry.ownerId == internal.toInteger(characterId)
end

--- Whether a character may do something on an account, whatever the name
--- means: an owning character may everything, a grant answers by pattern,
--- and a job account asks the job engine for the same permission name.
---@param accountId number The account id.
---@param characterId number The character id.
---@param permission string The permission asked.
---@return boolean allowed Whether the character may.
function Siku.accounts.canAct(accountId, characterId, permission)
  local entry <const> = internal.getEntry(accountId)
  local id <const> = internal.toInteger(characterId)

  if not entry or not id or type(permission) ~= 'string' then
    return false
  end

  if entry.ownerType == internal.OWNER_CHARACTER and entry.ownerId == id then
    return true
  end

  if Siku.accounts.hasGrant(entry.id, id, permission) then
    return true
  end

  if entry.ownerType == internal.OWNER_JOB then
    local jobName <const> = internal.jobNameOf(entry.ownerId)

    return jobName ~= nil and Siku.jobs.hasPermission(id, jobName, permission)
  end

  return false
end
