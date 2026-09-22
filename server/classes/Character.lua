local DEFAULT_PED <const> = 'mp_m_freemode_01'
local DEFAULT_HEIGHT <const> = 175
local STATE_KEY <const> = 'siku:state:character'
local EVENT_DEATH_CHANGED <const> = 'siku:character:deathChanged'
local EVENT_IDENTITY_CHANGED <const> = 'siku:character:identityChanged'
local MAX_NAME_LENGTH <const> = 50
local MAX_BIRTHPLACE_LENGTH <const> = 100
local NATIONALITY_LENGTH <const> = 2
local MIN_HEIGHT <const> = 100
local MAX_HEIGHT <const> = 250
local DATE_PATTERN <const> = '^(%d%d%d%d)%-(%d%d)%-(%d%d)'
local MILLISECONDS <const> = 1000

---@class SikuCharacter
---@field id number The database character id.
---@field userId number The owning user id.
---@field sessionId number The player's server id.
---@field firstName string The first name.
---@field lastName string The last name.
---@field dob string The date of birth, `YYYY-MM-DD`.
---@field gender string The gender, as declared at creation.
---@field height number The height in centimetres.
---@field nationality string The nationality, a two-letter country code.
---@field birthplace string The birthplace.
---@field pedModel string The ped model name.
---@field appearance table? The saved look { heritage, physical, clothing, accessories, tattoos }, nil when none.
---@field isDead boolean Whether the character is dead.
---@field x number The last known X coordinate.
---@field y number The last known Y coordinate.
---@field z number The last known Z coordinate.
---@field heading number The last known heading.
---@field lastPlayed? string Timestamp of the last play session.
---@field createdAt? string Timestamp of character creation.
local Character = Siku.class('Character')

--- Reads a database date as `YYYY-MM-DD`, whether the driver handed a
--- string or a millisecond timestamp.
---@param value any The raw value.
---@return string? date The date, or nil when unreadable.
local function readDate(value)
  if type(value) == 'number' then
    return os.date('%Y-%m-%d', value // MILLISECONDS) --[[@as string]]
  end

  if type(value) == 'string' and value:match(DATE_PATTERN) then
    return value:sub(1, 10)
  end

  return nil
end

--- Decodes a saved appearance, tolerating a table already decoded.
---@param value any The raw column.
---@return table? appearance The look, or nil when none.
local function readAppearance(value)
  if type(value) == 'table' then
    return value
  end

  if type(value) ~= 'string' or value == '' then
    return nil
  end

  local ok <const>, decoded <const> = pcall(json.decode, value)

  return ok and type(decoded) == 'table' and decoded or nil
end

--- Whether a string is usable as a name-like field.
---@param value any The value.
---@param maxLength number The longest accepted.
---@return boolean valid Whether it is a non-empty string within bounds.
local function isText(value, maxLength)
  return type(value) == 'string' and value ~= '' and #value <= maxLength
end

--- Builds a character from its database row.
---@param sessionId number The player's server id.
---@param data table The character row, every column of `characters`.
function Character:constructor(sessionId, data)
  self.id = data.id
  self.userId = data.user_id
  self.sessionId = sessionId

  self.firstName = data.first_name or ''
  self.lastName = data.last_name or ''
  self.dob = readDate(data.dob)
  self.gender = data.gender or ''
  self.height = data.height or DEFAULT_HEIGHT
  self.nationality = data.nationality or ''
  self.birthplace = data.birthplace or ''
  self.pedModel = data.ped_model or DEFAULT_PED
  self.appearance = readAppearance(data.appearance)

  self.isDead = data.is_dead == true or data.is_dead == 1
  self.lastPlayed = data.last_played
  self.createdAt = data.created_at

  self.x = data.x or 0.0
  self.y = data.y or 0.0
  self.z = data.z or 70.0
  self.heading = data.heading or 0.0

  self.dbPlaytime = data.playtime or 0
  self.sessionStart = os.time()
end

--- The first and last name together.
---@return string name The full name.
function Character:getFullName()
  return ('%s %s'):format(self.firstName, self.lastName)
end

--- The age in years, from the date of birth and today's date.
---@return number? age The age, or nil when the date of birth is unknown.
function Character:getAge()
  if not self.dob then
    return nil
  end

  local year <const>, month <const>, day <const> = self.dob:match(DATE_PATTERN)
  local today <const> = os.date('*t')
  local age = today.year - tonumber(year)

  if today.month < tonumber(month) or (today.month == tonumber(month) and today.day < tonumber(day)) then
    age = age - 1
  end

  return math.max(0, age)
end

--- What the character looks like to anyone but the server: the identity
--- and the state a HUD, a target or another player may read, nothing
--- that lets them act on it.
---@return table public { id, firstName, lastName, fullName, gender, dob, age, height, nationality, birthplace, pedModel, isDead }.
function Character:getPublic()
  return {
    id = self.id,
    firstName = self.firstName,
    lastName = self.lastName,
    fullName = self:getFullName(),
    gender = self.gender,
    dob = self.dob,
    age = self:getAge(),
    height = self.height,
    nationality = self.nationality,
    birthplace = self.birthplace,
    pedModel = self.pedModel,
    isDead = self.isDead,
  }
end

--- Replicates the public view on the player's state bag, so the client
--- and every other client read who this character is without asking.
---@return nil
function Character:publish()
  Player(self.sessionId).state:set(STATE_KEY, self:getPublic(), true)
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

--- Changes the identity, the fields given only, and writes it at once:
--- a name is not something a save pass should be trusted to catch up on.
---@param fields table Any of { firstName, lastName, dob, gender, height, nationality, birthplace }.
---@return boolean changed Whether every given field was valid and written.
function Character:setIdentity(fields)
  if type(fields) ~= 'table' then
    return false
  end

  local identity <const> = {
    firstName = fields.firstName or self.firstName,
    lastName = fields.lastName or self.lastName,
    dob = fields.dob and readDate(fields.dob) or self.dob,
    gender = fields.gender or self.gender,
    height = fields.height or self.height,
    nationality = fields.nationality or self.nationality,
    birthplace = fields.birthplace or self.birthplace,
  }

  if not isText(identity.firstName, MAX_NAME_LENGTH) or not isText(identity.lastName, MAX_NAME_LENGTH) then
    return false
  end

  if not identity.dob or not isText(identity.gender, MAX_NAME_LENGTH) then
    return false
  end

  if type(identity.height) ~= 'number' or identity.height < MIN_HEIGHT or identity.height > MAX_HEIGHT then
    return false
  end

  if not isText(identity.nationality, NATIONALITY_LENGTH) or not isText(identity.birthplace, MAX_BIRTHPLACE_LENGTH) then
    return false
  end

  MySQL.update.await(
    'UPDATE characters SET first_name = ?, last_name = ?, dob = ?, gender = ?, height = ?, nationality = ?, birthplace = ? WHERE id = ?',
    { identity.firstName, identity.lastName, identity.dob, identity.gender, identity.height, identity.nationality, identity.birthplace, self.id }
  )

  self.firstName = identity.firstName
  self.lastName = identity.lastName
  self.dob = identity.dob
  self.gender = identity.gender
  self.height = identity.height
  self.nationality = identity.nationality
  self.birthplace = identity.birthplace

  self:publish()
  TriggerEvent(EVENT_IDENTITY_CHANGED, self.sessionId, self.id, self:getPublic())

  return true
end

--- Changes the ped model, written at once.
---@param model string The ped model name.
---@return boolean changed Whether the model was accepted.
function Character:setPedModel(model)
  if not isText(model, MAX_NAME_LENGTH) then
    return false
  end

  MySQL.update.await('UPDATE characters SET ped_model = ? WHERE id = ?', { model, self.id })
  self.pedModel = model
  self:publish()

  return true
end

--- Replaces the saved look, written at once.
---@param appearance table? The look { heritage, physical, clothing, accessories, tattoos }, nil to clear it.
---@return boolean changed Whether the look was accepted.
function Character:setAppearance(appearance)
  if appearance ~= nil and type(appearance) ~= 'table' then
    return false
  end

  MySQL.update.await(
    'UPDATE characters SET appearance = ? WHERE id = ?',
    { appearance and json.encode(appearance) or nil, self.id }
  )

  self.appearance = appearance

  return true
end

--- Marks the character dead or alive, written at once and told to
--- everyone: the state bag for the clients, a local event for the
--- server resources that pause, close or revive something on it.
---@param dead boolean Whether the character is dead.
---@return boolean changed Whether the state moved.
function Character:setDead(dead)
  local value <const> = dead == true

  if self.isDead == value then
    return false
  end

  self.isDead = value

  MySQL.update.await('UPDATE characters SET is_dead = ? WHERE id = ?', { value and 1 or 0, self.id })

  self:publish()
  TriggerEvent(EVENT_DEATH_CHANGED, self.sessionId, self.id, value)

  return true
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

--- Serializes the character to a plain table, the look left out since it
--- is large and has its own field.
---@return table data The serialized character.
function Character:toJSON()
  return {
    id = self.id,
    userId = self.userId,
    firstName = self.firstName,
    lastName = self.lastName,
    fullName = self:getFullName(),
    dob = self.dob,
    age = self:getAge(),
    gender = self.gender,
    height = self.height,
    nationality = self.nationality,
    birthplace = self.birthplace,
    pedModel = self.pedModel,
    hasAppearance = self.appearance ~= nil,
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
