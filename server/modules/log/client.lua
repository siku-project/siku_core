local BATCH_EVENT <const> = 'siku:log:batch'
local MAX_OFFSET_MS <const> = 60000
local MAX_RECORDS <const> = 50
local MAX_FIELD <const> = 1024
local MAX_KEY <const> = 128
local MAX_DEPTH <const> = 3
local MAX_ENTRIES <const> = 50
local MAX_ENTITIES <const> = 16
local MAX_EVENT <const> = 96
local MAX_OUTCOME <const> = 32
local MAX_MESSAGE <const> = 2048
local MAX_NAME <const> = 256
local MAX_STACK <const> = 4096
local ID_LENGTH <const> = 32
local ENTITY_TYPE <const> = 32
local BYTES_BURST_SECONDS <const> = 3
local DROP_REPORT_MS <const> = 60000

local internal <const> = _SikuInternal.log
local settings <const> = internal.settings
local bytesBurst <const> = settings.bytesPerSecond * BYTES_BURST_SECONDS

local buckets <const> = {}

local function bucket(sessionId)
  local entry = buckets[sessionId]

  if not entry then
    entry = { tokens = settings.burst, bytes = bytesBurst, at = GetGameTimer(), dropped = 0, reportedAt = nil }
    buckets[sessionId] = entry
  end

  return entry
end

local function refill(entry, now)
  local elapsed <const> = (now - entry.at) / 1000

  if elapsed > 0 then
    entry.tokens = math.min(settings.burst, entry.tokens + elapsed * settings.perSecond)
    entry.bytes = math.min(bytesBurst, entry.bytes + elapsed * settings.bytesPerSecond)
    entry.at = now
  end
end

local function text(value, max)
  if type(value) ~= 'string' then
    return nil
  end

  return value:sub(1, max)
end

local function bounded(value, depth)
  local kind <const> = type(value)

  if kind == 'string' then
    return value:sub(1, MAX_FIELD)
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

    if count > MAX_ENTRIES then
      break
    end

    if type(key) == 'string' then
      out[key:sub(1, MAX_KEY)] = bounded(entry, depth + 1)
    elseif type(key) == 'number' then
      out[key] = bounded(entry, depth + 1)
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
      local clean <const> = bounded(entity, 1)

      clean.type = entity.type:sub(1, ENTITY_TYPE):lower()
      clean.session = nil
      out[#out + 1] = clean
    end
  end

  return #out > 0 and out or nil
end

local function normalizeLog(record, receivedAt, batchNow)
  if type(record.ev) ~= 'string' or type(record.t) ~= 'number' then
    return nil
  end

  local offset <const> = math.max(math.min(batchNow - record.t, MAX_OFFSET_MS), 0)
  local out <const> = {
    k = 'log',
    t = receivedAt - offset,
    id = type(record.id) == 'string' and #record.id == ID_LENGTH and record.id or nil,
    ev = record.ev:sub(1, MAX_EVENT),
    lvl = record.lvl,
    cat = 'script',
    out = text(record.out, MAX_OUTCOME),
    msg = text(record.msg, MAX_MESSAGE),
    res = record.res,
    data = bounded(record.data, 0),
    ents = entities(record.ents),
    trace = record.trace,
    span = record.span,
    stack = text(record.stack, MAX_STACK),
  }

  if type(record.loc) == 'table' then
    out.loc = { file = bounded(record.loc.file, 0), line = tonumber(record.loc.line) }
  end

  return out
end

local function normalizeSpan(record, receivedAt, batchNow)
  if type(record.start) ~= 'number' or type(record['end']) ~= 'number' then
    return nil
  end

  local startOffset <const> = math.max(math.min(batchNow * 1000 - record.start, MAX_OFFSET_MS * 1000), 0)
  local duration <const> = math.max(math.min(record['end'] - record.start, MAX_OFFSET_MS * 1000), 0)
  local start <const> = receivedAt * 1000 - startOffset

  return {
    k = 'span',
    start = start,
    ['end'] = start + duration,
    trace = record.trace,
    span = record.span,
    parent = text(record.parent, ID_LENGTH),
    name = text(record.name, MAX_NAME),
    kind = record.kind,
    status = record.status == 'error' and 'error' or 'ok',
    err = text(record.err, MAX_MESSAGE),
    res = record.res,
    attrs = bounded(record.attrs, 1),
  }
end

local function normalize(record, receivedAt, batchNow)
  if type(record) ~= 'table' then
    return nil
  end

  if record.k == 'span' then
    return normalizeSpan(record, receivedAt, batchNow)
  end

  return normalizeLog(record, receivedAt, batchNow)
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

local function intake(sessionId, payload)
  local entry <const> = bucket(sessionId)
  local now <const> = GetGameTimer()
  local records <const> = payload.records
  local count <const> = math.min(#records, MAX_RECORDS)
  local cost <const> = #json.encode(records)

  refill(entry, now)

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
    internal.ingest(accepted, 'client', 'client', sessionId)
  end

  reportDrops(sessionId, entry, now)
end

RegisterNetEvent(BATCH_EVENT, function(payload)
  local sessionId <const> = source

  if type(sessionId) ~= 'number' or sessionId <= 0 or type(payload) ~= 'table' or type(payload.records) ~= 'table' then
    return
  end

  intake(sessionId, payload)
end)

AddEventHandler('playerDropped', function()
  buckets[source] = nil
end)
