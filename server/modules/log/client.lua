local BATCH_EVENT <const> = 'siku:log:batch'
local MAX_OFFSET_MS <const> = 60000
local MAX_RECORDS <const> = 50
local MAX_FIELD <const> = 1024
local MAX_DEPTH <const> = 3
local MAX_KEYS <const> = 32
local MAX_LIST <const> = 50
local MAX_ENTITIES <const> = 16
local DROP_REPORT_MS <const> = 60000

_SikuInternal.log = _SikuInternal.log or {}

local service <const> = _SikuInternal.log
local config <const> = Siku.config.log
local client <const> = config.client or {}
local perSecond <const> = math.max(tonumber(client.perSecond) or 30, 1)
local burst <const> = math.max(tonumber(client.burst) or 90, perSecond)
local bytesPerSecond <const> = math.max(tonumber(client.bytesPerSecond) or 32768, 1024)
local bytesBurst <const> = bytesPerSecond * 3

local buckets <const> = {}

local function bucket(sessionId)
  local entry = buckets[sessionId]

  if not entry then
    entry = { tokens = burst, bytes = bytesBurst, at = GetGameTimer(), dropped = 0, reportedAt = nil }
    buckets[sessionId] = entry
  end

  return entry
end

local function refill(entry)
  local now <const> = GetGameTimer()
  local elapsed <const> = (now - entry.at) / 1000

  if elapsed > 0 then
    entry.tokens = math.min(burst, entry.tokens + elapsed * perSecond)
    entry.bytes = math.min(bytesBurst, entry.bytes + elapsed * bytesPerSecond)
    entry.at = now
  end
end

local function sized(value, depth)
  local kind <const> = type(value)

  if kind == 'string' then
    return #value <= MAX_FIELD and value or value:sub(1, MAX_FIELD)
  end

  if kind == 'number' or kind == 'boolean' or value == nil then
    return value
  end

  if kind ~= 'table' or depth >= MAX_DEPTH then
    return nil
  end

  local out <const> = {}
  local count = 0

  for key, entry in pairs(value) do
    count = count + 1

    if count > math.max(MAX_KEYS, MAX_LIST) then
      break
    end

    local keyKind <const> = type(key)

    if keyKind == 'string' or keyKind == 'number' then
      out[keyKind == 'string' and key:sub(1, 128) or key] = sized(entry, depth + 1)
    end
  end

  return out
end

local function entities(list)
  if type(list) ~= 'table' then
    return nil
  end

  local out <const> = {}

  for i = 1, math.min(#list, MAX_ENTITIES) do
    local entity <const> = list[i]

    if type(entity) == 'table' and type(entity.type) == 'string' and (type(entity.id) == 'string' or type(entity.id) == 'number') then
      local clean <const> = sized(entity, 1)

      if clean then
        clean.type = entity.type:sub(1, 32):lower()
        clean.session = nil
        out[#out + 1] = clean
      end
    end
  end

  return #out > 0 and out or nil
end

local function normalize(record, receivedAt, batchNow)
  if type(record) ~= 'table' then
    return nil
  end

  local kind <const> = record.k == 'span' and 'span' or 'log'
  local out <const> = { k = kind }

  if kind == 'log' then
    if type(record.ev) ~= 'string' or type(record.t) ~= 'number' then
      return nil
    end

    local offset <const> = math.max(math.min(batchNow - record.t, MAX_OFFSET_MS), 0)

    out.t = receivedAt - offset
    out.id = type(record.id) == 'string' and #record.id == 32 and record.id or nil
    out.ev = record.ev:sub(1, 96)
    out.lvl = record.lvl
    out.cat = 'script'
    out.out = type(record.out) == 'string' and record.out:sub(1, 32) or nil
    out.msg = type(record.msg) == 'string' and record.msg:sub(1, 2048) or nil
    out.res = record.res
    out.data = sized(record.data, 0)
    out.ents = entities(record.ents)
    out.trace = record.trace
    out.span = record.span
    out.stack = type(record.stack) == 'string' and record.stack:sub(1, 4096) or nil

    if type(record.loc) == 'table' then
      out.loc = { file = sized(record.loc.file, 0), line = tonumber(record.loc.line) }
    end

    return out
  end

  if type(record.start) ~= 'number' or type(record['end']) ~= 'number' then
    return nil
  end

  local startOffset <const> = math.max(math.min(batchNow * 1000 - record.start, MAX_OFFSET_MS * 1000), 0)
  local duration <const> = math.max(math.min(record['end'] - record.start, MAX_OFFSET_MS * 1000), 0)

  out.start = receivedAt * 1000 - startOffset
  out['end'] = out.start + duration
  out.trace = record.trace
  out.span = record.span
  out.parent = type(record.parent) == 'string' and record.parent or nil
  out.name = type(record.name) == 'string' and record.name:sub(1, 256) or nil
  out.kind = record.kind
  out.status = record.status == 'error' and 'error' or 'ok'
  out.err = type(record.err) == 'string' and record.err:sub(1, 2048) or nil
  out.res = record.res
  out.attrs = sized(record.attrs, 1)

  return out
end

local function reportDrops(sessionId, entry, now)
  if entry.dropped == 0 or (entry.reportedAt and now - entry.reportedAt < DROP_REPORT_MS) then
    return
  end

  local dropped <const> = entry.dropped

  entry.dropped = 0
  entry.reportedAt = now

  Siku.log.system('log.client_dropped', {
    level = 'warn',
    source = sessionId,
    data = { dropped = dropped },
    entities = { { type = 'player', id = sessionId, role = 'actor' } },
  })
end

RegisterNetEvent(BATCH_EVENT, function(payload)
  local sessionId <const> = source

  if type(sessionId) ~= 'number' or sessionId <= 0 or type(payload) ~= 'table' or type(payload.records) ~= 'table' then
    return
  end

  local entry <const> = bucket(sessionId)
  local now <const> = GetGameTimer()

  refill(entry)

  local records <const> = payload.records
  local count <const> = math.min(#records, MAX_RECORDS)
  local cost <const> = #json.encode(records)

  if entry.bytes < cost then
    entry.dropped = entry.dropped + count
    reportDrops(sessionId, entry, now)
    return
  end

  entry.bytes = entry.bytes - cost

  if type(payload.dropped) == 'number' and payload.dropped > 0 then
    entry.dropped = entry.dropped + math.floor(payload.dropped)
  end

  local batchNow <const> = tonumber(payload.now) or now
  local receivedAt <const> = Siku.log.now()
  local accepted <const> = {}

  for i = 1, count do
    if entry.tokens < 1 then
      entry.dropped = entry.dropped + (count - i + 1)
      break
    end

    local record <const> = normalize(records[i], receivedAt, batchNow)

    if record then
      entry.tokens = entry.tokens - 1
      accepted[#accepted + 1] = record
    end
  end

  if #accepted > 0 then
    service.ingest(accepted, 'client', 'client', sessionId)
  end

  reportDrops(sessionId, entry, now)
end)

AddEventHandler('playerDropped', function()
  buckets[source] = nil
end)
