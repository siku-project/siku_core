local BATCH_EVENT <const> = 'siku:log:batch'
local FLUSH_MIN_MS <const> = 1000
local DEFAULT_BATCH_BYTES <const> = 24576
local DEFAULT_BATCH_RECORDS <const> = 50

local settings <const> = internal.settings
local maxBytes <const> = tonumber(settings.client.maxBatchBytes) or DEFAULT_BATCH_BYTES
local maxRecords <const> = tonumber(settings.client.maxBatchRecords) or DEFAULT_BATCH_RECORDS

local oversized = 0

local function slice(batch, from, to)
  local out <const> = {}

  for i = from, to do
    out[#out + 1] = batch[i]
  end

  return out
end

local function deliver(batch)
  local records <const> = slice(batch, 1, math.min(#batch, maxRecords))
  local payload <const> = { now = GetGameTimer(), records = records, dropped = (#batch - #records) + oversized }
  local encoded <const> = json.encode(payload)

  if #encoded > maxBytes then
    if #records == 1 then
      oversized = oversized + 1
      return
    end

    local half <const> = #records // 2

    deliver(slice(records, 1, half))
    deliver(slice(records, half + 1, #records))

    return
  end

  oversized = 0
  TriggerServerEvent(BATCH_EVENT, payload)
end

internal.startDelivery(deliver, math.max(settings.flushMs, FLUSH_MIN_MS))

return {}
