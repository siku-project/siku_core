local OWNER_TYPES <const> = {
  CHARACTER = 'character',
  JOB = 'job',
}

local STATES <const> = {
  ACTIVE = 'active',
  FROZEN = 'frozen',
  CLOSED = 'closed',
}

local CLIENT_EVENT <const> = 'siku:client:accountsUpdated'

local CALLBACKS <const> = {
  MY_ACCOUNTS = 'siku:callback:myAccounts',
  ACCOUNT = 'siku:callback:account',
  JOB_ACCOUNTS = 'siku:callback:jobAccounts',
  MUTATIONS = 'siku:callback:accountMutations',
}

internal.OWNER_TYPES = OWNER_TYPES
internal.STATES = STATES
internal.CLIENT_EVENT = CLIENT_EVENT
internal.CALLBACKS = CALLBACKS

--- Finds an account by id in a list the engine published.
---@param accounts table The public accounts.
---@param accountId number The account id.
---@return table? account The account, or nil.
function internal.findAccount(accounts, accountId)
  for index = 1, #accounts do
    if accounts[index].id == accountId then
      return accounts[index]
    end
  end

  return nil
end

return {
  OWNER_TYPES = OWNER_TYPES,
  STATES = STATES,
}
