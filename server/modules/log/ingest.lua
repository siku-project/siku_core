local MAX_BATCH <const> = 1000
local ID_LENGTH <const> = 32
local ID_FORMAT <const> = '%012x%s'
local ID_RANDOM <const> = 20
local TRACE_ID_LENGTH <const> = 32
local SPAN_ID_LENGTH <const> = 16
local RESOURCE_MAX <const> = 64
local UNKNOWN_RESOURCE <const> = 'unknown'
local DEFAULT_LEVEL <const> = 9
local LEVELS <const> = { [1] = true, [5] = true, [9] = true, [13] = true, [17] = true, [21] = true }
local CATEGORIES <const> = { system = true, script = true, audit = true }

local internal <const> = _SikuInternal.log
local settings <const> = internal.settings

local function isHex(value, length)
  return type(value) == 'string' and #value == length
end

local function declaredResource(record)
  if type(record.res) == 'string' then
    return record.res:sub(1, RESOURCE_MAX)
  end

  return UNKNOWN_RESOURCE
end

local function expandEntities(record)
  local entities <const> = record.ents

  if not entities then
    return
  end

  local out <const> = {}

  for i = 1, #entities do
    local entity <const> = entities[i]
    local sessionId <const> = entity.type == 'player' and tonumber(entity.id) or nil

    if sessionId then
      local expanded <const> = internal.sessionEntities(sessionId, entity.role, entity.label)

      for j = 1, #expanded do
        out[#out + 1] = expanded[j]
      end
    else
      out[#out + 1] = entity
    end
  end

  record.ents = #out > 0 and out or nil
end

local function ensureActor(record, sessionId)
  record.src = sessionId

  local entities <const> = record.ents or {}

  for i = 1, #entities do
    if entities[i].role == 'actor' and entities[i].session == sessionId then
      return
    end
  end

  local actors <const> = internal.sessionEntities(sessionId, 'actor')

  for i = 1, #actors do
    entities[#entities + 1] = actors[i]
  end

  record.ents = entities
end

local function acceptLog(record, resource, origin, declared)
  if type(record.ev) ~= 'string' or type(record.t) ~= 'number' then
    return false
  end

  if not LEVELS[record.lvl] then
    record.lvl = DEFAULT_LEVEL
  end

  if not isHex(record.id, ID_LENGTH) then
    record.id = ID_FORMAT:format(math.max(math.floor(record.t), 0) & 0xFFFFFFFFFFFF, Siku.math.randomHex(ID_RANDOM))
  end

  if not CATEGORIES[record.cat] or (declared and record.cat ~= 'script') then
    record.cat = 'script'
  end

  record.res = declared and declaredResource(record) or resource
  record.org = origin
  record.trust = declared and 'declared' or 'verified'

  if declared then
    record.trace = isHex(record.trace, TRACE_ID_LENGTH) and record.trace or nil
    record.span = isHex(record.span, SPAN_ID_LENGTH) and record.span or nil
  end

  expandEntities(record)

  return true
end

local function acceptSpan(record, resource, origin, declared)
  if not isHex(record.trace, TRACE_ID_LENGTH) or not isHex(record.span, SPAN_ID_LENGTH) then
    return false
  end

  if type(record.start) ~= 'number' or type(record['end']) ~= 'number' or type(record.name) ~= 'string' then
    return false
  end

  record.res = declared and declaredResource(record) or resource
  record.org = origin
  record.trust = declared and 'declared' or 'verified'

  return true
end

local function accept(record, resource, origin, sessionId)
  local declared <const> = origin == 'client'

  if record.k == 'span' then
    return acceptSpan(record, resource, origin, declared)
  end

  record.k = 'log'

  if not acceptLog(record, resource, origin, declared) then
    return false
  end

  if sessionId then
    ensureActor(record, sessionId)
  end

  return true
end

function internal.ingest(batch, resource, origin, sessionId)
  if type(batch) ~= 'table' then
    return 0
  end

  local accepted = 0

  for i = 1, math.min(#batch, MAX_BATCH) do
    local record <const> = batch[i]

    if type(record) == 'table' and accept(record, resource, origin, sessionId) then
      local encoded <const> = json.encode(record)

      if encoded and #encoded <= settings.recordBytes then
        internal.push(encoded)
        accepted = accepted + 1
      end
    end
  end

  return accepted
end

exports('logIngest', function(batch)
  local resource <const> = GetInvokingResource()

  if not resource or resource == internal.CORE then
    return 0
  end

  return internal.ingest(batch, resource, 'server')
end)
