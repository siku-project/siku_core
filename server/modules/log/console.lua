local SCRIPT_CHANNEL <const> = '^script:([^:]+)'
local WARNING_CHANNEL_SUFFIX <const> = ':warning'
local RESOURCE_CHANNELS <const> = { resources = true, ['citizen-server-impl'] = true, ['c-server-impl'] = true }
local ERROR_PREFIX <const> = 'SCRIPT ERROR: '
local ERROR_BODY <const> = 'SCRIPT ERROR: (.*)$'
local FRAME_PATTERN <const> = '^%^3> (.-)%^7 %(%^5(.-)%^7[^:]*:(%d+)%)'
local LOCATION_PATTERN <const> = '^(@[^:]+):(%d+): (.*)$'
local LOAD_ERROR <const> = '^Error (%a+) script (%S+) in resource (%S+): (.*)$'
local START_FAILED <const> = "^%^3Couldn't start resource (%S+)%.%^7"
local WARNING_LINE <const> = '^%^3Warning: (.*)%^7'
local WARNING_PREFIX <const> = '^Warning: '
local COLOR_CODE <const> = '%^%d'
local IDLE_MS <const> = 1500
local MAX_FRAMES <const> = 40
local MAX_PENDING <const> = 64
local MAX_PARTIAL <const> = 8192
local DRAIN_MS <const> = 100
local MAX_INBOX <const> = 20000

local internal <const> = _SikuInternal.log

local partial <const> = {}
local pending <const> = {}
local pendingCount = 0
local inbox = {}
local inboxCount = 0

local function strip(text)
  return (text:gsub(COLOR_CODE, ''))
end

local function warning(resource, message)
  Siku.log.system('script.warning', {
    level = 'warn',
    message = message,
    data = { resource = resource },
    entities = { internal.resourceEntity(resource) },
  })
end

local function scriptError(entry)
  local location <const>, line <const>, message <const> = entry.message:match(LOCATION_PATTERN)

  Siku.log.system('script.error', {
    level = 'error',
    message = message or entry.message,
    file = location,
    line = tonumber(line),
    stack = #entry.frames > 0 and table.concat(entry.frames, '\n') or nil,
    data = { resource = entry.resource },
    entities = { internal.resourceEntity(entry.resource) },
  })
end

local function finish(resource)
  local entry <const> = pending[resource]

  if not entry then
    return
  end

  pending[resource] = nil
  pendingCount = pendingCount - 1
  scriptError(entry)
end

local function begin(resource, message)
  finish(resource)

  if pendingCount >= MAX_PENDING then
    return
  end

  pendingCount = pendingCount + 1
  pending[resource] = { resource = resource, message = message, frames = {}, at = GetGameTimer() }
end

local function collectFrame(entry, line)
  local name <const>, file <const>, number <const> = line:match(FRAME_PATTERN)

  if not name then
    return false
  end

  if #entry.frames < MAX_FRAMES then
    entry.frames[#entry.frames + 1] = ('%s (%s:%s)'):format(name, file, number)
  end

  entry.at = GetGameTimer()

  return true
end

local function scriptLine(resource, text)
  local line <const> = text:gsub('^%s+', '')

  if line:sub(1, 2) == '^1' and line:find(ERROR_PREFIX, 1, true) then
    begin(resource, (strip(line:match(ERROR_BODY) or line):gsub('%s+$', '')))
    return
  end

  local entry <const> = pending[resource]

  if entry then
    if collectFrame(entry, line) then
      return
    end

    finish(resource)
  end

  local message <const> = line:match(WARNING_LINE)

  if message then
    warning(resource, strip(message))
  end
end

local function resourceLine(text)
  local kind <const>, file <const>, resource <const>, message <const> = text:match(LOAD_ERROR)

  if kind then
    Siku.log.system('script.load_error', {
      level = 'fatal',
      message = strip(message),
      file = file,
      data = { resource = resource, phase = kind },
      entities = { internal.resourceEntity(resource) },
    })
    return
  end

  local failed <const> = text:match(START_FAILED)

  if failed then
    Siku.log.system('resource.start_failed', {
      level = 'error',
      message = ("Couldn't start resource %s"):format(failed),
      entities = { internal.resourceEntity(failed) },
    })
  end
end

local function handleLine(channel, text)
  local resource <const> = channel:match(SCRIPT_CHANNEL)

  if resource then
    if channel:sub(-#WARNING_CHANNEL_SUFFIX) == WARNING_CHANNEL_SUFFIX then
      warning(resource, (strip(text):gsub(WARNING_PREFIX, '')))
      return
    end

    scriptLine(resource, text)
    return
  end

  if RESOURCE_CHANNELS[channel] then
    resourceLine(text)
  end
end

local function handlePiece(channel, piece)
  if partial[channel] then
    piece = partial[channel] .. piece
    partial[channel] = nil
  end

  local start = 1

  while true do
    local stop <const> = piece:find('\n', start, true)

    if not stop then
      local rest <const> = piece:sub(start)

      if rest ~= '' and #rest < MAX_PARTIAL then
        partial[channel] = rest
      end

      return
    end

    local line <const> = piece:sub(start, stop - 1)

    if line ~= '' then
      handleLine(channel, line)
    end

    start = stop + 1
  end
end

local function drain()
  if inboxCount == 0 then
    return
  end

  local pieces <const> = inbox
  local count <const> = inboxCount

  inbox = {}
  inboxCount = 0

  for i = 1, count, 2 do
    handlePiece(pieces[i], pieces[i + 1])
  end
end

local function finishIdle()
  if pendingCount == 0 then
    return
  end

  local now <const> = GetGameTimer()

  for resource, entry in pairs(pending) do
    if now - entry.at >= IDLE_MS then
      finish(resource)
    end
  end
end

RegisterConsoleListener(function(channel, message)
  if inboxCount >= MAX_INBOX or type(channel) ~= 'string' or type(message) ~= 'string' then
    return
  end

  inbox[inboxCount + 1] = channel
  inbox[inboxCount + 2] = message
  inboxCount = inboxCount + 2
end)

Citizen.CreateThread(function()
  while true do
    Wait(DRAIN_MS)
    drain()
    finishIdle()
  end
end)
