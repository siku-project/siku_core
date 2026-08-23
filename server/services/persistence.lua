Siku.persistence = {}

--- Refreshes the cached character with everything the world still
--- knows about it. Runs without yielding: a leaving player loses their
--- ped within a frame, so the cache must be filled before any query.
---@param sessionId number The player server ID.
---@return table|nil user, table|nil character The cached user and its active character.
local function captureIntoCache(sessionId)
  local user <const> = Siku.cache.getPlayer(sessionId)

  if not user then
    return nil, nil
  end

  user:updateLastSeen()

  local character <const> = user.currentCharacter

  if not character then
    return user, nil
  end

  local ped <const> = GetPlayerPed(tostring(sessionId))

  if ped and ped ~= 0 and DoesEntityExist(ped) then
    local coords <const> = GetEntityCoords(ped)

    character.x = coords.x
    character.y = coords.y
    character.z = coords.z
    character.heading = GetEntityHeading(ped)
  end

  character:flushSessionPlaytime()
  character:updateLastPlayed()
  user:updateTotalPlaytime()

  return user, character
end

--- Writes a cached character back to the database.
---@param character table The cached character.
---@return nil
local function writeCharacter(character)
  MySQL.update.await(
    'UPDATE characters SET x = ?, y = ?, z = ?, heading = ?, playtime = ?, is_dead = ?, last_played = CURRENT_TIMESTAMP WHERE id = ?',
    {
      character.x,
      character.y,
      character.z,
      character.heading,
      character:getPlaytime(),
      character.isDead and 1 or 0,
      character.id,
    }
  )
end

--- Writes a cached user back to the database.
---@param user table The cached user.
---@return nil
local function writeUser(user)
  MySQL.update.await(
    'UPDATE users SET last_played_character = ?, total_playtime = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ?',
    { user.lastPlayedCharacter, user.totalPlaytime, user.id }
  )
end

--- Captures a player's live state into the cache, then persists the
--- cache to the database. Safe to call for a player who already left.
---@param sessionId number The player server ID.
---@return boolean saved Whether something was written.
function Siku.persistence.savePlayer(sessionId)
  local user <const>, character <const> = captureIntoCache(sessionId)

  if not user then
    return false
  end

  if character then
    writeCharacter(character)
  end

  writeUser(user)

  return true
end

--- Saves every cached player — the autosave pass, and the sweep run
--- when the core stops.
---@return number saved The number of players written.
function Siku.persistence.saveAll()
  local sessionIds <const> = Siku.cache.getSessionIds()
  local saved = 0

  for i = 1, #sessionIds do
    if Siku.persistence.savePlayer(sessionIds[i]) then
      saved = saved + 1
    end
  end

  return saved
end
