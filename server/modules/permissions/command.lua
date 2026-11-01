local CONSOLE_SOURCE <const> = 0
local NO_ROLE_DEPTH <const> = -1

--- Finds a role by name among the declared ones.
---@param name string The role name.
---@return table|nil role The role, or nil when unknown.
local function findRole(name)
  local roles <const> = Siku.permissions.getAllRoles()

  for i = 1, #roles do
    if roles[i].name == name then
      return roles[i]
    end
  end

  return nil
end

--- Checks whether a character already holds a role.
---@param charId number The character ID.
---@param roleName string The role name.
---@return boolean held Whether the character holds it.
local function holdsRole(charId, roleName)
  local roles <const> = Siku.permissions.getCharacterRoles(charId)

  for i = 1, #roles do
    if roles[i].name == roleName then
      return true
    end
  end

  return false
end

--- Checks whether a role is a primary one, whatever shape the database gave the flag.
---@param role table The role row.
---@return boolean primary Whether the role is primary.
local function isPrimaryRole(role)
  return role.is_primary == 1 or role.is_primary == true
end

--- Checks that a caller may apply a role to a character. The console may do
--- anything. A player must outrank the target, unless the target is
--- themselves, and may only hand out primary roles strictly below their own.
---@param src number The caller's server id, or 0 for the console.
---@param performer table|nil The caller's active character.
---@param character table The target character.
---@param role table The role being applied.
---@return boolean allowed, string? reason Whether the change may happen, and the translation key explaining a refusal.
local function canApply(src, performer, character, role)
  if src == CONSOLE_SOURCE then
    return true
  end

  if not performer then
    return false, 'permissions_no_performer'
  end

  if performer.id ~= character.id and not Siku.permissions.canModify(performer.id, character.id) then
    return false, 'permissions_target_outranks'
  end

  if not isPrimaryRole(role) then
    return true
  end

  local performerRole <const> = Siku.permissions.getPrimaryRole(performer.id)
  local ceiling <const> = performerRole and _SikuInternal.GetRoleDepth(performerRole.id) or NO_ROLE_DEPTH

  if _SikuInternal.GetRoleDepth(role.id) >= ceiling then
    return false, 'permissions_role_too_high'
  end

  return true
end

Siku.command.register('setrole', function(src, args)
  local targetSession <const> = args.target
  local roleName <const> = args.role
  local character <const> = Siku.cache.getCurrentCharacter(targetSession)

  if not character then
    local message <const> = T('permissions_no_character', targetSession)
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    if targetSession ~= src then
      entities[#entities + 1] = { type = 'player', id = targetSession, role = 'target' }
    end

    Siku.log.warn('permissions.command_refused', message, {
      command = 'setrole',
      reason = 'no_character',
      role = roleName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })

    if src == CONSOLE_SOURCE then
      Siku.print.warn(message)
    else
      Siku.notification.show(src, {
        type = 'error',
        title = T('permissions_command_title'),
        description = message,
      })
    end

    return
  end

  local role <const> = findRole(roleName)

  if not role then
    local message <const> = T('permissions_unknown_role', roleName)
    local entities <const> = { { type = 'character', id = character.id, role = 'target', session = targetSession } }

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    Siku.log.warn('permissions.command_refused', message, {
      command = 'setrole',
      reason = 'unknown_role',
      role = roleName,
      console = src == CONSOLE_SOURCE,
    }, { outcome = 'denied', source = src ~= CONSOLE_SOURCE and src or nil, entities = entities })

    if src == CONSOLE_SOURCE then
      Siku.print.warn(message)
    else
      Siku.notification.show(src, {
        type = 'error',
        title = T('permissions_command_title'),
        description = message,
      })
    end

    return
  end

  local performer <const> = src ~= CONSOLE_SOURCE and Siku.cache.getCurrentCharacter(src) or nil
  local allowed <const>, reason <const> = canApply(src, performer, character, role)

  if not allowed then
    local message <const> = T(reason, roleName)
    local entities <const> = {
      { type = 'character', id = character.id, role = 'target', session = targetSession },
      { type = 'player', id = src, role = 'actor' },
    }

    Siku.log.warn('permissions.command_refused', message, {
      command = 'setrole',
      reason = (reason:gsub('^permissions_', '')),
      role = roleName,
      console = false,
    }, { outcome = 'denied', source = src, entities = entities })
    Siku.notification.show(src, {
      type = 'error',
      title = T('permissions_command_title'),
      description = message,
    })

    return
  end

  local primary <const> = isPrimaryRole(role)

  if primary and holdsRole(character.id, roleName) then
    Siku.notification.show(targetSession, {
      type = 'info',
      title = T('permissions_command_title'),
      description = T('permissions_already_own_role', roleName),
    })

    if src ~= CONSOLE_SOURCE and src ~= targetSession then
      Siku.notification.show(src, {
        type = 'info',
        title = T('permissions_command_title'),
        description = T('permissions_already_has_role', roleName),
      })
    end

    return
  end

  local performerId <const> = performer and performer.id or nil
  local removed = false

  if primary then
    Siku.permissions.assignRole(character.id, roleName, nil, performerId)
  elseif holdsRole(character.id, roleName) then
    Siku.permissions.revokeRole(character.id, roleName, performerId)
    removed = true
  else
    Siku.permissions.assignRole(character.id, roleName, nil, performerId)
  end

  Siku.command.refreshSuggestions(targetSession)

  local messageKey <const> = removed and 'permissions_role_removed' or 'permissions_role_applied'
  local message <const> = T(messageKey, roleName, character.id)

  if src == CONSOLE_SOURCE then
    Siku.print.info(message)
  else
    Siku.notification.show(src, {
      type = 'success',
      title = T('permissions_command_title'),
      description = message,
    })
  end
end, {
  permission = 'permissions.setrole',
  allowConsole = true,
  description = 'Assigne un rôle primaire ou bascule un rôle secondaire.',
  arguments = {
    { name = 'target', type = 'player', help = 'Id du joueur ou "me"' },
    { name = 'role', type = 'string', help = 'Nom du rôle' },
  },
})
