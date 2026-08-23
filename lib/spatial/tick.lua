local subscribers = {}
local tickActive = false

--- Register a named per-frame subscriber. Starts the tick loop on first subscriber.
---@param key string A unique name for this subscriber.
---@param fn function The function to call every frame.
local function registerTick(key, fn)
  subscribers[key] = fn

  if tickActive then
    return
  end

  tickActive = true

  CreateThread(function()
    while next(subscribers) do
      for name, callback in pairs(subscribers) do
        local ok <const>, err <const> = pcall(callback)

        if not ok then
          Siku.print.error(("Spatial tick '%s' failed: %s"):format(name, tostring(err)))
        end
      end

      Wait(0)
    end

    tickActive = false
  end)
end

--- Unregister a named per-frame subscriber. Stops the tick loop when no subscribers remain.
---@param key string The name of the subscriber to remove.
local function unregisterTick(key)
  subscribers[key] = nil
end

--- Check if there are any active per-frame subscribers.
---@return boolean hasSubscribers Whether any subscribers are registered.
local function hasTickSubscribers()
  return next(subscribers) ~= nil
end

return {
  registerTick = registerTick,
  unregisterTick = unregisterTick,
  hasTickSubscribers = hasTickSubscribers,
}
