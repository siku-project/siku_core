--- Builds a user instance and registers it in the player cache.
---@param sessionId number The player server ID.
---@param userData table The user row { id, license, discord_id, last_played_character, total_playtime, created_at }.
---@return nil
local function handleCreateUserInstance(sessionId, userData)
  if type(sessionId) ~= 'number' or type(userData) ~= 'table' then
    Siku.print.error(T('lifecycle_invalid_payload'))
    return
  end

  if not userData.id or not userData.license then
    Siku.print.error(T('lifecycle_incomplete_data', sessionId))
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  if Siku.cache.hasPlayer(sessionId) then
    return
  end

  local user <const> = Siku.User.new(sessionId, userData)

  if not Siku.cache.addPlayer(user) then
    Siku.print.error(T('lifecycle_cache_failed', userData.id, sessionId))
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  Siku.print.debug(('User %d cached for session %d'):format(userData.id, sessionId))
  Siku.print.debug(Siku.cache.getPlayer(sessionId):toJSON())
end

--- Persists then clears the cached user of a player leaving the server.
--- Saving comes first: the cache is the only place their state still
--- lives once the player is gone.
---@return nil
local function handlePlayerDropped()
  local sessionId <const> = source
  local user <const> = Siku.cache.getPlayer(sessionId)

  if not user then
    return
  end

  Siku.SavePlayer(sessionId)

  user:setOnline(false)
  Siku.cache.removePlayer(sessionId)
end

AddEventHandler('siku:server:createUserInstance', handleCreateUserInstance)
AddEventHandler('playerDropped', handlePlayerDropped)
