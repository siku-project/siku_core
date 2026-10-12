local internal <const> = _SikuInternal.licenses

local CONSOLE_SOURCE <const> = 0
local PERMISSION_MANAGE <const> = 'licenses.manage'
local COMMAND_COOLDOWN_MS <const> = 500
local REASON_COMMAND <const> = 'command'

local function tell(src, kind, message)
  if src == CONSOLE_SOURCE then
    Siku.print.info(message)
    return
  end

  Siku.notification.show(src, {
    type = kind,
    title = T('licenses_command_title'),
    description = message,
  })
end

local function refuse(src, key, ...)
  local message <const> = T(key, ...)

  Siku.print.warn(message)
  tell(src, 'error', message)
end

local function explain(reason, licenseName)
  return T(('licenses_reason_%s'):format(reason), licenseName)
end

local function characterOf(src, sessionId)
  local characterId <const> = Siku.cache.getCurrentCharacterId(sessionId)

  if not characterId then
    refuse(src, 'licenses_no_character', sessionId)
  end

  return characterId
end

local function staffContext(src)
  return {
    performedBy = src ~= CONSOLE_SOURCE and Siku.cache.getCurrentCharacterId(src) or nil,
    reason = REASON_COMMAND,
  }
end

local function labelOf(licenseName)
  local definition <const> = Siku.licenses.getDefinition(licenseName)

  return definition and definition.label or licenseName
end

local function describe(holding)
  local line = ('%s — %s'):format(holding.label, T(('licenses_state_%s'):format(holding.state)))

  if holding.maxPoints then
    line = line .. T('licenses_points_line', holding.points, holding.maxPoints)
  end

  if holding.state == internal.STATE_SUSPENDED and holding.suspendedUntil then
    line = line .. T('licenses_until_line', holding.suspendedUntil)
  elseif holding.expiresAt then
    line = line .. T('licenses_expires_line', holding.expiresAt)
  end

  return line
end

Siku.command.register('grantlicense', function(src, args)
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local licenseName <const> = args.license
  local ok <const>, reason <const> = Siku.licenses.issue(characterId, licenseName, staffContext(src))

  if not ok then
    refuse(src, 'licenses_refused', explain(reason, licenseName))
    return
  end

  local holding <const> = Siku.licenses.getHolding(characterId, licenseName)
  local message <const> = T('licenses_granted', characterId, describe(holding))

  Siku.print.info(message)
  tell(src, 'success', message)

  if src ~= args.target then
    tell(args.target, 'info', T('licenses_you_received', holding.label))
  end
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Délivre une licence à un personnage.',
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'license', type = 'string', help = 'Nom de la licence' },
  },
})

Siku.command.register('revokelicense', function(src, args)
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local licenseName <const> = args.license
  local ok <const>, reason <const> = Siku.licenses.revoke(characterId, licenseName, staffContext(src))

  if not ok then
    refuse(src, 'licenses_refused', explain(reason, licenseName))
    return
  end

  local label <const> = labelOf(licenseName)
  local message <const> = T('licenses_revoked', characterId, label)

  Siku.print.info(message)
  tell(src, 'success', message)

  if src ~= args.target then
    tell(args.target, 'warning', T('licenses_you_lost', label))
  end
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Retire définitivement une licence à un personnage.",
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'license', type = 'string', help = 'Nom de la licence' },
  },
})

Siku.command.register('suspendlicense', function(src, args)
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local licenseName <const> = args.license
  local options <const> = staffContext(src)

  if args.duration then
    options.endsAt = internal.now() + args.duration
  end

  local ok <const>, reason <const> = Siku.licenses.suspend(characterId, licenseName, options)

  if not ok then
    refuse(src, 'licenses_refused', explain(reason, licenseName))
    return
  end

  local holding <const> = Siku.licenses.getHolding(characterId, licenseName)
  local message <const> = holding.suspendedUntil
    and T('licenses_suspended_until', characterId, holding.label, holding.suspendedUntil)
    or T('licenses_suspended', characterId, holding.label)

  Siku.print.info(message)
  tell(src, 'success', message)

  if src ~= args.target then
    tell(args.target, 'warning', T('licenses_you_are_suspended', holding.label))
  end
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Suspend une licence, pour une durée ou jusqu'à nouvel ordre.",
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'license', type = 'string', help = 'Nom de la licence' },
    { name = 'duration', type = 'duration', optional = true, help = 'Durée (30m, 2h, 7d), indéfinie sans argument' },
  },
})

Siku.command.register('liftlicense', function(src, args)
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local licenseName <const> = args.license
  local ok <const>, reason <const> = Siku.licenses.lift(characterId, licenseName, staffContext(src))

  if not ok then
    refuse(src, 'licenses_refused', explain(reason, licenseName))
    return
  end

  local label <const> = labelOf(licenseName)
  local message <const> = T('licenses_lifted', characterId, label)

  Siku.print.info(message)
  tell(src, 'success', message)

  if src ~= args.target then
    tell(args.target, 'info', T('licenses_you_are_lifted', label))
  end
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Lève la suspension d'une licence.",
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'license', type = 'string', help = 'Nom de la licence' },
  },
})

Siku.command.register('licensepoints', function(src, args)
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local licenseName <const> = args.license
  local delta <const> = args.delta
  local ok, reason

  if delta >= 0 then
    ok, reason = Siku.licenses.addPoints(characterId, licenseName, delta, staffContext(src))
  else
    ok, reason = Siku.licenses.removePoints(characterId, licenseName, -delta, staffContext(src))
  end

  if not ok then
    refuse(src, 'licenses_refused', explain(reason, licenseName))
    return
  end

  local holding <const> = Siku.licenses.getHolding(characterId, licenseName)
  local message <const> = T('licenses_points_set', characterId, holding.label, holding.points, holding.maxPoints)

  Siku.print.info(message)
  tell(src, 'success', message)

  if src ~= args.target then
    tell(args.target, 'info', T('licenses_your_points', holding.label, holding.points, holding.maxPoints))
  end
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Ajoute ou retire des points sur une licence.",
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'license', type = 'string', help = 'Nom de la licence' },
    { name = 'delta', type = 'integer', help = 'Points à ajouter, négatif pour retirer' },
  },
})

Siku.command.register('licenses', function(src, args)
  local sessionId <const> = args.target or src

  if sessionId ~= src and not Siku.permissions.hasPermission(Siku.cache.getCurrentCharacterId(src) or 0, PERMISSION_MANAGE) then
    refuse(src, 'licenses_not_allowed_others')
    return
  end

  local characterId <const> = characterOf(src, sessionId)

  if not characterId then
    return
  end

  local holdings <const> = Siku.licenses.getHoldings(characterId)

  if #holdings == 0 then
    tell(src, 'info', T('licenses_none', characterId))
    return
  end

  local lines <const> = {}

  for index = 1, #holdings do
    lines[index] = describe(holdings[index])
  end

  tell(src, 'info', table.concat(lines, '\n'))
end, {
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Affiche les licences d'un personnage.",
  arguments = {
    { name = 'target', type = 'player', optional = true, help = 'Id du joueur, soi-même sans argument' },
  },
})
