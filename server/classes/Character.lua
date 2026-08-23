local DEFAULT_PED <const> = 'mp_m_freemode_01'

---@class SikuCharacter
---@field id number The database character id.
---@field userId number The owning user id.
---@field sessionId number The player's server id.
---@field pedModel string The ped model name.
---@field isDead boolean Whether the character is dead.
---@field x number The last known X coordinate.
---@field y number The last known Y coordinate.
---@field z number The last known Z coordinate.
---@field heading number The last known heading.
---@field lastPlayed? string Timestamp of the last play session.
---@field createdAt? string Timestamp of character creation.
local Character = Siku.class('Character')

--- Builds a character from its database row.
---@param sessionId number The player's server id.
---@param data table The character row { id, user_id, ped_model, x, y, z, heading, is_dead, playtime, last_played, created_at }.
function Character:constructor(sessionId, data)
  self.id = data.id
  self.userId = data.user_id
  self.sessionId = sessionId
  self.pedModel = data.ped_model or DEFAULT_PED
  self.isDead = data.is_dead or false
  self.lastPlayed = data.last_played
  self.createdAt = data.created_at

  self.x = data.x or 0.0
  self.y = data.y or 0.0
  self.z = data.z or 70.0
  self.heading = data.heading or 0.0

  self.dbPlaytime = data.playtime or 0
  self.sessionStart = os.time()
end

--- Reads the live position from the ped entity, refreshing the stored coordinates.
---@param asVector? boolean Return a vector (true) instead of a plain table (false/nil).
---@param withHeading? boolean Include the heading (vector4, or a table carrying heading).
---@return vector4|vector3|table position The current position.
function Character:getPosition(asVector, withHeading)
  local ped <const> = GetPlayerPed(tostring(self.sessionId))
  local coords <const> = GetEntityCoords(ped)

  self.x = coords.x
  self.y = coords.y
  self.z = coords.z
  self.heading = GetEntityHeading(ped)

  if asVector then
    return withHeading and vector4(self.x, self.y, self.z, self.heading) or coords
  end

  local result = { x = self.x, y = self.y, z = self.z }

  if withHeading then
    result.heading = self.heading
  end

  return result
end

--- Stores a new position and teleports the ped to it.
---@param x number The X coordinate.
---@param y number The Y coordinate.
---@param z number The Z coordinate.
---@param heading number The heading angle.
---@return nil
function Character:setPosition(x, y, z, heading)
  self.x = x
  self.y = y
  self.z = z
  self.heading = heading

  local ped <const> = GetPlayerPed(tostring(self.sessionId))
  SetEntityCoords(ped, x, y, z, false, false, false, false)
  SetEntityHeading(ped, heading)
end

--- Gets the playtime accumulated during the current session.
---@return number seconds The session playtime, in seconds.
function Character:getSessionPlaytime()
  return os.time() - self.sessionStart
end

--- Gets the total playtime (stored total plus the current session).
---@return number seconds The total playtime, in seconds.
function Character:getPlaytime()
  return self.dbPlaytime + self:getSessionPlaytime()
end

--- Folds the session playtime into the stored total and restarts the session timer.
---@return nil
function Character:flushSessionPlaytime()
  self.dbPlaytime = self.dbPlaytime + self:getSessionPlaytime()
  self.sessionStart = os.time()
end

--- Updates the last-played timestamp to now.
---@return nil
function Character:updateLastPlayed()
  self.lastPlayed = os.date('%Y-%m-%d %H:%M:%S') --[[@as string]]
end

--- Checks whether the character holds a permission.
---@param permission string The permission to check.
---@return boolean granted Whether the permission is granted.
function Character:hasPermission(permission)
  return Siku.permissions.hasPermission(self.id, permission)
end

--- Checks whether this character outranks another one.
---@param targetCharId number The target character id.
---@return boolean canModify Whether this character outranks the target.
function Character:canModify(targetCharId)
  return Siku.permissions.canModify(self.id, targetCharId)
end

--- Gets the character's primary role.
---@return table? role The primary role, or nil.
function Character:getPrimaryRole()
  return Siku.permissions.getPrimaryRole(self.id)
end

--- Gets every role held by the character.
---@return table roles The list of roles.
function Character:getRoles()
  return Siku.permissions.getCharacterRoles(self.id)
end

--- Gets every resolved permission of the character.
---@return table permissions The list of permission strings.
function Character:getPermissions()
  return Siku.permissions.getCharacterPermissions(self.id)
end

--- Assigns a role to the character.
---@param roleName string The role name.
---@param expiresIn? number Optional expiration in seconds.
---@param performedBy? number The character id performing the action.
---@return boolean success Whether the role was assigned.
function Character:assignRole(roleName, expiresIn, performedBy)
  return Siku.permissions.assignRole(self.id, roleName, expiresIn, performedBy)
end

--- Revokes a role from the character.
---@param roleName string The role name.
---@param performedBy? number The character id performing the action.
---@return boolean success Whether the role was revoked.
function Character:revokeRole(roleName, performedBy)
  return Siku.permissions.revokeRole(self.id, roleName, performedBy)
end

--- Serializes the character to a plain table.
---@return table data The serialized character.
function Character:toJSON()
  return {
    id = self.id,
    userId = self.userId,
    pedModel = self.pedModel,
    x = self.x,
    y = self.y,
    z = self.z,
    heading = self.heading,
    isDead = self.isDead,
    playtime = self:getPlaytime(),
    sessionPlaytime = self:getSessionPlaytime(),
    lastPlayed = self.lastPlayed,
    createdAt = self.createdAt,
  }
end

Siku.Character = Character
