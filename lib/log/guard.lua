local EVENT <const> = 'script.error'
local LOCATION_PATTERN <const> = '^(.-):(%d+): (.*)$'
local ERROR_HEADER <const> = '^%^1SCRIPT ERROR: (.-)%^7\n?(.*)$'
local FRAME_PATTERN <const> = '%^3> (.-)%^7 %(%^5(.-)%^7[^:]*:(%d+)%)'
local NUI_ERROR <const> = '^error during NUI callback ([^:]+): (.*)$'
local TRACEBACK_HEADER <const> = '^%s*stack traceback:%s*'
local COLOR_CODE <const> = '%^%d'
local MAX_FRAMES <const> = 40

local settings <const> = internal.settings
local emit <const> = internal.emit

local function locate(text)
  local file <const>, line <const>, message <const> = text:match(LOCATION_PATTERN)

  if file then
    return file, tonumber(line), message
  end

  return nil, nil, text
end

local function record(text, stack, context)
  local file <const>, line <const>, message <const> = locate((text:gsub(COLOR_CODE, '')))

  emit(EVENT, {
    level = 'error',
    message = message,
    file = file,
    line = line,
    stack = stack,
    data = { context = context },
    dedupe = settings.dedupeMs,
    key = file and (file .. ':' .. line) or message,
  })
end

local function describe(fn)
  local info <const> = debug.getinfo(fn, 'S')

  return ('%s:%d'):format(info.short_src, info.linedefined)
end

local function traceback()
  local text <const> = debug.traceback('', 3):gsub(TRACEBACK_HEADER, ''):gsub('\n%s+', '\n')

  return text ~= '' and text or nil
end

local function guard(fn, kind, name)
  if type(fn) ~= 'function' then
    return fn
  end

  local context <const> = name or (kind .. ' ' .. describe(fn))

  return function(...)
    local results <const> = table.pack(xpcall(fn, function(err)
      record(tostring(err), traceback(), context)
      return err
    end, ...))

    if not results[1] then
      error(results[2], 0)
    end

    return table.unpack(results, 2, results.n)
  end
end

local function capture(text)
  local head <const>, rest <const> = text:match(ERROR_HEADER)

  if head then
    local frames <const> = {}

    for name, file, line in rest:gmatch(FRAME_PATTERN) do
      if #frames < MAX_FRAMES then
        frames[#frames + 1] = ('%s (%s:%s)'):format(name, file, line)
      end
    end

    record(head, #frames > 0 and table.concat(frames, '\n') or nil, 'ref call')
    return
  end

  local callback <const>, err <const> = text:match(NUI_ERROR)

  if callback then
    record((err:gsub('%s+$', '')), nil, 'nui ' .. callback)
  end
end

local createThread <const> = Citizen.CreateThread
local createThreadNow <const> = Citizen.CreateThreadNow
local setTimeout <const> = Citizen.SetTimeout
local trace <const> = Citizen.Trace

function Citizen.CreateThread(fn)
  return createThread(guard(fn, 'thread'))
end

function Citizen.CreateThreadNow(fn, name)
  return createThreadNow(guard(fn, 'thread', name), name)
end

function Citizen.SetTimeout(ms, fn)
  return setTimeout(ms, guard(fn, 'timeout'))
end

function Citizen.Trace(text)
  if type(text) == 'string' then
    capture(text)
  end

  return trace(text)
end

_G.CreateThread = Citizen.CreateThread
_G.SetTimeout = Citizen.SetTimeout

return {}
