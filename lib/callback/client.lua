local EVENTS <const> = internal.events

local bound <const> = {}

local channel <const> = internal.createChannel(
  function(_, requestId, name, ...)
    TriggerServerEvent(EVENTS.SERVER_REQUEST:format(name), Siku.name, requestId, ...)
  end,
  function(_, caller, requestId, ok, results)
    TriggerServerEvent(EVENTS.SERVER_RESPONSE:format(caller), requestId, ok, results)
  end,
  false
)

--- Listen once for the requests aimed at one callback name. The handler is
--- looked up at call time, so an unregistered name simply stops answering.
---@param name string The callback name.
local function bindRequest(name)
  if bound[name] then
    return
  end

  bound[name] = true

  RegisterNetEvent(EVENTS.CLIENT_REQUEST:format(name), function(caller, requestId, ...)
    if type(caller) ~= 'string' or type(requestId) ~= 'number' then
      return
    end

    channel.onRequest(nil, caller, requestId, name, ...)
  end)
end

RegisterNetEvent(EVENTS.CLIENT_RESPONSE:format(Siku.name), function(requestId, ok, results)
  channel.onResponse(requestId, ok, results)
end)

--- Register a handler answering a callback the server may ask this client.
---@param name string The callback name, following the '<resource>:callback:<name>' convention.
---@param handler function The function answering the callback.
---@return boolean registered Whether the handler was stored.
local function register(name, handler)
  if not channel.register(name, handler) then
    return false
  end

  bindRequest(name)

  return true
end

--- Remove a handler previously registered on this client.
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

--- Ask the server a callback and block this thread until it answers or times out.
---@param name string The callback name registered on the server.
---@param ... any The arguments forwarded to the server handler.
---@return boolean ok, any ... Whether the call succeeded, then the handler results or the failure reason.
local function triggerServer(name, ...)
  return channel.request(nil, name, ...)
end

return {
  register = register,
  unregister = unregister,
  isRegistered = isRegistered,
  triggerServer = triggerServer,
}
