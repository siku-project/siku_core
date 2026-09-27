local CORE <const> = 'siku_core'
local SERVICES_EXPORT <const> = 'objectExport'

local service <const> = exports[CORE][SERVICES_EXPORT]().accounts

--- A handle on one account. Every read is a copy answered by the core,
--- every write goes back to it: the handle carries an id and nothing else,
--- so nothing can drift from the authority.
---@class SikuAccount
---@field id number The account id.
local Account <const> = Siku.class('Account')

--- Builds a handle.
---@param id number The account id.
function Account:constructor(id)
  self.id = id
end

--- Whether the account is known to the core.
---@return boolean exists Whether it is registered.
function Account:exists()
  return service.exists(self.id)
end

--- The account as the core sees it.
---@return table? account The public account, or nil.
function Account:read()
  return service.getAccount(self.id)
end

--- The balance.
---@return number? balance The balance, or nil for an unknown account.
function Account:getBalance()
  return service.getBalance(self.id)
end

--- The state.
---@return string? state `active`, `frozen` or `closed`, or nil.
function Account:getState()
  return service.getState(self.id)
end

--- Whether the account accepts mutations right now.
---@return boolean active Whether it is active.
function Account:isActive()
  return service.isActive(self.id)
end

--- Adds an amount.
---@param amount number The amount, whole and positive.
---@param context? table { reason?, performedBy? }.
---@return boolean credited, string? reason, table? result Whether it happened, why not, and the batch.
function Account:credit(amount, context)
  return service.credit(self.id, amount, context)
end

--- Takes an amount.
---@param amount number The amount, whole and positive.
---@param context? table { reason?, performedBy? }.
---@return boolean debited, string? reason, table? result Whether it happened, why not, and the batch.
function Account:debit(amount, context)
  return service.debit(self.id, amount, context)
end

--- Moves an amount to another account, both or neither.
---@param toAccountId number The account credited.
---@param amount number The amount, whole and positive.
---@param context? table { reason?, performedBy? }.
---@return boolean transferred, string? reason, table? result Whether it happened, why not, and the batch.
function Account:transferTo(toAccountId, amount, context)
  return service.transfer(self.id, toAccountId, amount, context)
end

--- Sets the balance outright, for administration.
---@param balance number The balance wanted.
---@param context? table { reason?, performedBy? }.
---@return boolean set, string? reason, table? result Whether it happened, why not, and the batch.
function Account:setBalance(balance, context)
  return service.setBalance(self.id, balance, context)
end

--- The last mutations, newest first.
---@param limit? number How many at most.
---@return table mutations The journal lines.
function Account:getMutations(limit)
  return service.getMutations(self.id, limit)
end

--- Freezes the account.
---@param performedBy? number The character acting.
---@return boolean frozen, string? reason Whether it happened, and why not.
function Account:freeze(performedBy)
  return service.freeze(self.id, performedBy)
end

--- Reopens a frozen account.
---@param performedBy? number The character acting.
---@return boolean unfrozen, string? reason Whether it happened, and why not.
function Account:unfreeze(performedBy)
  return service.unfreeze(self.id, performedBy)
end

--- Closes the account for good. Its balance must be zero.
---@param performedBy? number The character acting.
---@return boolean closed, string? reason Whether it happened, and why not.
function Account:close(performedBy)
  return service.close(self.id, performedBy)
end

--- Replaces the free metadata.
---@param metadata table The new metadata, whole.
---@return boolean changed, string? reason Whether it happened, and why not.
function Account:setMetadata(metadata)
  return service.setMetadata(self.id, metadata)
end

--- Allows or forbids a negative balance on this account.
---@param allowed boolean Whether the balance may go under zero.
---@return boolean changed, string? reason Whether it happened, and why not.
function Account:setNegativeAllowed(allowed)
  return service.setNegativeAllowed(self.id, allowed)
end

--- Gives a character a permission on the account.
---@param characterId number The character id.
---@param permission string The pattern granted.
---@param performedBy? number The character acting.
---@return boolean granted, string? reason Whether it happened, and why not.
function Account:grant(characterId, permission, performedBy)
  return service.grant(self.id, characterId, permission, performedBy)
end

--- Takes a permission away from a character, or all of them.
---@param characterId number The character id.
---@param permission? string The pattern, nil for all of them.
---@param performedBy? number The character acting.
---@return boolean revoked, string? reason Whether it happened, and why not.
function Account:revoke(characterId, permission, performedBy)
  return service.revoke(self.id, characterId, permission, performedBy)
end

--- The grants held on the account, by character.
---@return table grants The list of { characterId, permissions }.
function Account:getGrants()
  return service.getGrants(self.id)
end

--- Whether a character owns the account.
---@param characterId number The character id.
---@return boolean owner Whether it belongs to the character.
function Account:isOwner(characterId)
  return service.isOwner(self.id, characterId)
end

--- Whether a character may do something on the account.
---@param characterId number The character id.
---@param permission string The permission asked.
---@return boolean allowed Whether the character may.
function Account:canAct(characterId, permission)
  return service.canAct(self.id, characterId, permission)
end

local namespace <const> = {}

for key, value in pairs(service) do
  namespace[key] = value
end

--- A handle on an account, existing or not. Reading through it answers
--- copies, acting through it goes back to the core.
---@param id number The account id.
---@return SikuAccount account The handle.
function namespace.get(id)
  return Account.new(id)
end

return namespace
