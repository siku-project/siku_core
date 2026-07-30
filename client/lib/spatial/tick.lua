local subscribers = {}
local tickActive = false

--- Register a named tick subscriber. Starts the tick loop on first subscriber.
---@param key string A unique name for this subscriber.
---@param fn function The function to call every frame.
function Siku.RegisterSpatialTick(key, fn)
  subscribers[key] = fn

  if not tickActive then
    tickActive = true
    Citizen.CreateThread(function()
      while next(subscribers) do
        for _, callback in pairs(subscribers) do
          callback()
        end
        Wait(0)
      end
      tickActive = false
    end)
  end
end

--- Unregister a named tick subscriber. Stops the tick loop when no subscribers remain.
---@param key string The name of the subscriber to remove.
function Siku.UnregisterSpatialTick(key)
  subscribers[key] = nil
end

--- Check if there are any active tick subscribers.
---@return boolean hasSubscribers Whether any subscribers are registered.
function Siku.HasSpatialTickSubscribers()
  return next(subscribers) ~= nil
end
