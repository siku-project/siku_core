local DROP_REASONS <const> = {
  [1] = 'resource', [2] = 'client', [3] = 'server', [4] = 'client_replaced', [5] = 'client_timeout',
  [6] = 'client_timeout_pending_commands', [7] = 'server_shutdown', [8] = 'state_bag_rate_limit',
  [9] = 'net_event_rate_limit', [10] = 'latent_net_event_rate_limit', [11] = 'command_rate_limit',
  [12] = 'one_sync_too_many_missed_frames', [13] = 'net_game_event_rate_limit',
}
local DROP_KINDS <const> = {
  client = 'quit', client_replaced = 'replaced', client_timeout = 'timeout', client_timeout_pending_commands = 'timeout',
  server_shutdown = 'shutdown', state_bag_rate_limit = 'flood', net_event_rate_limit = 'flood',
  latent_net_event_rate_limit = 'flood', command_rate_limit = 'flood', net_game_event_rate_limit = 'flood',
  one_sync_too_many_missed_frames = 'freeze',
}
local DROP_LABELS <const> = {
  quit = 'left', crash = 'crashed', timeout = 'timed out', freeze = 'stopped responding', kicked = 'was kicked',
  banned = 'was banned', kicked_by_script = 'was dropped', replaced = 'reconnected from elsewhere',
  shutdown = 'left, server shutting down', flood = 'was dropped for network abuse', switched = 'left for another server',
  unknown = 'left',
}
local INTERNAL_DROPPER <const> = '^__cfx_internal:'
local CRASH_PREFIX <const> = '^Game crashed'
local BAN_PREFIX <const> = '^[Bb]ann'
local KICK_PREFIX <const> = '^[Kk]ick'
local SWITCH_REASON <const> = 'Connecting to another server.'
local CLIENT_TIMEOUT_REASON <const> = 'Connection timed out.'
local UNKNOWN_NAME <const> = 'Unknown'

--- Classify a drop into something a human reads at a glance, from what
--- FXServer gives: the drop reason code, the reason text and the dropper.
---@param cause string The normalized drop reason.
---@param reason string The reason text.
---@param resourceName string? The resource that dropped the player, if any.
---@return string kind quit, crash, timeout, freeze, kicked, banned, kicked_by_script, replaced, shutdown, flood, switched or unknown.
local function dropKind(cause, reason, resourceName)
  if reason:match(CRASH_PREFIX) then
    return 'crash'
  end

  if cause == 'client' then
    if reason == SWITCH_REASON then
      return 'switched'
    end

    if reason == CLIENT_TIMEOUT_REASON then
      return 'timeout'
    end

    return 'quit'
  end

  if cause == 'resource' or cause == 'server' then
    if reason:match(BAN_PREFIX) then
      return 'banned'
    end

    if reason:match(KICK_PREFIX) or cause == 'server' then
      return 'kicked'
    end

    return 'kicked_by_script'
  end

  return DROP_KINDS[cause] or 'unknown'
end

local internal <const> = _SikuInternal.log
local settings <const> = internal.settings

local sessions <const> = {}
local startedAt <const> = {}
local bootedAt <const> = GetGameTimer()

local function uptimeSeconds(resource)
  local since <const> = startedAt[resource]

  startedAt[resource] = nil

  return since and math.floor((GetGameTimer() - since) / 1000) or nil
end

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

  startedAt[resource] = GetGameTimer()

  Siku.log.system('resource.started', {
    message = ('Resource %s started'):format(resource),
    entities = { internal.resourceEntity(resource) },
    data = { resource = resource, version = GetResourceMetadata(resource, 'version', 0) },
  })
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == internal.CORE then
    Siku.log.system('core.stopping', {
      message = 'siku_core is stopping',
      data = { version = GetResourceMetadata(internal.CORE, 'version', 0), uptimeSeconds = math.floor((GetGameTimer() - bootedAt) / 1000) },
    })
    Siku.log.flush()
    return
  end

  Siku.log.system('resource.stopped', {
    message = ('Resource %s stopped'):format(resource),
    entities = { internal.resourceEntity(resource) },
    data = { resource = resource, version = GetResourceMetadata(resource, 'version', 0), uptimeSeconds = uptimeSeconds(resource) },
  })
end)

AddEventHandler('playerJoining', function(oldId)
  local sessionId <const> = source
  local name <const> = GetPlayerName(tostring(sessionId)) or UNKNOWN_NAME
  local ids <const> = identifiers(sessionId)
  local user <const> = ids.license and MySQL.single.await(
    'SELECT id, total_playtime, created_at, last_seen, last_played_character FROM users WHERE license = ?',
    { ids.license }
  ) or nil

  local online <const>, capacity <const> = population(sessionId, true)
  local entities <const> = { playerEntity(sessionId, name) }

  if user then
    entities[#entities + 1] = { type = 'user', id = user.id, role = 'actor', label = name, session = sessionId }
  end

  sessions[sessionId] = { joinedAt = Siku.log.now(), name = name, userId = user and user.id or nil }

  Siku.log.system('player.joined', {
    message = ('%s joined%s'):format(name, user and '' or ', first visit'),
    source = sessionId,
    entities = entities,
    data = {
      identifiers = ids,
      temporaryId = tonumber(oldId),
      ping = GetPlayerPing(tostring(sessionId)),
      firstVisit = user == nil,
      userId = user and user.id or nil,
      totalPlaytime = user and user.total_playtime or nil,
      createdAt = user and user.created_at or nil,
      lastSeen = user and user.last_seen or nil,
      lastPlayedCharacter = user and user.last_played_character or nil,
      online = online,
      capacity = capacity,
    },
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
    local rank <const> = characterData.user_id and MySQL.single.await(
      'SELECT SUM(id <= ?) AS position, COUNT(*) AS total FROM characters WHERE user_id = ?',
      { characterData.id, characterData.user_id }
    ) or nil
    local name <const> = session and session.characterName or ('character ' .. tostring(characterData.id))
    local entities <const> = { playerEntity(sessionId, session and session.name or nil) }

    if characterData.user_id then
      entities[#entities + 1] = { type = 'user', id = characterData.user_id, role = 'actor', label = session and session.name or nil, session = sessionId }
    end

    Siku.log.system('character.activated', {
      message = rank and ('%s entered play, character %d of %d'):format(name, tonumber(rank.position) or 0, tonumber(rank.total) or 0) or ('%s entered play'):format(name),
      source = sessionId,
      entities = entities,
      data = {
        characterId = characterData.id,
        userId = characterData.user_id,
        position = rank and tonumber(rank.position) or nil,
        total = rank and tonumber(rank.total) or nil,
      },
    })
  end)
end)

AddEventHandler('playerDropped', function(reason, resourceName, dropReason)
  local sessionId <const> = source
  local session <const> = sessions[sessionId]
  local name <const> = GetPlayerName(tostring(sessionId)) or (session and session.name) or UNKNOWN_NAME
  local online <const>, capacity <const> = population(sessionId, false)
  local text <const> = tostring(reason)
  local cause <const> = DROP_REASONS[tonumber(dropReason) or 0] or 'unknown'
  local dropper <const> = type(resourceName) == 'string' and not resourceName:match(INTERNAL_DROPPER) and resourceName or nil
  local kind <const> = dropKind(cause, text, dropper)
  local sessionSeconds <const> = session and math.floor((Siku.log.now() - session.joinedAt) / 1000) or nil

  sessions[sessionId] = nil

  Siku.log.system('player.dropped', {
    message = ('%s %s%s: %s'):format(name, DROP_LABELS[kind], dropper and (' by ' .. dropper) or '', text),
    source = sessionId,
    entities = droppedEntities(sessionId, session, name),
    data = {
      kind = kind,
      reason = text,
      cause = cause,
      byResource = dropper,
      sessionSeconds = sessionSeconds,
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
