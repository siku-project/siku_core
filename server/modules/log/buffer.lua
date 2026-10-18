local COMPACT_AT <const> = 4096
local BOOT_ID_LENGTH <const> = 16

local internal <const> = _SikuInternal.log
local settings <const> = internal.settings
local boot <const> = Siku.math.randomHex(BOOT_ID_LENGTH)
local startedAt <const> = GetGameTimer()

local entries = {}
local first = 1
local last = 0
local firstSeq = 1
local seq = 0
local bytes = 0
local dropped = 0
local received = 0

local function size()
  if last < first then
    return 0
  end

  return last - first + 1
end

local function forget()
  bytes = bytes - #entries[first]
  entries[first] = nil
  first = first + 1
  firstSeq = firstSeq + 1
end

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
  while last >= first and (size() > settings.bufferRecords or bytes > settings.bufferBytes) do
    forget()
    dropped = dropped + 1
  end
end

function internal.push(encoded)
  seq = seq + 1
  received = received + 1
  last = last + 1

  local stamped <const> = encoded:sub(1, -2) .. ',"seq":' .. seq .. '}'

  entries[last] = stamped
  bytes = bytes + #stamped

  if size() == 1 then
    firstSeq = seq
  end

  evict()
end

function internal.ack(cursor)
  if type(cursor) ~= 'number' or cursor < firstSeq then
    return
  end

  local target <const> = math.min(cursor, seq)

  while last >= first and firstSeq <= target do
    forget()
  end

  compact()
end

function internal.pull(cursor, limit)
  local from = first
  local nextSeq = firstSeq - 1

  if type(cursor) == 'number' and cursor >= firstSeq then
    from = first + (cursor - firstSeq) + 1
    nextSeq = cursor
  end

  local slice <const> = {}
  local count = 0

  for i = from, last do
    if count >= limit then
      break
    end

    count = count + 1
    slice[count] = entries[i]
    nextSeq = firstSeq + (i - first)
  end

  return slice, nextSeq, math.max(last - (from + count) + 1, 0)
end

function internal.state()
  return {
    boot = boot,
    seq = seq,
    buffered = size(),
    bytes = bytes,
    dropped = dropped,
    received = received,
    uptimeMs = GetGameTimer() - startedAt,
  }
end
