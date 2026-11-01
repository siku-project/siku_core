local NOTIFICATION_RESOURCE <const> = 'siku_notification'
local STARTED <const> = 'started'

--- Check that the notification resource is started before forwarding a call.
---@return boolean ready Whether the notification resource is available.
local function isReady()
  if GetResourceState(NOTIFICATION_RESOURCE) == STARTED then
    return true
  end

  Siku.log.warn('dependency.missing', ("'%s' is not started, the notification call was ignored"):format(NOTIFICATION_RESOURCE), {
    resource = Siku.name,
    dependency = NOTIFICATION_RESOURCE,
    call = 'notification',
  }, {
    entities = { { type = 'resource', id = NOTIFICATION_RESOURCE, role = 'subject', label = NOTIFICATION_RESOURCE } },
    dedupe = tonumber((Siku.config.log.errors or {}).dedupeMs) or 5000,
    key = NOTIFICATION_RESOURCE,
  })

  return false
end

--- Send a notification to a player.
---@param source number The player's server id.
---@param data table The notification payload (type, title, subtitle, description, icon, image, imageMode, position, duration).
local function show(source, data)
  if not isReady() then
    return
  end

  exports[NOTIFICATION_RESOURCE]:show(source, data)
end

--- Hide every notification for a player.
---@param source number The player's server id.
local function hide(source)
  if not isReady() then
    return
  end

  exports[NOTIFICATION_RESOURCE]:hide(source)
end

return {
  show = show,
  hide = hide,
}
