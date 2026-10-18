local CORE <const> = 'siku_core'
local ID_FORMAT <const> = '%012x%08x%08x%04x'
local FLUSH_MIN_MS <const> = 50
local LEVELS <const> = { trace = 1, debug = 5, info = 9, warn = 13, error = 17, fatal = 21 }

local config <const> = Siku.config.log
local limits <const> = config.limits or {}
local tracing <const> = config.tracing or {}
local enabled <const> = config.enabled ~= false

local settings <const> = {
  enabled = enabled,
  batchSize = math.max(tonumber(config.batchSize) or 100, 1),
  flushMs = math.max(tonumber(config.flushMs) or 200, FLUSH_MIN_MS),
  tracing = enabled and tracing.enabled ~= false,
  sql = tracing.sql ~= false,
  sampleRate = tonumber(tracing.sampleRate) or 1.0,
  autoSampleRate = tonumber(tracing.autoSampleRate) or 0.2,
  maxSpans = tonumber(tracing.maxSpans) or 200,
  maxAttributes = tonumber(tracing.maxAttributes) or 64,
  message = tonumber(limits.message) or 2048,
  string = tonumber(limits.string) or 1024,
  keys = tonumber(limits.keys) or 32,
  depth = tonumber(limits.depth) or 3,
  list = tonumber(limits.list) or 50,
  entities = tonumber(limits.entities) or 16,
  stack = tonumber(limits.stack) or 16384,
  client = config.client or {},
}

local clock <const> = {
  now = GetGameTimer,
  micros = function()
    return GetGameTimer() * 1000
  end,
}

internal.LEVELS = LEVELS
internal.settings = settings
internal.clock = clock
internal.origin = Siku.context
internal.categories = {
  script = true,
  audit = Siku.context == 'server',
  system = Siku.context == 'server' and Siku.name == CORE,
}

function internal.newId(now)
  return ID_FORMAT:format(
    math.max(now, 0) & 0xFFFFFFFFFFFF,
    math.random(0, 0xFFFFFFFF),
    math.random(0, 0xFFFFFFFF),
    math.random(0, 0xFFFF)
  )
end

import('sanitize')
import('queue')
import('trace')
import('events')

return {
  levels = function()
    return LEVELS
  end,
  now = function()
    return clock.now()
  end,
  isEnabled = function()
    return enabled
  end,
}
