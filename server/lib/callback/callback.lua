local EVENTS <const> = _SikuInternal.CALLBACK_EVENTS
local RATE_LIMIT <const> = math.max(tonumber(CallbackConfig.rateLimit) or 0, 0)

local timestamps <const> = {}

local channel <const> = _SikuInternal.CreateCallbackChannel(
  function(target, requestId, name, ...)
    TriggerClientEvent(EVENTS.CLIENT_REQUEST, target, requestId, name, ...)
  end,
  function(target, requestId, ok, results)
    TriggerClientEvent(EVENTS.CLIENT_RESPONSE, target, requestId, ok, results)
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

RegisterNetEvent(EVENTS.SERVER_REQUEST, function(requestId, name, ...)
  local sessionId <const> = source

  if isRateLimited(sessionId, name) then
    Siku.print.warn(("Callback '%s' rate limited for player %d"):format(tostring(name), sessionId))
    TriggerClientEvent(
      EVENTS.CLIENT_RESPONSE,
      sessionId,
      requestId,
      false,
      table.pack(("Callback '%s' rate limited"):format(tostring(name)))
    )

    return
  end

  channel.onRequest(sessionId, requestId, name, ...)
end)

RegisterNetEvent(EVENTS.SERVER_RESPONSE, function(requestId, ok, results)
  channel.onResponse(requestId, ok, results, source)
end)

AddEventHandler('playerDropped', function()
  local sessionId <const> = source

  timestamps[sessionId] = nil
  channel.dropTarget(sessionId)
end)

--- Register a handler answering a callback clients may ask the server.
---@param name string The callback name, following the 'siku:callback:<name>' convention.
---@param handler function The function answering the callback, receiving the caller session id first.
---@return boolean registered Whether the handler was stored.
function Siku.RegisterCallback(name, handler)
  return channel.register(name, handler)
end

--- Remove a handler previously registered on the server.
---@param name string The callback name.
---@return boolean removed Whether a handler existed and was removed.
function Siku.UnregisterCallback(name)
  return channel.unregister(name)
end

--- Check whether the server answers a callback name.
---@param name string The callback name.
---@return boolean registered Whether a handler is registered.
function Siku.IsCallbackRegistered(name)
  return channel.isRegistered(name)
end

--- Ask one client a callback and block this thread until it answers or times out.
---@param target number The player server id to question.
---@param name string The callback name registered on that client.
---@param ... any The arguments forwarded to the client handler.
---@return boolean ok, any ... Whether the call succeeded, then the handler results or the failure reason.
function Siku.TriggerClientCallback(target, name, ...)
  if type(target) ~= 'number' then
    Siku.print.error(("Callback '%s' needs a numeric player id as target"):format(tostring(name)))
    return false, 'Invalid target'
  end

  return channel.request(target, name, ...)
end
