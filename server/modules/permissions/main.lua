local rolesMap = {}
local rolesByName = {}

--- Load all roles from the database into memory.
local function loadRoles()
  rolesMap = {}
  rolesByName = {}

  local rows <const> = MySQL.query.await('SELECT * FROM roles')
  for i = 1, #rows do
    local role <const> = rows[i]
    rolesMap[role.id] = role
    rolesByName[role.name] = role
  end
end

--- Load role-permission mappings from DB and rebuild the permission cache.
local function rebuildPermissionCache()
  local rows <const> = MySQL.query.await('SELECT rp.role_id, p.name FROM role_permissions rp JOIN permissions p ON rp.permission_id = p.id')

  local rolePermsMap <const> = {}
  for i = 1, #rows do
    local row <const> = rows[i]
    if not rolePermsMap[row.role_id] then
      rolePermsMap[row.role_id] = {}
    end
    local arr <const> = rolePermsMap[row.role_id]
    arr[#arr + 1] = row.name
  end

  _SikuInternal.BuildRoleCache(rolesMap, rolePermsMap)
  _SikuInternal.InvalidateAllCharacters()
end

--- Load roles from DB, then rebuild permission cache. Use when roles are created/deleted.
local function loadAndBuildCache()
  loadRoles()
  rebuildPermissionCache()
end

--- Resolve and cache the active roles for a character.
---@param charId number The character ID.
---@return table roles A list of role objects.
local function resolveCharacterRoles(charId)
  local cached <const> = _SikuInternal.GetCharacterRoles(charId)
  if cached then return cached end

  local rows <const> = MySQL.query.await(
    'SELECT role_id FROM character_roles WHERE character_id = ? AND (expires_at IS NULL OR expires_at > NOW())',
    { charId }
  )

  local roles <const> = {}

  for i = 1, #rows do
    local role <const> = rolesMap[rows[i].role_id]
    if role then roles[#roles + 1] = role end
  end

  _SikuInternal.SetCharacterRoles(charId, roles)
  return roles
end

--- Resolve and cache all permissions for a character.
---@param charId number The character ID.
---@return table perms A set of permissions { ['perm.name'] = true }.
local function resolveCharacterPermissions(charId)
  local cached <const> = _SikuInternal.GetCharacterPermissions(charId)
  if cached then return cached end

  local roles <const> = resolveCharacterRoles(charId)
  local perms <const> = {}

  for i = 1, #roles do
    local rolePerms <const> = _SikuInternal.GetRolePermissions(roles[i].id)
    for perm in pairs(rolePerms) do
      perms[perm] = true
    end
  end

  _SikuInternal.SetCharacterPermissions(charId, perms)
  return perms
end

--- Write an entry to the RBAC audit log.
---@param action string The action performed.
---@param targetType string The target type (e.g. 'character', 'role').
---@param targetId string The target identifier.
---@param performedBy? number The character ID of the performer.
---@param details? string Additional details.
local function writeAuditLog(action, targetType, targetId, performedBy, details)
  MySQL.query.await(
    'INSERT INTO rbac_audit_log (action, target_type, target_id, performed_by, details) VALUES (?, ?, ?, ?, ?)',
    { action, targetType, targetId, performedBy, details }
  )
end

--- Initialize the permission system (seed, cache, expired roles cleanup cron).
function _SikuInternal.InitPermissions()
  _SikuInternal.SeedPermissions()
  loadAndBuildCache()

  Siku.cron.create('*/5 * * * *', function()
    local result <const> = MySQL.query.await('DELETE FROM character_roles WHERE expires_at IS NOT NULL AND expires_at < NOW()')
    if result.affectedRows and result.affectedRows > 0 then
      Siku.print.info(('Cleaned %d expired role(s)'):format(result.affectedRows))
      _SikuInternal.InvalidateAllCharacters()
    end
  end)

  Siku.print.success(('RBAC initialized with %d roles'):format(Siku.table.size(rolesMap)))
end

--- Check if a character has a specific permission.
---@param charId number The character ID.
---@param permission string The permission to check.
---@return boolean allowed Whether the character has the permission.
function Siku.permissions.hasPermission(charId, permission)
  local perms <const> = resolveCharacterPermissions(charId)
  return _SikuInternal.MatchPermission(perms, permission)
end

--- Check if a source character can modify a target character (based on role hierarchy depth).
---@param sourceCharId number The source character ID.
---@param targetCharId number The target character ID.
---@return boolean canModify Whether the source outranks the target.
function Siku.permissions.canModify(sourceCharId, targetCharId)
  local sourceRole <const> = Siku.permissions.getPrimaryRole(sourceCharId)
  local targetRole <const> = Siku.permissions.getPrimaryRole(targetCharId)

  if not sourceRole then return false end
  if not targetRole then return true end

  return _SikuInternal.GetRoleDepth(sourceRole.id) > _SikuInternal.GetRoleDepth(targetRole.id)
end

--- Get all active roles for a character.
---@param charId number The character ID.
---@return table roles A list of role tables.
function Siku.permissions.getCharacterRoles(charId)
  return resolveCharacterRoles(charId)
end

--- Get all resolved permissions for a character as a list.
---@param charId number The character ID.
---@return table permissions A list of permission strings.
function Siku.permissions.getCharacterPermissions(charId)
  local perms <const> = resolveCharacterPermissions(charId)
  local result <const> = {}
  for perm in pairs(perms) do
    result[#result + 1] = perm
  end
  return result
end

--- Get the primary role of a character.
---@param charId number The character ID.
---@return table|nil role The primary role or nil.
function Siku.permissions.getPrimaryRole(charId)
  local roles <const> = Siku.permissions.getCharacterRoles(charId)
  for i = 1, #roles do
    if roles[i].is_primary then return roles[i] end
  end
  return nil
end

--- Assign a role to a character.
---@param charId number The character ID.
---@param roleName string The role name.
---@param expiresIn? number Optional expiration in seconds.
---@param performedBy? number The character ID performing the action.
---@return boolean success Whether the role was assigned.
function Siku.permissions.assignRole(charId, roleName, expiresIn, performedBy)
  local role <const> = rolesByName[roleName]
  if not role then return false end

  if role.is_primary then
    local currentPrimary <const> = Siku.permissions.getPrimaryRole(charId)
    if currentPrimary then
      MySQL.query.await('DELETE FROM character_roles WHERE character_id = ? AND role_id = ?', { charId, currentPrimary.id })
    end
  end

  local expiresAt = nil
  if expiresIn then
    expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + expiresIn)
  end

  MySQL.query.await(
    'INSERT INTO character_roles (character_id, role_id, expires_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at)',
    { charId, role.id, expiresAt }
  )

  _SikuInternal.InvalidateCharacter(charId)

  writeAuditLog('role_assigned', 'character', tostring(charId), performedBy,
    ('role=%s%s'):format(roleName, expiresAt and (' expires=' .. expiresAt) or ''))

  return true
end

--- Revoke a role from a character.
---@param charId number The character ID.
---@param roleName string The role name.
---@param performedBy? number The character ID performing the action.
---@return boolean success Whether the role was revoked.
function Siku.permissions.revokeRole(charId, roleName, performedBy)
  local role <const> = rolesByName[roleName]
  if not role then return false end

  local result <const> = MySQL.query.await(
    'DELETE FROM character_roles WHERE character_id = ? AND role_id = ?',
    { charId, role.id }
  )

  if not result.affectedRows or result.affectedRows == 0 then return false end

  _SikuInternal.InvalidateCharacter(charId)

  writeAuditLog('role_revoked', 'character', tostring(charId), performedBy, 'role=' .. roleName)

  return true
end

--- Create a new role.
---@param name string The role name.
---@param label string The display label.
---@param isPrimary boolean Whether this is a primary (hierarchical) role.
---@param inheritsFrom? string The parent role name.
---@param performedBy? number The character ID performing the action.
---@return table|nil role The created role or nil if failed.
function Siku.permissions.createRole(name, label, isPrimary, inheritsFrom, performedBy)
  if rolesByName[name] then return nil end

  local inheritsId = nil
  if inheritsFrom then
    local parent <const> = rolesByName[inheritsFrom]
    if not parent then return nil end
    inheritsId = parent.id
  end

  MySQL.query.await(
    'INSERT INTO roles (name, label, is_primary, inherits_from) VALUES (?, ?, ?, ?)',
    { name, label, isPrimary and 1 or 0, inheritsId }
  )

  loadAndBuildCache()

  writeAuditLog('role_created', 'role', name, performedBy,
    ('label=%s primary=%s inherits=%s'):format(label, tostring(isPrimary), inheritsFrom or 'none'))

  return rolesByName[name]
end

--- Delete a role.
---@param name string The role name.
---@param performedBy? number The character ID performing the action.
---@return boolean success Whether the role was deleted.
function Siku.permissions.deleteRole(name, performedBy)
  local role <const> = rolesByName[name]
  if not role then return false end

  MySQL.query.await('DELETE FROM roles WHERE id = ?', { role.id })

  loadAndBuildCache()

  writeAuditLog('role_deleted', 'role', name, performedBy)

  return true
end

--- Add a permission to a role.
---@param roleName string The role name.
---@param permission string The permission string.
---@param performedBy? number The character ID performing the action.
---@return boolean success Whether the permission was added.
function Siku.permissions.addPermissionToRole(roleName, permission, performedBy)
  if not _SikuInternal.IsValidPermission(permission) then return false end

  local role <const> = rolesByName[roleName]
  if not role then return false end

  local perm = MySQL.single.await('SELECT * FROM permissions WHERE name = ?', { permission })

  if not perm then
    local result <const> = MySQL.query.await('INSERT INTO permissions (name) VALUES (?)', { permission })
    perm = { id = result.insertId, name = permission }
  end

  local existing <const> = MySQL.single.await(
    'SELECT role_id FROM role_permissions WHERE role_id = ? AND permission_id = ?',
    { role.id, perm.id }
  )

  if existing then return false end

  MySQL.query.await('INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)', { role.id, perm.id })

  rebuildPermissionCache()

  writeAuditLog('permission_added', 'role', roleName, performedBy, 'permission=' .. permission)

  return true
end

--- Remove a permission from a role.
---@param roleName string The role name.
---@param permission string The permission string.
---@param performedBy? number The character ID performing the action.
---@return boolean success Whether the permission was removed.
function Siku.permissions.removePermissionFromRole(roleName, permission, performedBy)
  local role <const> = rolesByName[roleName]
  if not role then return false end

  local perm <const> = MySQL.single.await('SELECT * FROM permissions WHERE name = ?', { permission })
  if not perm then return false end

  local result <const> = MySQL.query.await(
    'DELETE FROM role_permissions WHERE role_id = ? AND permission_id = ?',
    { role.id, perm.id }
  )

  if not result.affectedRows or result.affectedRows == 0 then return false end

  rebuildPermissionCache()

  writeAuditLog('permission_removed', 'role', roleName, performedBy, 'permission=' .. permission)

  return true
end

--- Get all roles.
---@return table roles A list of all roles.
function Siku.permissions.getAllRoles()
  local result <const> = {}
  for _, role in pairs(rolesMap) do
    result[#result + 1] = role
  end
  return result
end

--- Get all permissions from the database.
---@return table permissions A list of all permissions.
function Siku.permissions.getAllPermissions()
  return MySQL.query.await('SELECT * FROM permissions')
end

--- Get all permissions for a role by name.
---@param roleName string The role name.
---@return table permissions A list of permission strings.
function Siku.permissions.getRolePermissions(roleName)
  local role <const> = rolesByName[roleName]
  if not role then return {} end

  local perms <const> = _SikuInternal.GetRolePermissions(role.id)
  local result <const> = {}
  for perm in pairs(perms) do
    result[#result + 1] = perm
  end
  return result
end
