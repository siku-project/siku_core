local EVENTS <const> = _SikuInternal.CALLBACK_EVENTS

local channel <const> = _SikuInternal.CreateCallbackChannel(
  function(_, requestId, name, ...)
    TriggerServerEvent(EVENTS.SERVER_REQUEST, requestId, name, ...)
  end,
  function(_, requestId, ok, results)
    TriggerServerEvent(EVENTS.SERVER_RESPONSE, requestId, ok, results)
  end,
  false
)

RegisterNetEvent(EVENTS.CLIENT_REQUEST, function(requestId, name, ...)
  channel.onRequest(nil, requestId, name, ...)
end)

RegisterNetEvent(EVENTS.CLIENT_RESPONSE, function(requestId, ok, results)
  channel.onResponse(requestId, ok, results)
end)

--- Register a handler answering a callback the server may ask this client.
---@param name string The callback name, following the 'siku:callback:<name>' convention.
---@param handler function The function answering the callback.
---@return boolean registered Whether the handler was stored.
function Siku.RegisterCallback(name, handler)
  return channel.register(name, handler)
end

--- Remove a handler previously registered on this client.
---@param name string The callback name.
---@return boolean removed Whether a handler existed and was removed.
function Siku.UnregisterCallback(name)
  return channel.unregister(name)
end

--- Check whether this client answers a callback name.
---@param name string The callback name.
---@return boolean registered Whether a handler is registered.
function Siku.IsCallbackRegistered(name)
  return channel.isRegistered(name)
end

--- Ask the server a callback and block this thread until it answers or times out.
---@param name string The callback name registered on the server.
---@param ... any The arguments forwarded to the server handler.
---@return boolean ok, any ... Whether the call succeeded, then the handler results or the failure reason.
function Siku.TriggerServerCallback(name, ...)
  return channel.request(nil, name, ...)
end
