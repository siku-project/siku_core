--- Builds a character instance, attaches it to its cached user, makes it
--- the active one and grants the default role on its first entrance.
---@param sessionId number The player server ID.
---@param characterData table The character row from the database.
---@return nil
local function handleCreateCharacterInstance(sessionId, characterData)
  if type(sessionId) ~= 'number' or type(characterData) ~= 'table' then
    Siku.log.error('lifecycle.character_payload_invalid', T('lifecycle_invalid_payload'), {
      sessionType = type(sessionId),
      payloadType = type(characterData),
    })
    return
  end

  if not characterData.id or not characterData.user_id then
    Siku.log.error('lifecycle.character_data_incomplete', T('lifecycle_incomplete_data', sessionId), {
      characterId = characterData.id,
      userId = characterData.user_id,
      dropped = true,
    }, { source = sessionId, entities = { { type = 'player', id = sessionId, role = 'subject' } } })
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  local user <const> = Siku.cache.getPlayer(sessionId)

  if not user then
    Siku.log.error('lifecycle.user_not_cached', T('lifecycle_no_cached_user', sessionId), {
      characterId = characterData.id,
      userId = characterData.user_id,
      dropped = true,
    }, { source = sessionId, entities = { { type = 'player', id = sessionId, role = 'subject' } } })
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  local character <const> = Siku.Character.new(sessionId, characterData)

  if not user:addCharacter(character) then
    Siku.log.error('lifecycle.character_cache_failed', T('lifecycle_character_cache_failed', character.id, sessionId), {
      characterId = character.id,
      userId = characterData.user_id,
    }, { source = sessionId, entities = { { type = 'character', id = character.id, role = 'subject', session = sessionId } } })
    return
  end

  Siku.cache.releaseCurrentCharacter(sessionId)
  Siku.cache.setCurrentCharacter(sessionId, character.id)

  if not Siku.permissions.getPrimaryRole(character.id) then
    Siku.permissions.assignRole(character.id, PermissionSeedConfig.defaultRole)
  end

  character:publish()
  Siku.command.refreshSuggestions(sessionId)

  Siku.log.debug('lifecycle.character_activated', ('Character %d active for session %d'):format(character.id, sessionId), {
    characterId = character.id,
    userId = characterData.user_id,
  }, { source = sessionId, entities = { { type = 'character', id = character.id, role = 'subject', session = sessionId } } })
end

AddEventHandler('siku:server:createCharacterInstance', handleCreateCharacterInstance)
