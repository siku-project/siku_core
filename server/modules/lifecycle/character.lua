--- Builds a character instance, attaches it to its cached user, makes it
--- the active one and grants the default role on its first entrance.
---@param sessionId number The player server ID.
---@param characterData table The character row from the database.
---@return nil
local function handleCreateCharacterInstance(sessionId, characterData)
  if type(sessionId) ~= 'number' or type(characterData) ~= 'table' then
    Siku.print.error(T('lifecycle_invalid_payload'))
    return
  end

  if not characterData.id or not characterData.user_id then
    Siku.print.error(T('lifecycle_incomplete_data', sessionId))
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  local user <const> = Siku.cache.getPlayer(sessionId)

  if not user then
    Siku.print.error(T('lifecycle_no_cached_user', sessionId))
    DropPlayer(tostring(sessionId), T('lifecycle_setup_failed'))
    return
  end

  local character <const> = Siku.Character.new(sessionId, characterData)

  if not user:addCharacter(character) then
    Siku.print.error(T('lifecycle_character_cache_failed', character.id, sessionId))
    return
  end

  user:setCurrentCharacter(character.id)

  if not Siku.permissions.getPrimaryRole(character.id) then
    Siku.permissions.assignRole(character.id, PermissionSeedConfig.defaultRole)
  end

  Siku.print.debug(('Character %d active for session %d'):format(character.id, sessionId))
end

AddEventHandler('siku:server:createCharacterInstance', handleCreateCharacterInstance)
