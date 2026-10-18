local BATCH_EVENT <const> = 'siku:log:batch'
local CLIENT_FLUSH_MS <const> = 1000
local MICRO <const> = 1000

local config <const> = Siku.config.log
local client <const> = config.client or {}
local maxBytes <const> = tonumber(client.maxBatchBytes) or 24576
local maxRecords <const> = tonumber(client.maxBatchRecords) or 50

local droppedBytes = 0

internal.allowAudit = false
internal.allowSystem = false
internal.setOrigin('client')
internal.flushMs = math.max(internal.flushMs, CLIENT_FLUSH_MS)

internal.now = GetGameTimer

internal.monotonicUs = function()
  return GetGameTimer() * MICRO
end

local function trim(batch)
  local out <const> = {}

  for i = 1, math.min(#batch, maxRecords) do
    out[i] = batch[i]
  end

  return out, #batch - #out
end

local function deliver(batch)
  local records <const>, overflow <const> = trim(batch)
  local payload <const> = { now = GetGameTimer(), records = records, dropped = overflow + droppedBytes }
  local encoded <const> = json.encode(payload)

  if #encoded > maxBytes then
    if #records > 1 then
      local half <const> = #records // 2
      local first <const> = {}
      local second <const> = {}

      for i = 1, half do
        first[i] = records[i]
      end

      for i = half + 1, #records do
        second[#second + 1] = records[i]
      end

      deliver(first)
      deliver(second)

      return
    end

    droppedBytes = droppedBytes + 1

    return
  end

  droppedBytes = 0
  TriggerServerEvent(BATCH_EVENT, payload)
end

internal.send = deliver

internal.flushLoop()

return {}
