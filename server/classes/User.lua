---@class SikuUser
---@field id number The database user id.
---@field sessionId number The player's server id.
---@field license string The player's Rockstar license.
---@field discordId string The player's Discord id.
---@field identifiers table All of the player's identifiers.
---@field characters table The user's characters, indexed by their id.
---@field currentCharacter? table The currently active character.
---@field isOnline boolean Whether the user is currently online.
---@field lastSeen number Timestamp of the last activity.
---@field lastPlayedCharacter? number The id of the last played character.
---@field totalPlaytime number Total playtime across every character, in seconds.
---@field createdAt? string Timestamp of when the user was created.
local User = Siku.class('User')

--- Builds a user from its database row.
---@param sessionId number The player's server id.
---@param data table The user row { id, license, discord_id, last_played_character, total_playtime, created_at }.
function User:constructor(sessionId, data)
  self.id = data.id
  self.sessionId = sessionId
  self.license = data.license
  self.discordId = data.discord_id
  self.identifiers = Siku.player.getIdentifiers(sessionId)
  self.characters = {}
  self.currentCharacter = nil
  self.isOnline = true
  self.lastSeen = os.time()
  self.lastPlayedCharacter = data.last_played_character
  self.totalPlaytime = data.total_playtime or 0
  self.createdAt = data.created_at
end

--- Gets a specific identifier by type.
---@param identifierType string The identifier type (license, steam, discord, ...).
---@return string? identifier The identifier value, or nil when absent.
function User:getIdentifier(identifierType)
  return self.identifiers[identifierType]
end

--- Gets a character owned by the user.
---@param charId number The character id.
---@return table? character The character, or nil when absent.
function User:getCharacter(charId)
  return self.characters[charId]
end

--- Checks whether the user owns a character.
---@param charId number The character id.
---@return boolean exists Whether the character exists.
function User:hasCharacter(charId)
  return self.characters[charId] ~= nil
end

--- Counts the user's characters.
---@return number count The number of characters.
function User:getCharacterCount()
  local count = 0

  for _ in pairs(self.characters) do
    count = count + 1
  end

  return count
end

--- Adds a character to the user.
---@param character table The character object, carrying an id.
---@return boolean success Whether the character was added.
function User:addCharacter(character)
  if type(character) ~= 'table' or not character.id then
    return false
  end

  if self.characters[character.id] then
    return false
  end

  self.characters[character.id] = character

  return true
end

--- Removes a character from the user, clearing it when it was active.
---@param charId number The character id to remove.
---@return boolean success Whether the character was removed.
function User:removeCharacter(charId)
  if not self.characters[charId] then
    return false
  end

  if self.currentCharacter and self.currentCharacter.id == charId then
    self.currentCharacter = nil
  end

  self.characters[charId] = nil

  return true
end

--- Sets the active character.
---@param charId number The character id to activate.
---@return boolean success Whether the character was found and activated.
function User:setCurrentCharacter(charId)
  local character <const> = self.characters[charId]

  if not character then
    return false
  end

  self.currentCharacter = character
  self.lastPlayedCharacter = charId

  return true
end

--- Clears the active character.
---@return nil
function User:clearCurrentCharacter()
  self.currentCharacter = nil
end

--- Triggers a client event on this user's client.
---@param eventName string The event name.
---@vararg any Extra arguments forwarded to the event.
---@return nil
function User:triggerEvent(eventName, ...)
  TriggerClientEvent(eventName, self.sessionId, ...)
end

--- Sets the online status, stamping the last-seen time when going offline.
---@param status boolean The new online status.
---@return nil
function User:setOnline(status)
  self.isOnline = status

  if not status then
    self.lastSeen = os.time()
  end
end

--- Updates the last-seen timestamp to now.
---@return nil
function User:updateLastSeen()
  self.lastSeen = os.time()
end

--- Recalculates the total playtime from every character.
---@return nil
function User:updateTotalPlaytime()
  local total = 0

  for _, character in pairs(self.characters) do
    if character.getPlaytime then
      total = total + character:getPlaytime()
    end
  end

  self.totalPlaytime = total
end

--- Drops the user from the server.
---@param reason? string The disconnect reason.
---@return nil
function User:drop(reason)
  if not self.isOnline then
    return
  end

  DropPlayer(tostring(self.sessionId), reason or 'Disconnected by server')
  self.isOnline = false
  self.lastSeen = os.time()
end

--- Serializes the user to a plain table.
---@return table data The serialized user.
function User:toJSON()
  return {
    id = self.id,
    sessionId = self.sessionId,
    license = self.license,
    discordId = self.discordId,
    isOnline = self.isOnline,
    lastSeen = self.lastSeen,
    lastPlayedCharacter = self.lastPlayedCharacter,
    totalPlaytime = self.totalPlaytime,
    characterCount = self:getCharacterCount(),
    currentCharacterId = self.currentCharacter and self.currentCharacter.id,
    createdAt = self.createdAt,
  }
end

Siku.User = User
