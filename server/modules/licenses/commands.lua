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

local function explain(reason, licenseName)
  return T(('licenses_reason_%s'):format(reason), licenseName)
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
  local characterId <const> = Siku.cache.getCurrentCharacterId(args.target)
  local licenseName <const> = args.license

  if not characterId then
    local message <const> = T('licenses_no_character', args.target)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if args.target ~= src then
      entities[#entities + 1] = { type = 'player', id = args.target, role = 'target' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'grantlicense',
      reason = 'no_character',
      license = licenseName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local ok <const>, reason <const> = Siku.licenses.issue(characterId, licenseName, staffContext(src))

  if not ok then
    local message <const> = T('licenses_refused', explain(reason, licenseName))
    local entities <const> = { { type = 'character', id = characterId, role = 'target', session = args.target } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'grantlicense',
      reason = reason,
      license = licenseName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local holding <const> = Siku.licenses.getHolding(characterId, licenseName)
  local message <const> = T('licenses_granted', characterId, describe(holding))

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
  local characterId <const> = Siku.cache.getCurrentCharacterId(args.target)
  local licenseName <const> = args.license

  if not characterId then
    local message <const> = T('licenses_no_character', args.target)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if args.target ~= src then
      entities[#entities + 1] = { type = 'player', id = args.target, role = 'target' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'revokelicense',
      reason = 'no_character',
      license = licenseName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local ok <const>, reason <const> = Siku.licenses.revoke(characterId, licenseName, staffContext(src))

  if not ok then
    local message <const> = T('licenses_refused', explain(reason, licenseName))
    local entities <const> = { { type = 'character', id = characterId, role = 'target', session = args.target } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'revokelicense',
      reason = reason,
      license = licenseName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local label <const> = labelOf(licenseName)
  local message <const> = T('licenses_revoked', characterId, label)

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
  local characterId <const> = Siku.cache.getCurrentCharacterId(args.target)
  local licenseName <const> = args.license

  if not characterId then
    local message <const> = T('licenses_no_character', args.target)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if args.target ~= src then
      entities[#entities + 1] = { type = 'player', id = args.target, role = 'target' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'suspendlicense',
      reason = 'no_character',
      license = licenseName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local options <const> = staffContext(src)

  if args.duration then
    options.endsAt = internal.now() + args.duration
  end

  local ok <const>, reason <const> = Siku.licenses.suspend(characterId, licenseName, options)

  if not ok then
    local message <const> = T('licenses_refused', explain(reason, licenseName))
    local entities <const> = { { type = 'character', id = characterId, role = 'target', session = args.target } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'suspendlicense',
      reason = reason,
      license = licenseName,
      duration = args.duration,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local holding <const> = Siku.licenses.getHolding(characterId, licenseName)
  local message <const> = holding.suspendedUntil
    and T('licenses_suspended_until', characterId, holding.label, holding.suspendedUntil)
    or T('licenses_suspended', characterId, holding.label)

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
  local characterId <const> = Siku.cache.getCurrentCharacterId(args.target)
  local licenseName <const> = args.license

  if not characterId then
    local message <const> = T('licenses_no_character', args.target)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if args.target ~= src then
      entities[#entities + 1] = { type = 'player', id = args.target, role = 'target' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'liftlicense',
      reason = 'no_character',
      license = licenseName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local ok <const>, reason <const> = Siku.licenses.lift(characterId, licenseName, staffContext(src))

  if not ok then
    local message <const> = T('licenses_refused', explain(reason, licenseName))
    local entities <const> = { { type = 'character', id = characterId, role = 'target', session = args.target } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'liftlicense',
      reason = reason,
      license = licenseName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local label <const> = labelOf(licenseName)
  local message <const> = T('licenses_lifted', characterId, label)

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
  local characterId <const> = Siku.cache.getCurrentCharacterId(args.target)
  local licenseName <const> = args.license
  local delta <const> = args.delta

  if not characterId then
    local message <const> = T('licenses_no_character', args.target)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if args.target ~= src then
      entities[#entities + 1] = { type = 'player', id = args.target, role = 'target' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'licensepoints',
      reason = 'no_character',
      license = licenseName,
      delta = delta,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local ok, reason

  if delta >= 0 then
    ok, reason = Siku.licenses.addPoints(characterId, licenseName, delta, staffContext(src))
  else
    ok, reason = Siku.licenses.removePoints(characterId, licenseName, -delta, staffContext(src))
  end

  if not ok then
    local message <const> = T('licenses_refused', explain(reason, licenseName))
    local entities <const> = { { type = 'character', id = characterId, role = 'target', session = args.target } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'licensepoints',
      reason = reason,
      license = licenseName,
      delta = delta,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local holding <const> = Siku.licenses.getHolding(characterId, licenseName)
  local message <const> = T('licenses_points_set', characterId, holding.label, holding.points, holding.maxPoints)

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
    local message <const> = T('licenses_not_allowed_others')

    Siku.log.warn('licenses.command_refused', message, {
      command = 'licenses',
      reason = 'not_allowed_others',
      console = false,
    }, {
      outcome = 'denied',
      source = src,
      entities = { { type = 'player', id = src, role = 'actor' }, { type = 'player', id = sessionId, role = 'target' } },
    })
    tell(src, 'error', message)
    return
  end

  local characterId <const> = Siku.cache.getCurrentCharacterId(sessionId)

  if not characterId then
    local message <const> = T('licenses_no_character', sessionId)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if sessionId ~= src then
      entities[#entities + 1] = { type = 'player', id = sessionId, role = 'target' }
    end

    Siku.log.warn('licenses.command_refused', message, {
      command = 'licenses',
      reason = 'no_character',
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
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
