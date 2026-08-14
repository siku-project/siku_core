local NOTIFICATION_RESOURCE <const> = 'siku_notification'

--- Check that the notification resource is started before forwarding a call.
---@return boolean ready Whether the notification resource is available.
local function isReady()
  if GetResourceState(NOTIFICATION_RESOURCE) == 'started' then
    return true
  end

  Siku.print.warn(("'%s' is not started, the notification call was ignored"):format(NOTIFICATION_RESOURCE))

  return false
end

--- Send a notification to a player.
---@param source number The player's server id.
---@param data table The notification payload (type, title, subtitle, description, icon, image, imageMode, position, duration).
function Siku.Notification(source, data)
  if not isReady() then
    return
  end

  exports[NOTIFICATION_RESOURCE]:show(source, data)
end

--- Hide every notification for a player.
---@param source number The player's server id.
function Siku.HideNotification(source)
  if not isReady() then
    return
  end

  exports[NOTIFICATION_RESOURCE]:hide(source)
end
