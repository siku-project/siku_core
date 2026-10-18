local PULL_PATH <const> = '/logs/pull'
local HEALTH_PATH <const> = '/logs/health'
local TOKEN_CONVAR <const> = 'siku:logToken'
local DEFAULT_LIMIT <const> = 2000
local MAX_LIMIT <const> = 5000
local VERSION <const> = 1
local JSON_HEADERS <const> = { ['Content-Type'] = 'application/json', ['Cache-Control'] = 'no-store' }
local ERRORS <const> = {
  method = '{"error":"method_not_allowed"}',
  path = '{"error":"not_found"}',
  forbidden = '{"error":"forbidden"}',
}

local internal <const> = _SikuInternal.log
local settings <const> = internal.settings

local pulls = 0
local lastPullAt = nil

local function token()
  local value <const> = GetConvar(TOKEN_CONVAR, '')

  if value ~= '' then
    return value
  end

  return settings.token
end

local function isLoopback(address)
  if type(address) ~= 'string' then
    return false
  end

  local host = (address:match('^%[(.-)%]:%d+$') or address:match('^(.-):%d+$') or address):lower()

  if host:sub(1, 7) == '::ffff:' then
    host = host:sub(8)
  end

  return host == '::1' or host:match('^127%.%d+%.%d+%.%d+$') ~= nil
end

local function authorized(req)
  local expected <const> = token()

  if expected ~= '' then
    local header <const> = req.headers and (req.headers.Authorization or req.headers.authorization)

    if header == 'Bearer ' .. expected then
      return true
    end
  end

  return isLoopback(req.address)
end

local function query(path)
  local params <const> = {}
  local raw <const> = path:match('%?(.*)$')

  if raw then
    for key, value in raw:gmatch('([^&=]+)=([^&]*)') do
      params[key] = value
    end
  end

  return params
end

local function reply(res, status, body)
  res.writeHead(status, JSON_HEADERS)
  res.send(body)
end

local function health()
  local state <const> = internal.state()

  state.v = VERSION
  state.pulls = pulls
  state.lastPullAt = lastPullAt

  return json.encode(state)
end

local function pull(params)
  local cursor <const> = tonumber(params.cursor)
  local limit <const> = math.min(math.max(math.floor(tonumber(params.limit) or DEFAULT_LIMIT), 1), MAX_LIMIT)

  if cursor then
    internal.ack(cursor)
  end

  local slice <const>, nextSeq <const>, pending <const> = internal.pull(cursor, limit)
  local state <const> = internal.state()

  pulls = pulls + 1
  lastPullAt = os.time()

  return table.concat({
    '{"v":', VERSION,
    ',"boot":"', state.boot,
    '","next":', nextSeq,
    ',"pending":', pending,
    ',"dropped":', state.dropped,
    ',"state":', json.encode(state),
    ',"records":[', table.concat(slice, ','), ']}',
  })
end

SetHttpHandler(function(req, res)
  if req.method ~= 'GET' then
    return reply(res, 405, ERRORS.method)
  end

  local path <const> = req.path:match('^[^?]*')

  if path ~= PULL_PATH and path ~= HEALTH_PATH then
    return reply(res, 404, ERRORS.path)
  end

  if not authorized(req) then
    return reply(res, 403, ERRORS.forbidden)
  end

  if path == HEALTH_PATH then
    return reply(res, 200, health())
  end

  return reply(res, 200, pull(query(req.path)))
end)
