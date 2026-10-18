local CORE <const> = 'siku_core'
local DEFAULT_BUFFER_RECORDS <const> = 20000
local MIN_BUFFER_RECORDS <const> = 100
local DEFAULT_BUFFER_BYTES <const> = 16 * 1024 * 1024
local MIN_BUFFER_BYTES <const> = 64 * 1024
local DEFAULT_DATA_BYTES <const> = 16 * 1024
local RECORD_OVERHEAD <const> = 4
local DEFAULT_PER_SECOND <const> = 30
local DEFAULT_BURST <const> = 90
local DEFAULT_BYTES_PER_SECOND <const> = 32 * 1024
local MIN_BYTES_PER_SECOND <const> = 1024

local config <const> = Siku.config.log
local limits <const> = config.limits or {}
local client <const> = config.client or {}
local identity <const> = config.identity or {}
local perSecond <const> = math.max(tonumber(client.perSecond) or DEFAULT_PER_SECOND, 1)

_SikuInternal.log = {
  CORE = CORE,
  settings = {
    bufferRecords = math.max(tonumber(config.bufferRecords) or DEFAULT_BUFFER_RECORDS, MIN_BUFFER_RECORDS),
    bufferBytes = math.max(tonumber(config.bufferBytes) or DEFAULT_BUFFER_BYTES, MIN_BUFFER_BYTES),
    recordBytes = (tonumber(limits.data) or DEFAULT_DATA_BYTES) * RECORD_OVERHEAD,
    token = type(config.token) == 'string' and config.token or '',
    identifiers = identity.identifiers or {},
    perSecond = perSecond,
    burst = math.max(tonumber(client.burst) or DEFAULT_BURST, perSecond),
    bytesPerSecond = math.max(tonumber(client.bytesPerSecond) or DEFAULT_BYTES_PER_SECOND, MIN_BYTES_PER_SECOND),
  },
}

local internal <const> = _SikuInternal.log

function internal.snapshot(sessionId)
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

function internal.sessionEntities(sessionId, role, fallbackLabel)
  local snapshot <const> = internal.snapshot(sessionId)
  local out <const> = {}

  if snapshot and snapshot.characterId then
    out[#out + 1] = { type = 'character', id = snapshot.characterId, role = role, label = snapshot.characterName, session = sessionId }
  end

  if snapshot and snapshot.userId then
    out[#out + 1] = { type = 'user', id = snapshot.userId, role = role, label = snapshot.name, session = sessionId }
  end

  if #out == 0 then
    out[1] = { type = 'player', id = sessionId, role = role, label = GetPlayerName(tostring(sessionId)) or fallbackLabel }
  end

  return out
end

function internal.resourceEntity(name)
  return { type = 'resource', id = name, role = 'subject', label = name }
end
