local EVENTS <const> = internal.events
local RATE_LIMIT <const> = math.max(tonumber(Siku.config.callback.rateLimit) or 0, 0)

local timestamps <const> = {}
local bound <const> = {}

local channel <const> = internal.createChannel(
  function(target, requestId, name, ...)
    TriggerClientEvent(EVENTS.CLIENT_REQUEST:format(name), target, Siku.name, requestId, ...)
  end,
  function(target, caller, requestId, ok, results)
    TriggerClientEvent(EVENTS.CLIENT_RESPONSE:format(caller), target, requestId, ok, results)
  end,
  true
)

--- Check whether a player is calling one callback faster than allowed.
---@param sessionId number The player server id.
---@param name string The callback name being asked for.
---@return boolean limited Whether this request must be rejected.
local function isRateLimited(sessionId, name)
  if RATE_LIMIT <= 0 then
    return false
  end

  local playerCalls = timestamps[sessionId]

  if not playerCalls then
    playerCalls = {}
    timestamps[sessionId] = playerCalls
  end

  local now <const> = GetGameTimer()
  local last <const> = playerCalls[name]

  if last and (now - last) < RATE_LIMIT then
    return true
  end

  playerCalls[name] = now

  return false
end

--- Listen once for the requests aimed at one callback name. The handler is
--- looked up at call time, so an unregistered name simply stops answering.
---@param name string The callback name.
local function bindRequest(name)
  if bound[name] then
    return
  end

  bound[name] = true

  RegisterNetEvent(EVENTS.SERVER_REQUEST:format(name), function(caller, requestId, ...)
    local sessionId <const> = source

    if type(caller) ~= 'string' or type(requestId) ~= 'number' then
      return
    end

    if isRateLimited(sessionId, name) then
      Siku.print.warn(("Callback '%s' rate limited for player %d"):format(name, sessionId))
      TriggerClientEvent(
        EVENTS.CLIENT_RESPONSE:format(caller),
        sessionId,
        requestId,
        false,
        table.pack(("Callback '%s' rate limited"):format(name))
      )

      return
    end

    channel.onRequest(sessionId, caller, requestId, name, ...)
  end)
end

RegisterNetEvent(EVENTS.SERVER_RESPONSE:format(Siku.name), function(requestId, ok, results)
  channel.onResponse(requestId, ok, results, source)
end)

AddEventHandler('playerDropped', function()
  local sessionId <const> = source

  timestamps[sessionId] = nil
  channel.dropTarget(sessionId)
end)

--- Register a handler answering a callback clients may ask the server.
---@param name string The callback name, following the '<resource>:callback:<name>' convention.
---@param handler function The function answering the callback, receiving the caller session id first.
---@return boolean registered Whether the handler was stored.
local function register(name, handler)
  if not channel.register(name, handler) then
    return false
  end

  bindRequest(name)

  return true
end

--- Remove a handler previously registered on the server.
---@param name string The callback name.
---@return boolean removed Whether a handler existed and was removed.
local function unregister(name)
  return channel.unregister(name)
end

--- Check whether this resource answers a callback name.
---@param name string The callback name.
---@return boolean registered Whether a handler is registered.
local function isRegistered(name)
  return channel.isRegistered(name)
end

--- Ask one client a callback and block this thread until it answers or times out.
---@param target number The player server id to question.
---@param name string The callback name registered on that client.
---@param ... any The arguments forwarded to the client handler.
---@return boolean ok, any ... Whether the call succeeded, then the handler results or the failure reason.
local function triggerClient(target, name, ...)
  if type(target) ~= 'number' then
    Siku.print.error(("Callback '%s' needs a numeric player id as target"):format(tostring(name)))
    return false, 'Invalid target'
  end

  return channel.request(target, name, ...)
end

return {
  register = register,
  unregister = unregister,
  isRegistered = isRegistered,
  triggerClient = triggerClient,
}
