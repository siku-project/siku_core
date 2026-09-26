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
---@param jobName string The job the action aimed at.
---@param gradeName? string The grade the action aimed at.
---@return string message The line.
local function explain(reason, jobName, gradeName)
  local key <const> = ('jobs_reason_%s'):format(reason)

  return T(key, jobName, gradeName or '')
end

--- The character a session plays, or a refusal.
---@param src number The caller's server id.
---@param sessionId number The session looked at.
---@return number? characterId The character id, or nil after refusing.
local function characterOf(src, sessionId)
  local characterId <const> = Siku.cache.getCurrentCharacterId(sessionId)

  if not characterId then
    refuse(src, 'jobs_no_character', sessionId)
  end

  return characterId
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
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local jobName <const> = args.job
  local gradeName <const> = args.grade
  local context <const> = staffContext(src)
  local ok, reason

  if Siku.jobs.hasJob(characterId, jobName) then
    ok, reason = Siku.jobs.setGrade(characterId, jobName, gradeName, context)
  else
    ok, reason = Siku.jobs.hire(characterId, jobName, gradeName, context)
  end

  if not ok then
    refuse(src, 'jobs_refused', explain(reason, jobName, gradeName))
    return
  end

  local membership <const> = Siku.jobs.getMembership(characterId, jobName)
  local message <const> = T('jobs_set', characterId, describe(membership))

  Siku.print.info(message)
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
  local characterId <const> = characterOf(src, args.target)

  if not characterId then
    return
  end

  local jobName <const> = args.job
  local membership <const> = Siku.jobs.getMembership(characterId, jobName)
  local ok <const>, reason <const> = Siku.jobs.fire(characterId, jobName, staffContext(src))

  if not ok then
    refuse(src, 'jobs_refused', explain(reason, jobName))
    return
  end

  local message <const> = T('jobs_unset', characterId, membership and membership.label or jobName)

  Siku.print.info(message)
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
    refuse(src, 'jobs_not_allowed_others')
    return
  end

  local characterId <const> = characterOf(src, sessionId)

  if not characterId then
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

Siku.command.register('duty', function(src, args)
  local characterId <const> = characterOf(src, src)

  if not characterId then
    return
  end

  local jobName <const> = args.job
  local onDuty <const> = not Siku.jobs.isOnDuty(characterId, jobName)
  local ok <const>, reason <const> = Siku.jobs.setDuty(characterId, jobName, onDuty)

  if not ok then
    refuse(src, 'jobs_refused', explain(reason, jobName))
    return
  end

  local membership <const> = Siku.jobs.getMembership(characterId, jobName)

  tell(src, 'success', T(onDuty and 'jobs_duty_started' or 'jobs_duty_ended', membership.label))
end, {
  cooldown = COMMAND_COOLDOWN_MS,
  description = 'Prend ou quitte le service dans un job légal.',
  arguments = {
    { name = 'job', type = 'string', help = 'Nom du job' },
  },
})
