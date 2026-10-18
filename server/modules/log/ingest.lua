local CORE <const> = 'siku_core'
local MAX_BATCH <const> = 1000
local TRUST_VERIFIED <const> = 'verified'
local TRUST_DECLARED <const> = 'declared'
local PLAYER <const> = 'player'
local CHARACTER <const> = 'character'
local USER <const> = 'user'
local ACTOR <const> = 'actor'
local ID_FORMAT <const> = '%012x%s'

_SikuInternal.log = _SikuInternal.log or {}

local service <const> = _SikuInternal.log
local config <const> = Siku.config.log
local limits <const> = config.limits or {}
local levels <const> = { [1] = true, [5] = true, [9] = true, [13] = true, [17] = true, [21] = true }
local categories <const> = { system = true, script = true, audit = true }
local sizeLimit <const> = (limits.data or 16384) * 4

local function snapshot(sessionId)
  local user <const> = Siku.cache.getPlayer(sessionId)

  if not user then
    return nil
  end

  local character <const> = user.currentCharacter

  return {
    userId = user.id,
    name = user.name,
    characterId = character and character.id or nil,
    characterName = character and character:getFullName() or nil,
  }
end

service.snapshot = snapshot

local function expandPlayer(entity, out)
  local sessionId <const> = tonumber(entity.id)

  if not sessionId then
    return
  end

  local identity <const> = snapshot(sessionId)
  local role <const> = entity.role

  if identity and identity.characterId then
    out[#out + 1] = { type = CHARACTER, id = identity.characterId, role = role, label = identity.characterName, session = sessionId }
  end

  if identity and identity.userId then
    out[#out + 1] = { type = USER, id = identity.userId, role = role, label = identity.name, session = sessionId }
  end

  if not identity then
    out[#out + 1] = { type = PLAYER, id = sessionId, role = role, label = GetPlayerName(tostring(sessionId)) or entity.label }
  end
end

local function resolveEntities(record)
  local entities <const> = record.ents

  if not entities then
    return
  end

  local out <const> = {}

  for i = 1, #entities do
    local entity <const> = entities[i]

    if entity.type == PLAYER then
      expandPlayer(entity, out)
    else
      out[#out + 1] = entity
    end
  end

  record.ents = #out > 0 and out or nil
end

local function ensureActor(record, sessionId)
  if not sessionId then
    return
  end

  record.src = sessionId

  local entities = record.ents or {}

  for i = 1, #entities do
    if entities[i].role == ACTOR and entities[i].session == sessionId then
      record.ents = entities
      return
    end
  end

  local identity <const> = snapshot(sessionId)

  if identity and identity.characterId then
    entities[#entities + 1] = { type = CHARACTER, id = identity.characterId, role = ACTOR, label = identity.characterName, session = sessionId }
  end

  if identity and identity.userId then
    entities[#entities + 1] = { type = USER, id = identity.userId, role = ACTOR, label = identity.name, session = sessionId }
  end

  if not identity then
    entities[#entities + 1] = { type = PLAYER, id = sessionId, role = ACTOR, label = GetPlayerName(tostring(sessionId)) }
  end

  record.ents = entities
end

local function acceptLog(record, resource, origin, declared)
  if type(record.ev) ~= 'string' or type(record.t) ~= 'number' then
    return false
  end

  if not levels[record.lvl] then
    record.lvl = 9
  end

  if type(record.id) ~= 'string' or #record.id ~= 32 then
    record.id = ID_FORMAT:format(math.max(math.floor(record.t), 0) & 0xFFFFFFFFFFFF, Siku.math.randomHex(20))
  end

  if not categories[record.cat] or (declared and record.cat ~= 'script') then
    record.cat = 'script'
  end

  record.res = declared and (type(record.res) == 'string' and record.res:sub(1, 64) or 'unknown') or resource
  record.org = origin
  record.trust = declared and TRUST_DECLARED or TRUST_VERIFIED

  if declared then
    record.trace = type(record.trace) == 'string' and #record.trace == 32 and record.trace or nil
    record.span = type(record.span) == 'string' and #record.span == 16 and record.span or nil
  end

  resolveEntities(record)

  return true
end

local function acceptSpan(record, resource, origin, declared)
  if type(record.trace) ~= 'string' or #record.trace ~= 32 or type(record.span) ~= 'string' or #record.span ~= 16 then
    return false
  end

  if type(record.start) ~= 'number' or type(record['end']) ~= 'number' or type(record.name) ~= 'string' then
    return false
  end

  record.res = declared and (type(record.res) == 'string' and record.res:sub(1, 64) or 'unknown') or resource
  record.org = origin
  record.trust = declared and TRUST_DECLARED or TRUST_VERIFIED

  return true
end

function service.ingest(batch, resource, origin, sessionId)
  if type(batch) ~= 'table' then
    return 0
  end

  local declared <const> = origin == 'client'
  local accepted = 0

  for i = 1, math.min(#batch, MAX_BATCH) do
    local record <const> = batch[i]

    if type(record) == 'table' then
      local ok

      if record.k == 'span' then
        ok = acceptSpan(record, resource, origin, declared)
      else
        record.k = 'log'
        ok = acceptLog(record, resource, origin, declared)

        if ok and declared then
          ensureActor(record, sessionId)
        end
      end

      if ok then
        local encoded <const> = json.encode(record)

        if encoded and #encoded <= sizeLimit then
          service.push(encoded)
          accepted = accepted + 1
        end
      end
    end
  end

  return accepted
end

exports('logIngest', function(batch)
  local resource <const> = GetInvokingResource()

  if not resource or resource == CORE then
    return 0
  end

  return service.ingest(batch, resource, 'server')
end)
