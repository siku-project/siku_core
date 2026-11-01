local CONSOLE_SOURCE <const> = 0
local PERMISSION_MANAGE <const> = 'jobs.manage'
local COMMAND_COOLDOWN_MS <const> = 500

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
    title = T('jobs_command_title'),
    description = message,
  })
end

--- Translates an engine reason into a line for the caller.
---@param reason string The reason the engine returned.
---@param jobName string The job the action aimed at.
---@param gradeName? string The grade the action aimed at.
---@return string message The line.
local function explain(reason, jobName, gradeName)
  local key <const> = ('jobs_reason_%s'):format(reason)

  return T(key, jobName, gradeName or '')
end

--- The character acting, for the audit log.
---@param src number The caller's server id, or 0 for the console.
---@return table context { performedBy?, enforceHierarchy = false }.
local function staffContext(src)
  return {
    performedBy = src ~= CONSOLE_SOURCE and Siku.cache.getCurrentCharacterId(src) or nil,
    enforceHierarchy = false,
  }
end

--- One line describing a membership.
---@param membership table The public membership.
---@return string line The line.
local function describe(membership)
  local duty <const> = membership.onDuty == nil and '' or (' · ' .. T(membership.onDuty and 'jobs_on_duty' or 'jobs_off_duty'))

  return ('%s — %s%s'):format(membership.label, membership.gradeLabel or membership.grade or '?', duty)
end

Siku.command.register('setjob', function(src, args)
  local characterId <const> = Siku.cache.getCurrentCharacterId(args.target)
  local jobName <const> = args.job
  local gradeName <const> = args.grade

  if not characterId then
    local message <const> = T('jobs_no_character', args.target)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if args.target ~= src then
      entities[#entities + 1] = { type = 'player', id = args.target, role = 'target' }
    end

    Siku.log.warn('jobs.command_refused', message, {
      command = 'setjob',
      reason = 'no_character',
      job = jobName,
      grade = gradeName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local context <const> = staffContext(src)
  local ok, reason

  if Siku.jobs.hasJob(characterId, jobName) then
    ok, reason = Siku.jobs.setGrade(characterId, jobName, gradeName, context)
  else
    ok, reason = Siku.jobs.hire(characterId, jobName, gradeName, context)
  end

  if not ok then
    local message <const> = T('jobs_refused', explain(reason, jobName, gradeName))
    local entities <const> = { { type = 'character', id = characterId, role = 'target', session = args.target } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('jobs.command_refused', message, {
      command = 'setjob',
      reason = reason,
      job = jobName,
      grade = gradeName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local membership <const> = Siku.jobs.getMembership(characterId, jobName)
  local message <const> = T('jobs_set', characterId, describe(membership))

  tell(src, 'success', message)

  if src ~= args.target then
    tell(args.target, 'info', T('jobs_you_are_now', describe(membership)))
  end
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Embauche un personnage dans un job ou change son grade.',
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'job', type = 'string', help = 'Nom du job' },
    { name = 'grade', type = 'string', help = 'Nom du grade' },
  },
})

Siku.command.register('unsetjob', function(src, args)
  local characterId <const> = Siku.cache.getCurrentCharacterId(args.target)
  local jobName <const> = args.job

  if not characterId then
    local message <const> = T('jobs_no_character', args.target)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if args.target ~= src then
      entities[#entities + 1] = { type = 'player', id = args.target, role = 'target' }
    end

    Siku.log.warn('jobs.command_refused', message, {
      command = 'unsetjob',
      reason = 'no_character',
      job = jobName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local membership <const> = Siku.jobs.getMembership(characterId, jobName)
  local ok <const>, reason <const> = Siku.jobs.fire(characterId, jobName, staffContext(src))

  if not ok then
    local message <const> = T('jobs_refused', explain(reason, jobName))
    local entities <const> = { { type = 'character', id = characterId, role = 'target', session = args.target } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('jobs.command_refused', message, {
      command = 'unsetjob',
      reason = reason,
      job = jobName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local message <const> = T('jobs_unset', characterId, membership and membership.label or jobName)

  tell(src, 'success', message)

  if src ~= args.target then
    tell(args.target, 'info', T('jobs_you_left', membership and membership.label or jobName))
  end
end, {
  permission = PERMISSION_MANAGE,
  allowConsole = true,
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Retire un personnage d'un job.",
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'job', type = 'string', help = 'Nom du job' },
  },
})

Siku.command.register('jobs', function(src, args)
  local sessionId <const> = args.target or src

  if sessionId ~= src and not Siku.permissions.hasPermission(Siku.cache.getCurrentCharacterId(src) or 0, PERMISSION_MANAGE) then
    local message <const> = T('jobs_not_allowed_others')

    Siku.log.warn('jobs.command_refused', message, {
      command = 'jobs',
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
    local message <const> = T('jobs_no_character', sessionId)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if sessionId ~= src then
      entities[#entities + 1] = { type = 'player', id = sessionId, role = 'target' }
    end

    Siku.log.warn('jobs.command_refused', message, {
      command = 'jobs',
      reason = 'no_character',
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })
    tell(src, 'error', message)
    return
  end

  local memberships <const> = Siku.jobs.getMemberships(characterId)

  if #memberships == 0 then
    tell(src, 'info', T('jobs_none', characterId))
    return
  end

  local lines <const> = {}

  for index = 1, #memberships do
    lines[index] = describe(memberships[index])
  end

  local status <const> = Siku.jobs.isUnemployed(characterId) and T('jobs_unemployed') or T('jobs_employed')

  tell(src, 'info', ('%s\n%s'):format(status, table.concat(lines, '\n')))
end, {
  cooldown = COMMAND_COOLDOWN_MS,
  description = "Affiche les jobs d'un personnage.",
  arguments = {
    { name = 'target', type = 'player', optional = true, help = 'Id du joueur, soi-même sans argument' },
  },
})
