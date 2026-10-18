local MAX_QUEUE <const> = 2000
local DROPPED_EVENT <const> = 'log.dropped'
local DROPPED_EVERY_MS <const> = 60000

local settings <const> = internal.settings
local clock <const> = internal.clock

local log <const> = {}
local queue = {}
local queued = 0
local dropped = 0
local droppedAt = 0
local flushPending = false
local deliver = nil

local function flushSoon()
  if flushPending then
    return
  end

  flushPending = true

  SetTimeout(0, function()
    flushPending = false
    log.flush()
  end)
end

local function dropReport(now)
  return {
    k = 'log',
    id = internal.newId(now),
    t = now,
    cat = 'system',
    lvl = internal.LEVELS.warn,
    ev = DROPPED_EVENT,
    res = Siku.name,
    org = internal.origin,
    data = { dropped = dropped },
  }
end

function internal.push(record)
  if queued >= MAX_QUEUE then
    dropped = dropped + 1
    return false
  end

  queued = queued + 1
  queue[queued] = record

  if queued >= settings.batchSize then
    flushSoon()
  end

  return true
end

function internal.queueStats()
  return queued, dropped
end

function internal.startDelivery(transport, flushMs)
  deliver = transport

  Citizen.CreateThreadNow(function()
    while true do
      Wait(flushMs)
      log.flush()
    end
  end)
end

function log.flush()
  if queued == 0 then
    return 0
  end

  local batch <const> = queue
  local count <const> = queued

  queue = {}
  queued = 0

  local now <const> = clock.now()

  if dropped > 0 and now - droppedAt >= DROPPED_EVERY_MS then
    droppedAt = now
    batch[count + 1] = dropReport(now)
    dropped = 0
  end

  if deliver then
    deliver(batch)
  else
    dropped = dropped + #batch
  end

  return count
end

AddEventHandler('onResourceStop', function(resource)
  if resource == Siku.name then
    log.flush()
  end
end)

return log
