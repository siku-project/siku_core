local DROP_REASONS <const> = {
  [1] = 'resource', [2] = 'client', [3] = 'server', [4] = 'client_replaced', [5] = 'client_timeout',
  [6] = 'server_timeout', [7] = 'server_shutdown', [8] = 'state_bag_rate_limit', [9] = 'net_event_rate_limit',
  [10] = 'latent_net_event_rate_limit', [11] = 'command', [12] = 'one_sync_too_many_missed_frames', [13] = 'net_game_event',
}
local UNKNOWN_NAME <const> = 'Unknown'

local internal <const> = _SikuInternal.log
local settings <const> = internal.settings

local sessions <const> = {}

local function identifiers(sessionId)
  local all <const> = Siku.player.getIdentifiers(sessionId)
  local out <const> = {}

  for i = 1, #settings.identifiers do
    local key <const> = settings.identifiers[i]

    out[key] = all[key]
  end

  return out
end

local function playerEntity(sessionId, name)
  return { type = 'player', id = sessionId, role = 'actor', label = name }
end

local function population(sessionId, present)
  local players <const> = GetPlayers()
  local key <const> = tostring(sessionId)
  local online = #players
  local listed = false

  for i = 1, #players do
    if players[i] == key then
      listed = true
      break
    end
  end

  if present and not listed then
    online = online + 1
  elseif not present and listed then
    online = online - 1
  end

  local capacity <const> = GetConvarInt('sv_maxclients', 0)

  return online, capacity > 0 and capacity or nil
end

local function rememberedEntities(session, sessionId)
  local out <const> = {}

  if session.characterId then
    out[#out + 1] = { type = 'character', id = session.characterId, role = 'actor', label = session.characterName, session = sessionId }
  end

  if session.userId then
    out[#out + 1] = { type = 'user', id = session.userId, role = 'actor', label = session.name, session = sessionId }
  end

  return out
end

local function droppedEntities(sessionId, session, name)
  if internal.snapshot(sessionId) then
    return internal.sessionEntities(sessionId, 'actor', name)
  end

  local remembered <const> = session and rememberedEntities(session, sessionId) or {}

  if #remembered == 0 then
    remembered[1] = playerEntity(sessionId, name)
  end

  return remembered
end

AddEventHandler('onResourceStart', function(resource)
  if resource == internal.CORE then
    return
  end

  Siku.log.system('resource.started', {
    message = ('Resource %s started'):format(resource),
    entities = { internal.resourceEntity(resource) },
    data = { version = GetResourceMetadata(resource, 'version', 0) },
  })
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == internal.CORE then
    Siku.log.system('core.stopping', { message = 'siku_core is stopping' })
    Siku.log.flush()
    return
  end

  Siku.log.system('resource.stopped', {
    message = ('Resource %s stopped'):format(resource),
    entities = { internal.resourceEntity(resource) },
  })
end)

AddEventHandler('playerJoining', function(oldId)
  local sessionId <const> = source
  local name <const> = GetPlayerName(tostring(sessionId)) or UNKNOWN_NAME

  local online <const>, capacity <const> = population(sessionId, true)

  sessions[sessionId] = { joinedAt = Siku.log.now(), name = name }

  Siku.log.system('player.joined', {
    message = ('%s joined'):format(name),
    source = sessionId,
    entities = { playerEntity(sessionId, name) },
    data = { identifiers = identifiers(sessionId), temporaryId = tonumber(oldId), online = online, capacity = capacity },
  })
end)

AddEventHandler('siku:server:createUserInstance', function(sessionId, userData)
  local session <const> = sessions[sessionId]

  if session and type(userData) == 'table' then
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
  local name <const> = GetPlayerName(tostring(sessionId)) or (session and session.name) or UNKNOWN_NAME
  local online <const>, capacity <const> = population(sessionId, false)

  sessions[sessionId] = nil

  Siku.log.system('player.dropped', {
    message = ('%s left: %s'):format(name, tostring(reason)),
    source = sessionId,
    entities = droppedEntities(sessionId, session, name),
    data = {
      reason = tostring(reason),
      cause = DROP_REASONS[tonumber(dropReason) or 0] or 'unknown',
      byResource = resourceName,
      sessionSeconds = session and math.floor((Siku.log.now() - session.joinedAt) / 1000) or nil,
      identifiers = identifiers(sessionId),
      online = online,
      capacity = capacity,
    },
  })
end)

function internal.announceReady()
  Siku.log.system('core.ready', {
    message = 'siku_core is ready',
    data = { version = GetResourceMetadata(internal.CORE, 'version', 0), players = Siku.cache.getPlayerCount() },
  })
end
