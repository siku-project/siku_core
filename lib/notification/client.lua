local NOTIFICATION_RESOURCE <const> = 'siku_notification'
local STARTED <const> = 'started'

--- Check that the notification resource is started before forwarding a call.
---@return boolean ready Whether the notification resource is available.
local function isReady()
  if GetResourceState(NOTIFICATION_RESOURCE) == STARTED then
    return true
  end

  Siku.print.warn(("'%s' is not started, the notification call was ignored"):format(NOTIFICATION_RESOURCE))

  return false
end

--- Show a notification on this client.
---@param data table The notification payload (type, title, subtitle, description, icon, image, imageMode, position, duration).
local function show(data)
  if not isReady() then
    return
  end

  exports[NOTIFICATION_RESOURCE]:show(data)
end

--- Hide every notification on this client.
local function hide()
  if not isReady() then
    return
  end

  exports[NOTIFICATION_RESOURCE]:hide()
end

return {
  show = show,
  hide = hide,
}
