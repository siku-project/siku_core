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

Siku.RegisterCommand('setrole', function(src, args)
  local targetSession <const> = args.target
  local roleName <const> = args.role

  local character <const> = Siku.cache.getCurrentCharacter(targetSession)

  if not character then
    Siku.print.warn(T('permissions_no_character', targetSession))

    if src ~= 0 then
      Siku.Notification(src, {
        type = 'error',
        title = T('permissions_command_title'),
        description = T('permissions_no_character', targetSession),
      })
    end

    return
  end

  local role <const> = findRole(roleName)

  if not role then
    Siku.print.warn(T('permissions_unknown_role', roleName))

    if src ~= 0 then
      Siku.Notification(src, {
        type = 'error',
        title = T('permissions_command_title'),
        description = T('permissions_unknown_role', roleName),
      })
    end

    return
  end

  local performedBy <const> = src ~= 0 and Siku.cache.getCurrentCharacter(src) or nil
  local isPrimary <const> = role.is_primary == 1 or role.is_primary == true
  local removed = false

  if isPrimary and holdsRole(character.id, roleName) then
    Siku.Notification(targetSession, {
      type = 'info',
      title = T('permissions_command_title'),
      description = T('permissions_already_own_role', roleName),
    })

    if src ~= 0 and src ~= targetSession then
      Siku.Notification(src, {
        type = 'info',
        title = T('permissions_command_title'),
        description = T('permissions_already_has_role', roleName),
      })
    end

    return
  end

  if isPrimary then
    Siku.permissions.assignRole(character.id, roleName, nil, performedBy and performedBy.id or nil)
  elseif holdsRole(character.id, roleName) then
    Siku.permissions.revokeRole(character.id, roleName, performedBy and performedBy.id or nil)
    removed = true
  else
    Siku.permissions.assignRole(character.id, roleName, nil, performedBy and performedBy.id or nil)
  end

  Siku.RefreshCommandSuggestions(targetSession)

  local messageKey <const> = removed and 'permissions_role_removed' or 'permissions_role_applied'
  local message <const> = T(messageKey, roleName, character.id)

  Siku.print.info(message)

  if src ~= 0 then
    Siku.Notification(src, {
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
