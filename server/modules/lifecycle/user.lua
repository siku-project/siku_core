--- Builds a user instance and registers it in the player cache.
---@param sessionId number The player server ID.
---@param userData table The user row { id, license, discord_id, last_played_character, total_playtime, created_at }.
---@return nil
local function handleCreateUserInstance(sessionId, userData)
  if type(sessionId) ~= 'number' or type(userData) ~= 'table' then
    Siku.log.error('lifecycle.user_payload_invalid', T('lifecycle_invalid_payload'), {
      sessionType = type(sessionId),
      payloadType = type(userData),
    })
    return
  end

  if not userData.id or not userData.license then
    Siku.log.error('lifecycle.user_data_incomplete', T('lifecycle_incomplete_data', sessionId), {
      userId = userData.id,
      hasLicense = userData.license ~= nil,
      dropped = true,
    }, { source = sessionId, entities = { { type = 'player', id = sessionId, role = 'subject' } } })
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  if Siku.cache.hasPlayer(sessionId) then
    return
  end

  local user <const> = Siku.User.new(sessionId, userData)

  if not Siku.cache.addPlayer(user) then
    Siku.log.error('lifecycle.user_cache_failed', T('lifecycle_cache_failed', userData.id, sessionId), {
      userId = userData.id,
      dropped = true,
    }, { source = sessionId, entities = { { type = 'user', id = userData.id, role = 'subject', session = sessionId } } })
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  Siku.log.debug('lifecycle.user_cached', ('User %d cached for session %d'):format(userData.id, sessionId), {
    userId = userData.id,
    lastPlayedCharacter = userData.last_played_character,
    totalPlaytime = userData.total_playtime,
  }, { source = sessionId, entities = { { type = 'user', id = userData.id, role = 'subject', session = sessionId } } })
end

--- Persists then clears the cached user of a player leaving the server.
--- Saving comes first: the cache is the only place their state still
--- lives once the player is gone. The character is released before the
--- cache forgets it, because this handler runs before every consumer's own
--- playerDropped and they could no longer name the character afterwards.
---@return nil
local function handlePlayerDropped()
  local sessionId <const> = source
  local user <const> = Siku.cache.getPlayer(sessionId)

  if not user then
    return
  end

  Siku.persistence.savePlayer(sessionId)
  Siku.cache.releaseCurrentCharacter(sessionId)

  user:setOnline(false)
  Siku.cache.removePlayer(sessionId)
end

AddEventHandler('siku:server:createUserInstance', handleCreateUserInstance)
AddEventHandler('playerDropped', handlePlayerDropped)
