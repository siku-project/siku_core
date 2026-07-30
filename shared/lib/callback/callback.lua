local DEFAULT_TIMEOUT <const> = 10000
local MIN_TIMEOUT <const> = 1000

local EVENTS <const> = {
  SERVER_REQUEST = 'siku:server:callbackRequest',
  SERVER_RESPONSE = 'siku:server:callbackResponse',
  CLIENT_REQUEST = 'siku:client:callbackRequest',
  CLIENT_RESPONSE = 'siku:client:callbackResponse',
}

local TIMEOUT <const> = math.max(tonumber(CallbackConfig.timeout) or DEFAULT_TIMEOUT, MIN_TIMEOUT)

--- Read the length of a packed table, tolerating one built by a remote peer.
---@param packed table The packed table to measure.
---@return number count The number of values it carries.
local function packedCount(packed)
  return packed.n or #packed
end

--- Create the request and response machinery shared by both callback directions.
---@param sendRequest function Sends a request to the other side, as (target, requestId, name, ...).
---@param sendResponse function Answers a request from the other side, as (target, requestId, ok, results).
---@param forwardTarget boolean Whether handlers receive the requesting target as their first argument.
---@return table channel The channel exposing register, unregister, isRegistered, request, onRequest, onResponse and dropTarget.
local function createChannel(sendRequest, sendResponse, forwardTarget)
  local handlers <const> = {}
  local pending <const> = {}
  local channel <const> = {}
  local nextRequestId = 0

  --- Settle a pending request and wake the thread waiting on it.
  ---@param requestId number The identifier of the request to settle.
  ---@param ok boolean Whether the call succeeded.
  ---@param results table The packed values carried back to the caller.
  local function settle(requestId, ok, results)
    local entry <const> = pending[requestId]

    if not entry then
      return
    end

    pending[requestId] = nil

    if entry.timer then
      ClearTimeout(entry.timer)
    end

    entry.answer:resolve({
      ok = ok == true,
      results = type(results) == 'table' and results or table.pack(results),
    })
  end

  --- Register a handler answering one callback name.
  ---@param name string The callback name.
  ---@param handler function The function answering the callback.
  ---@return boolean registered Whether the handler was stored.
  function channel.register(name, handler)
    if type(name) ~= 'string' or name == '' then
      Siku.print.error('Callback name must be a non-empty string')
      return false
    end

    if type(handler) ~= 'function' then
      Siku.print.error(("Callback '%s' needs a function handler"):format(name))
      return false
    end

    if handlers[name] then
      Siku.print.warn(("Callback '%s' is already registered, replacing it"):format(name))
    end

    handlers[name] = handler

    return true
  end

  --- Remove a registered handler.
  ---@param name string The callback name.
  ---@return boolean removed Whether a handler existed and was removed.
  function channel.unregister(name)
    if not handlers[name] then
      return false
    end

    handlers[name] = nil

    return true
  end

  --- Check whether a handler answers this callback name.
  ---@param name string The callback name.
  ---@return boolean registered Whether a handler is registered.
  function channel.isRegistered(name)
    return handlers[name] ~= nil
  end

  --- Send a request and block the calling thread until an answer or a timeout.
  ---@param target number? The player to question, or nil when questioning the server.
  ---@param name string The callback name.
  ---@param ... any The arguments forwarded to the handler.
  ---@return boolean ok, any ... Whether the call succeeded, then the handler results or the failure reason.
  function channel.request(target, name, ...)
    nextRequestId = nextRequestId + 1

    local requestId <const> = nextRequestId
    local answer <const> = promise.new()

    pending[requestId] = {
      answer = answer,
      target = target,
      timer = SetTimeout(TIMEOUT, function()
        settle(requestId, false, table.pack(("Callback '%s' timed out after %dms"):format(name, TIMEOUT)))
      end),
    }

    sendRequest(target, requestId, name, ...)

    local outcome <const> = Citizen.Await(answer)
    local results <const> = outcome.results

    return outcome.ok, table.unpack(results, 1, packedCount(results))
  end

  --- Answer an inbound request coming from the other side.
  ---@param target number? The peer to answer, or nil when answering the server.
  ---@param requestId number The request identifier to echo back.
  ---@param name string The callback name being asked for.
  ---@param ... any The arguments sent by the caller.
  function channel.onRequest(target, requestId, name, ...)
    local handler <const> = handlers[name]

    if not handler then
      sendResponse(target, requestId, false, table.pack(("Callback '%s' is not registered"):format(tostring(name))))
      return
    end

    local outcome <const> = forwardTarget and table.pack(pcall(handler, target, ...)) or table.pack(pcall(handler, ...))

    if not outcome[1] then
      local reason <const> = tostring(outcome[2])

      Siku.print.error(("Callback '%s' failed: %s"):format(tostring(name), reason))
      sendResponse(target, requestId, false, table.pack(reason))

      return
    end

    sendResponse(target, requestId, true, table.pack(table.unpack(outcome, 2, outcome.n)))
  end

  --- Take in an answer sent back by the other side.
  ---@param requestId number The identifier echoed by the peer.
  ---@param ok boolean Whether the peer reported a success.
  ---@param results table The packed values it sent back.
  ---@param from number? The peer that answered, checked against the one questioned.
  function channel.onResponse(requestId, ok, results, from)
    local entry <const> = pending[requestId]

    if not entry then
      return
    end

    if from ~= nil and entry.target ~= from then
      return
    end

    settle(requestId, ok, results)
  end

  --- Settle every pending request aimed at a peer that went away.
  ---@param target number The peer that disconnected.
  function channel.dropTarget(target)
    for requestId, entry in pairs(pending) do
      if entry.target == target then
        settle(requestId, false, table.pack(('Target %d disconnected before answering'):format(target)))
      end
    end
  end

  return channel
end

_SikuInternal.CALLBACK_EVENTS = EVENTS
_SikuInternal.CALLBACK_TIMEOUT = TIMEOUT
_SikuInternal.CreateCallbackChannel = createChannel
