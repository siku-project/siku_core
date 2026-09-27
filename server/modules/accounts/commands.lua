local CONSOLE_SOURCE <const> = 0
local PERMISSION_MANAGE <const> = 'accounts.manage'
local COMMAND_COOLDOWN_MS <const> = 500
local REASON_ADMIN <const> = 'admin'
local OWNER_CHARACTER <const> = _SikuInternal.accounts.OWNER_CHARACTER

--- Sends a titled notification, or a console line when nobody is playing.
---@param src number The caller's server id, or 0 for the console.
---@param kind string The notification type.
---@param message string The line.
---@return nil
local function tell(src, kind, message)
  if src == CONSOLE_SOURCE then
    Siku.print.info(message)
    return
  end

  Siku.notification.show(src, {
    type = kind,
    title = T('accounts_command_title'),
    description = message,
  })
end

--- Reports a refusal to the caller, with the console kept informed.
---@param src number The caller's server id, or 0 for the console.
---@param key string The translation key.
---@vararg any The format arguments.
---@return nil
local function refuse(src, key, ...)
  local message <const> = T(key, ...)

  Siku.print.warn(message)
  tell(src, 'error', message)
end

--- Translates an engine reason into a line for the caller.
---@param reason string The reason the engine returned.
---@param accountId? number The account the action aimed at.
---@return string message The line.
local function explain(reason, accountId)
  return T(('accounts_reason_%s'):format(reason), accountId or 0)
end

--- The character a session plays, or a refusal.
---@param src number The caller's server id.
---@param sessionId number The session looked at.
---@return number? characterId The character id, or nil after refusing.
local function characterOf(src, sessionId)
  local characterId <const> = Siku.cache.getCurrentCharacterId(sessionId)

  if not characterId then
    refuse(src, 'accounts_no_character', sessionId)
  end

  return characterId
end

--- The character acting, for the journal.
---@param src number The caller's server id, or 0 for the console.
---@return table context { reason, performedBy? }.
local function staffContext(src)
  return {
    reason = REASON_ADMIN,
    performedBy = src ~= CONSOLE_SOURCE and Siku.cache.getCurrentCharacterId(src) or nil,
  }
end

--- One line describing an account.
---@param account table The public account.
---@return string line The line.
local function describe(account)
  local owner <const> = account.ownerType == OWNER_CHARACTER
    and T('accounts_owner_character', account.ownerId)
    or T('accounts_owner_job', account.ownerName or account.ownerId)

  return ('#%d — %s — %s (%s)'):format(account.id, owner, Siku.math.formatNumber(account.balance), T('accounts_state_' .. account.state))
end

Siku.command.register('accounts', function(src, args)
  local sessionId <const> = args.target or src

  if sessionId ~= src and not Siku.permissions.hasPermission(Siku.cache.getCurrentCharacterId(src) or 0, PERMISSION_MANAGE) then
    refuse(src, 'accounts_not_allowed_others')
    return
  end

  local characterId <const> = characterOf(src, sessionId)

  if not characterId then
    return
  end

  local accounts <const> = Siku.accounts.getAccessible(characterId)

  if #accounts == 0 then
    tell(src, 'info', T('accounts_none', characterId))
    return
  end

  local lines <const> = {}

  for index = 1, #accounts do
    lines[index] = describe(accounts[index])
  end

  tell(src, 'info', table.concat(lines, '\n'))
end, {
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Affiche les comptes d'un personnage.",
  arguments = {
    { name = 'target', type = 'player', optional = true, help = 'Id du joueur, soi-même sans argument' },
  },
})

Siku.command.register('createaccount', function(src, args)
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local accountId <const>, reason <const> = Siku.accounts.create(OWNER_CHARACTER, characterId)

  if not accountId then
    refuse(src, 'accounts_refused', explain(reason))
    return
  end

  local message <const> = T('accounts_created', accountId, characterId)

  Siku.print.info(message)
  tell(src, 'success', message)
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Ouvre un compte au nom d’un personnage.',
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
  },
})

Siku.command.register('setbalance', function(src, args)
  local ok <const>, reason <const> = Siku.accounts.setBalance(args.account, args.amount, staffContext(src))

  if not ok then
    refuse(src, 'accounts_refused', explain(reason, args.account))
    return
  end

  local message <const> = T('accounts_balance_set', args.account, Siku.math.formatNumber(Siku.accounts.getBalance(args.account)))

  Siku.print.info(message)
  tell(src, 'success', message)
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Fixe le solde d’un compte.',
  arguments = {
    { name = 'account', type = 'integer', help = 'Id du compte' },
    { name = 'amount', type = 'integer', help = 'Nouveau solde' },
  },
})

Siku.command.register('creditaccount', function(src, args)
  local ok <const>, reason <const> = Siku.accounts.credit(args.account, args.amount, staffContext(src))

  if not ok then
    refuse(src, 'accounts_refused', explain(reason, args.account))
    return
  end

  local message <const> = T('accounts_credited', Siku.math.formatNumber(args.amount), args.account, Siku.math.formatNumber(Siku.accounts.getBalance(args.account)))

  Siku.print.info(message)
  tell(src, 'success', message)
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Crédite un compte.',
  arguments = {
    { name = 'account', type = 'integer', help = 'Id du compte' },
    { name = 'amount', type = 'integer', help = 'Montant' },
  },
})

Siku.command.register('debitaccount', function(src, args)
  local ok <const>, reason <const> = Siku.accounts.debit(args.account, args.amount, staffContext(src))

  if not ok then
    refuse(src, 'accounts_refused', explain(reason, args.account))
    return
  end

  local message <const> = T('accounts_debited', Siku.math.formatNumber(args.amount), args.account, Siku.math.formatNumber(Siku.accounts.getBalance(args.account)))

  Siku.print.info(message)
  tell(src, 'success', message)
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Débite un compte.',
  arguments = {
    { name = 'account', type = 'integer', help = 'Id du compte' },
    { name = 'amount', type = 'integer', help = 'Montant' },
  },
})

Siku.command.register('freezeaccount', function(src, args)
  local frozen <const> = Siku.accounts.getState(args.account) == _SikuInternal.accounts.STATE_FROZEN
  local performedBy <const> = staffContext(src).performedBy
  local ok, reason

  if frozen then
    ok, reason = Siku.accounts.unfreeze(args.account, performedBy)
  else
    ok, reason = Siku.accounts.freeze(args.account, performedBy)
  end

  if not ok then
    refuse(src, 'accounts_refused', explain(reason, args.account))
    return
  end

  local message <const> = T(frozen and 'accounts_unfrozen' or 'accounts_frozen', args.account)

  Siku.print.info(message)
  tell(src, 'success', message)
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Gèle ou dégèle un compte.',
  arguments = {
    { name = 'account', type = 'integer', help = 'Id du compte' },
  },
})

Siku.command.register('closeaccount', function(src, args)
  local ok <const>, reason <const> = Siku.accounts.close(args.account, staffContext(src).performedBy)

  if not ok then
    refuse(src, 'accounts_refused', explain(reason, args.account))
    return
  end

  local message <const> = T('accounts_closed', args.account)

  Siku.print.info(message)
  tell(src, 'success', message)
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Ferme un compte au solde nul.',
  arguments = {
    { name = 'account', type = 'integer', help = 'Id du compte' },
  },
})
