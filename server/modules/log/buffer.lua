local COMPACT_AT <const> = 4096

local config <const> = Siku.config.log
local maxRecords <const> = math.max(tonumber(config.bufferRecords) or 20000, 100)
local maxBytes <const> = math.max(tonumber(config.bufferBytes) or 16777216, 65536)

_SikuInternal.log = _SikuInternal.log or {}

local service <const> = _SikuInternal.log
local boot <const> = Siku.math.randomHex(16)
local startedAt <const> = GetGameTimer()

local entries = {}
local first = 1
local last = 0
local firstSeq = 1
local seq = 0
local bytes = 0
local dropped = 0
local received = 0

local function compact()
  if first <= COMPACT_AT then
    return
  end

  local moved <const> = {}
  local n = 0

  for i = first, last do
    n = n + 1
    moved[n] = entries[i]
  end

  entries = moved
  first = 1
  last = n
end

local function evict()
  while last >= first and ((last - first + 1) > maxRecords or bytes > maxBytes) do
    bytes = bytes - #entries[first]
    entries[first] = nil
    first = first + 1
    firstSeq = firstSeq + 1
    dropped = dropped + 1
  end
end

function service.push(encoded)
  seq = seq + 1
  received = received + 1
  last = last + 1
  entries[last] = encoded
  bytes = bytes + #encoded

  if last - first + 1 == 1 then
    firstSeq = seq
  end

  evict()
end

function service.ack(cursor)
  if type(cursor) ~= 'number' or cursor < firstSeq then
    return
  end

  local target <const> = math.min(cursor, seq)

  while last >= first and firstSeq <= target do
    bytes = bytes - #entries[first]
    entries[first] = nil
    first = first + 1
    firstSeq = firstSeq + 1
  end

  compact()
end

function service.pull(cursor, limit)
  local from = first

  if type(cursor) == 'number' and cursor >= firstSeq then
    from = first + (cursor - firstSeq) + 1
  end

  local slice <const> = {}
  local count = 0
  local nextSeq = type(cursor) == 'number' and math.max(cursor, firstSeq - 1) or firstSeq - 1

  for i = from, last do
    if count >= limit then
      break
    end

    count = count + 1
    slice[count] = entries[i]
    nextSeq = firstSeq + (i - first)
  end

  local pending <const> = math.max(last - (from + count) + 1, 0)

  return slice, nextSeq, pending
end

function service.state()
  return {
    boot = boot,
    seq = seq,
    buffered = last >= first and (last - first + 1) or 0,
    bytes = bytes,
    dropped = dropped,
    received = received,
    uptimeMs = GetGameTimer() - startedAt,
  }
end

function service.boot()
  return boot
end
