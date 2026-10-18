local CORE <const> = 'siku_core'
local DROP_REASONS <const> = {
  [1] = 'resource', [2] = 'client', [3] = 'server', [4] = 'client_replaced', [5] = 'client_timeout',
  [6] = 'server_timeout', [7] = 'server_shutdown', [8] = 'state_bag_rate_limit', [9] = 'net_event_rate_limit',
  [10] = 'latent_net_event_rate_limit', [11] = 'command', [12] = 'one_sync_too_many_missed_frames', [13] = 'net_game_event',
}

_SikuInternal.log = _SikuInternal.log or {}

local config <const> = Siku.config.log
local identityConfig <const> = config.identity or {}
local identifierKeys <const> = identityConfig.identifiers or {}

local sessions <const> = {}

local function identifiers(sessionId)
  local all <const> = Siku.player.getIdentifiers(sessionId)
  local out <const> = {}

  for i = 1, #identifierKeys do
    local key <const> = identifierKeys[i]

    if all[key] then
      out[key] = all[key]
    end
  end

  return out
end

local function playerEntity(sessionId, name)
  return { type = 'player', id = sessionId, role = 'actor', label = name }
end

AddEventHandler('onResourceStart', function(resource)
  if resource == CORE then
    return
  end

  Siku.log.system('resource.started', {
    message = ('Resource %s started'):format(resource),
    entities = { { type = 'resource', id = resource, role = 'subject', label = resource } },
    data = { version = GetResourceMetadata(resource, 'version', 0) },
  })
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == CORE then
    Siku.log.system('core.stopping', { message = 'siku_core is stopping' })
    Siku.log.flush()
    return
  end

  Siku.log.system('resource.stopped', {
    message = ('Resource %s stopped'):format(resource),
    entities = { { type = 'resource', id = resource, role = 'subject', label = resource } },
  })
end)

AddEventHandler('playerJoining', function(oldId)
  local sessionId <const> = source
  local name <const> = GetPlayerName(tostring(sessionId)) or 'Unknown'

  sessions[sessionId] = { joinedAt = Siku.log.now(), name = name }

  Siku.log.system('player.joined', {
    message = ('%s joined'):format(name),
    source = sessionId,
    entities = { playerEntity(sessionId, name) },
    data = { identifiers = identifiers(sessionId), temporaryId = tonumber(oldId) },
  })
end)

AddEventHandler('siku:server:createUserInstance', function(sessionId, userData)
  if type(sessionId) ~= 'number' or type(userData) ~= 'table' then
    return
  end

  local session <const> = sessions[sessionId]

  if session then
    session.userId = userData.id
  end
end)

AddEventHandler('siku:server:createCharacterInstance', function(sessionId, characterData)
  if type(sessionId) ~= 'number' or type(characterData) ~= 'table' or not characterData.id then
    return
  end

  local session <const> = sessions[sessionId]

  if session then
    session.characterId = characterData.id
    session.characterName = ('%s %s'):format(characterData.first_name or '', characterData.last_name or '')
  end

  SetTimeout(0, function()
    Siku.log.system('character.activated', {
      message = ('%s entered play'):format(session and session.characterName or ('character ' .. tostring(characterData.id))),
      source = sessionId,
      entities = { playerEntity(sessionId, session and session.name or nil) },
    })
  end)
end)

AddEventHandler('playerDropped', function(reason, resourceName, dropReason)
  local sessionId <const> = source
  local session <const> = sessions[sessionId]
  local name <const> = GetPlayerName(tostring(sessionId)) or (session and session.name) or 'Unknown'
  local identity <const> = _SikuInternal.log.snapshot(sessionId)
  local entities <const> = {}

  if identity and identity.characterId then
    entities[#entities + 1] = { type = 'character', id = identity.characterId, role = 'actor', label = identity.characterName, session = sessionId }
  elseif session and session.characterId then
    entities[#entities + 1] = { type = 'character', id = session.characterId, role = 'actor', label = session.characterName, session = sessionId }
  end

  if identity and identity.userId then
    entities[#entities + 1] = { type = 'user', id = identity.userId, role = 'actor', label = identity.name, session = sessionId }
  elseif session and session.userId then
    entities[#entities + 1] = { type = 'user', id = session.userId, role = 'actor', label = session.name, session = sessionId }
  end

  if #entities == 0 then
    entities[1] = playerEntity(sessionId, name)
  end

  sessions[sessionId] = nil

  Siku.log.system('player.dropped', {
    message = ('%s left: %s'):format(name, tostring(reason)),
    source = sessionId,
    entities = entities,
    data = {
      reason = tostring(reason),
      cause = DROP_REASONS[tonumber(dropReason) or 0] or 'unknown',
      byResource = resourceName,
      sessionSeconds = session and math.floor((Siku.log.now() - session.joinedAt) / 1000) or nil,
      identifiers = identifiers(sessionId),
    },
  })
end)

_SikuInternal.log.ready = function()
  Siku.log.system('core.ready', {
    message = 'siku_core is ready',
    data = { version = GetResourceMetadata(CORE, 'version', 0), players = Siku.cache.getPlayerCount() },
  })
end
