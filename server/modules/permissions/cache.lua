local rolePermissionCache = {}
local characterPermissionCache = {}
local characterRoleCache = {}
local inheritanceDepthCache = {}

--- Resolve all permissions for a role including inherited permissions.
---@param roleId number The role ID.
---@param roles table The roles map { [id] = role }.
---@param rolePermsMap table The role permissions map { [roleId] = { 'perm1', 'perm2' } }.
---@param visited? table Already visited role IDs to prevent circular inheritance.
---@return table perms A set of permissions { ['perm.name'] = true }.
local function resolveRolePermissions(roleId, roles, rolePermsMap, visited)
  visited = visited or {}
  if visited[roleId] then return {} end
  visited[roleId] = true

  local role <const> = roles[roleId]
  if not role then return {} end

  local perms <const> = {}
  local directPerms <const> = rolePermsMap[roleId]
  if directPerms then
    for i = 1, #directPerms do
      perms[directPerms[i]] = true
    end
  end

  if role.inherits_from then
    local parentPerms <const> = resolveRolePermissions(role.inherits_from, roles, rolePermsMap, visited)
    for perm in pairs(parentPerms) do
      perms[perm] = true
    end
  end

  return perms
end

--- Compute the inheritance depth of a role (0 = no parent).
---@param roleId number The role ID.
---@param roles table The roles map.
---@param visited? table Already visited role IDs.
---@return number depth The inheritance depth.
local function computeDepth(roleId, roles, visited)
  visited = visited or {}
  if visited[roleId] then return 0 end
  visited[roleId] = true

  local role <const> = roles[roleId]
  if not role or not role.inherits_from then return 0 end

  return 1 + computeDepth(role.inherits_from, roles, visited)
end

--- Build the role permission and inheritance depth caches.
---@param roles table The roles map { [id] = role }.
---@param rolePermsMap table The role permissions map { [roleId] = { 'perm1', 'perm2' } }.
function _SikuInternal.BuildRoleCache(roles, rolePermsMap)
  rolePermissionCache = {}
  inheritanceDepthCache = {}

  for roleId in pairs(roles) do
    rolePermissionCache[roleId] = resolveRolePermissions(roleId, roles, rolePermsMap)
    inheritanceDepthCache[roleId] = computeDepth(roleId, roles)
  end
end

--- Get cached permissions for a role.
---@param roleId number The role ID.
---@return table perms A set of permissions { ['perm.name'] = true }.
function _SikuInternal.GetRolePermissions(roleId)
  return rolePermissionCache[roleId] or {}
end

--- Get the cached inheritance depth for a role.
---@param roleId number The role ID.
---@return number depth The inheritance depth.
function _SikuInternal.GetRoleDepth(roleId)
  return inheritanceDepthCache[roleId] or 0
end

--- Get cached permissions for a character.
---@param charId number The character ID.
---@return table|nil perms The permission set or nil if not cached.
function _SikuInternal.GetCharacterPermissions(charId)
  return characterPermissionCache[charId]
end

--- Set cached permissions for a character.
---@param charId number The character ID.
---@param perms table The permission set { ['perm.name'] = true }.
function _SikuInternal.SetCharacterPermissions(charId, perms)
  characterPermissionCache[charId] = perms
end

--- Get cached active roles for a character.
---@param charId number The character ID.
---@return table|nil roles A list of role objects or nil if not cached.
function _SikuInternal.GetCharacterRoles(charId)
  return characterRoleCache[charId]
end

--- Set cached active roles for a character.
---@param charId number The character ID.
---@param roles table A list of role objects.
function _SikuInternal.SetCharacterRoles(charId, roles)
  characterRoleCache[charId] = roles
end

--- Invalidate the role and permission cache for a character.
---@param charId number The character ID.
function _SikuInternal.InvalidateCharacter(charId)
  characterPermissionCache[charId] = nil
  characterRoleCache[charId] = nil
end

--- Invalidate the role and permission cache for all characters.
function _SikuInternal.InvalidateAllCharacters()
  characterPermissionCache = {}
  characterRoleCache = {}
end
