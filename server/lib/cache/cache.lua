Siku.cache = {}

local players = {}
local licenseIndex = {}
local playerCount = 0

--- Caches a connected player's user, indexing it by session id and by license.
--- The session id and license are read from the user instance itself.
---@param user table A Siku.User instance.
---@return boolean success Whether the user was cached.
function Siku.cache.addPlayer(user)
  if not Siku.IsInstance(user, Siku.User) then
    return false
  end

  local sessionId <const> = user.sessionId

  if players[sessionId] then
    return false
  end

  players[sessionId] = user
  playerCount = playerCount + 1

  if user.license then
    licenseIndex[user.license] = sessionId
  end

  return true
end

--- Removes a cached player, clearing both indexes.
---@param sessionId number The player's server id.
---@return boolean success Whether the player was removed.
function Siku.cache.removePlayer(sessionId)
  local user <const> = players[sessionId]

  if not user then
    return false
  end

  if user.license then
    licenseIndex[user.license] = nil
  end

  players[sessionId] = nil
  playerCount = playerCount - 1

  return true
end

--- Gets a cached user by session id.
---@param sessionId number The player's server id.
---@return table? user The Siku.User instance, or nil.
function Siku.cache.getPlayer(sessionId)
  return players[sessionId]
end

--- Gets a cached user by Rockstar license.
---@param license string The player's license.
---@return table? user The Siku.User instance, or nil.
function Siku.cache.getPlayerByLicense(license)
  local sessionId <const> = licenseIndex[license]

  if not sessionId then
    return nil
  end

  return players[sessionId]
end

--- Gets the active character of a cached player.
---@param sessionId number The player's server id.
---@return table? character The current Siku.Character instance, or nil.
function Siku.cache.getCurrentCharacter(sessionId)
  local user <const> = players[sessionId]

  if not user then
    return nil
  end

  return user.currentCharacter
end

--- Checks whether a player is cached.
---@param sessionId number The player's server id.
---@return boolean cached Whether the player is cached.
function Siku.cache.hasPlayer(sessionId)
  return players[sessionId] ~= nil
end

--- Checks whether a license is cached.
---@param license string The player's license.
---@return boolean cached Whether the license is cached.
function Siku.cache.hasLicense(license)
  return licenseIndex[license] ~= nil
end

--- Gets the number of cached players.
---@return number count The player count.
function Siku.cache.getPlayerCount()
  return playerCount
end

--- Gets every cached user as a list.
---@return table users The list of Siku.User instances.
function Siku.cache.getPlayers()
  local result <const> = {}

  for _, user in pairs(players) do
    result[#result + 1] = user
  end

  return result
end

--- Gets every cached session id as a list.
---@return number[] sessionIds The list of session ids.
function Siku.cache.getSessionIds()
  local result <const> = {}

  for sessionId in pairs(players) do
    result[#result + 1] = sessionId
  end

  return result
end

--- Iterates over every cached player. Returning false from the callback stops early.
---@param callback fun(sessionId: number, user: table): boolean? The visitor.
---@return nil
function Siku.cache.forEach(callback)
  for sessionId, user in pairs(players) do
    if callback(sessionId, user) == false then
      return
    end
  end
end

--- Finds the first cached player matching a predicate.
---@param predicate fun(sessionId: number, user: table): boolean The predicate.
---@return table? user The matching Siku.User instance, or nil.
---@return number? sessionId The matching session id, or nil.
function Siku.cache.findPlayer(predicate)
  for sessionId, user in pairs(players) do
    if predicate(sessionId, user) then
      return user, sessionId
    end
  end

  return nil, nil
end

--- Clears the whole cache.
---@return nil
function Siku.cache.clear()
  players = {}
  licenseIndex = {}
  playerCount = 0
end
