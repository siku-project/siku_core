local SCRIPT_CHANNEL <const> = '^script:([^:]+)'
local ERROR_PREFIX <const> = 'SCRIPT ERROR: '
local FRAME_PATTERN <const> = '^%^3> (.-)%^7 %(%^5(.-)%^7[^:]*:(%d+)%)'
local LOCATION_PATTERN <const> = '^(@[^:]+):(%d+): (.*)$'
local LOAD_ERROR <const> = '^Error (%a+) script (%S+) in resource (%S+): (.*)$'
local START_FAILED <const> = "^%^3Couldn't start resource (%S+)%.%^7"
local WARNING_PREFIX <const> = '^%^3Warning: (.*)%^7'
local IDLE_MS <const> = 1500
local MAX_FRAMES <const> = 40
local MAX_PENDING <const> = 64
local DRAIN_MS <const> = 100
local MAX_INBOX <const> = 20000

local lines <const> = {}
local pending <const> = {}
local pendingCount = 0

local function strip(text)
  return (text:gsub('%^%d', ''))
end

local function emitError(entry)
  local location <const>, line <const>, message <const> = entry.message:match(LOCATION_PATTERN)
  local frames <const> = entry.frames
  local stack <const> = #frames > 0 and table.concat(frames, '\n') or nil

  Siku.log.system('script.error', {
    level = 'error',
    message = message or entry.message,
    file = location,
    line = tonumber(line),
    stack = stack,
    data = { resource = entry.resource },
    entities = { { type = 'resource', id = entry.resource, role = 'subject', label = entry.resource } },
  })
end

local function finish(resource)
  local entry <const> = pending[resource]

  if not entry then
    return
  end

  pending[resource] = nil
  pendingCount = pendingCount - 1
  emitError(entry)
end

local function begin(resource, message)
  finish(resource)

  if pendingCount >= MAX_PENDING then
    return
  end

  pendingCount = pendingCount + 1
  pending[resource] = { resource = resource, message = message, frames = {}, at = GetGameTimer() }
end

local function handleScript(resource, text)
  local trimmed <const> = text:gsub('^%s+', '')

  if trimmed:sub(1, 2) == '^1' and trimmed:find(ERROR_PREFIX, 1, true) then
    local body <const> = trimmed:match('SCRIPT ERROR: (.*)$')

    begin(resource, strip(body or trimmed):gsub('%s+$', ''))
    return
  end

  local entry <const> = pending[resource]

  if entry then
    local name <const>, file <const>, line <const> = trimmed:match(FRAME_PATTERN)

    if name then
      if #entry.frames < MAX_FRAMES then
        entry.frames[#entry.frames + 1] = ('%s (%s:%s)'):format(name, file, line)
      end

      entry.at = GetGameTimer()
      return
    end

    finish(resource)
  end

  local warning <const> = trimmed:match(WARNING_PREFIX)

  if warning then
    Siku.log.system('script.warning', {
      level = 'warn',
      message = strip(warning),
      data = { resource = resource },
      entities = { { type = 'resource', id = resource, role = 'subject', label = resource } },
    })
  end
end

local function handleResources(text)
  local kind <const>, file <const>, resource <const>, message <const> = text:match(LOAD_ERROR)

  if kind then
    Siku.log.system('script.load_error', {
      level = 'fatal',
      message = strip(message),
      file = file,
      data = { resource = resource, phase = kind },
      entities = { { type = 'resource', id = resource, role = 'subject', label = resource } },
    })
    return
  end

  local failed <const> = text:match(START_FAILED)

  if failed then
    Siku.log.system('resource.start_failed', {
      level = 'error',
      message = ("Couldn't start resource %s"):format(failed),
      entities = { { type = 'resource', id = failed, role = 'subject', label = failed } },
    })
  end
end

local function handleLine(channel, text)
  local resource <const> = channel:match(SCRIPT_CHANNEL)

  if resource then
    if channel:sub(-8) == ':warning' then
      Siku.log.system('script.warning', {
        level = 'warn',
        message = strip(text):gsub('^Warning: ', ''),
        data = { resource = resource },
        entities = { { type = 'resource', id = resource, role = 'subject', label = resource } },
      })
      return
    end

    handleScript(resource, text)
    return
  end

  if channel == 'resources' or channel == 'citizen-server-impl' or channel == 'c-server-impl' then
    handleResources(text)
  end
end

local function onPiece(channel, piece)
  if type(channel) ~= 'string' or type(piece) ~= 'string' then
    return
  end

  local buffer = lines[channel]

  if buffer then
    piece = buffer .. piece
    lines[channel] = nil
  end

  local start = 1

  while true do
    local stop <const> = piece:find('\n', start, true)

    if not stop then
      local rest <const> = piece:sub(start)

      if rest ~= '' and #rest < 8192 then
        lines[channel] = rest
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

local inbox = {}
local inboxCount = 0

RegisterConsoleListener(function(channel, message)
  if inboxCount >= MAX_INBOX then
    return
  end

  inbox[inboxCount + 1] = channel
  inbox[inboxCount + 2] = message
  inboxCount = inboxCount + 2
end)

local function drain()
  if inboxCount == 0 then
    return
  end

  local pieces <const> = inbox
  local count <const> = inboxCount

  inbox = {}
  inboxCount = 0

  for i = 1, count, 2 do
    onPiece(pieces[i], pieces[i + 1])
  end
end

Citizen.CreateThread(function()
  while true do
    Wait(DRAIN_MS)
    drain()

    if pendingCount > 0 then
      local now <const> = GetGameTimer()

      for resource, entry in pairs(pending) do
        if now - entry.at >= IDLE_MS then
          finish(resource)
        end
      end
    end
  end
end)
