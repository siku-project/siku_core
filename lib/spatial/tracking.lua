local INSIDE_TICK_KEY <const> = 'zones:inside'

local proximityStates = {}
local insideZones = {}
local checkHandle = nil
local hasInsideTick = false

--- Resolve a tracked zone that still exists, with its proximity state.
---@param id number The zone ID.
---@return table? state The proximity state, nil when the zone is gone or untracked.
local function liveState(id)
  local state <const> = proximityStates[id]

  if not state then
    return nil
  end

  local entry <const> = internal.getZoneInternal(id)

  if not entry or entry.removed then
    return nil
  end

  return state
end

--- The inside tick that fires onInside callbacks every frame.
local function insideTick()
  for id in pairs(insideZones) do
    local state <const> = liveState(id)

    if state and state.callbacks.onInside then
      state.callbacks.onInside(Siku.spatial.getZoneById(id))
    end
  end
end

--- Refresh the inside state of one nearby zone, firing onEnter when the player just entered it.
---@param zoneId number The zone ID.
---@param distance number The distance reported by the grid.
---@param playerCoords vector3 The player position.
---@param newInside table The set of zones the player is inside after this check.
local function trackEntry(zoneId, distance, playerCoords, newInside)
  local state <const> = liveState(zoneId)

  if not state then
    return
  end

  state.distance = distance

  if not internal.containsZone(internal.getZoneInternal(zoneId).shape, playerCoords) then
    return
  end

  newInside[zoneId] = true

  if state.inside then
    return
  end

  state.inside = true

  if state.callbacks.onEnter then
    state.callbacks.onEnter(Siku.spatial.getZoneById(zoneId))
  end
end

--- Fire onExit for every zone the player just left.
---@param newInside table The set of zones the player is inside after this check.
local function trackExits(newInside)
  for id in pairs(insideZones) do
    if not newInside[id] then
      local state <const> = proximityStates[id]

      if state then
        state.inside = false
      end

      local liveZone <const> = state and liveState(id)

      if liveZone and liveZone.callbacks.onExit then
        liveZone.callbacks.onExit(Siku.spatial.getZoneById(id))
      end
    end
  end
end

--- Start or stop the per-frame inside tick depending on whether any inside zone wants it.
local function syncInsideTick()
  local hasInside = false

  for id in pairs(insideZones) do
    local state <const> = proximityStates[id]

    if state and state.callbacks.onInside then
      hasInside = true
      break
    end
  end

  if hasInside and not hasInsideTick then
    Siku.spatial.registerTick(INSIDE_TICK_KEY, insideTick)
    hasInsideTick = true
  elseif not hasInside and hasInsideTick then
    Siku.spatial.unregisterTick(INSIDE_TICK_KEY)
    hasInsideTick = false
  end
end

--- The coarse check that runs on interval to detect zone enter/exit.
local function coarseCheck()
  local playerCoords <const> = GetEntityCoords(PlayerPedId(), false)
  local nearby <const> = internal.getZoneGrid().getNearby(playerCoords, { radius = Siku.config.spatial.defaultNearbyRadius })
  local newInside <const> = {}

  for i = 1, #nearby do
    trackEntry(nearby[i].data, nearby[i].distance, playerCoords, newInside)
  end

  trackExits(newInside)

  insideZones = newInside

  syncInsideTick()
end

--- Start the zone check interval loop.
local function startCheckLoop()
  if checkHandle then
    return
  end

  coarseCheck()

  checkHandle = Siku.timers.setInterval(Siku.config.spatial.zoneCheckInterval, function()
    coarseCheck()
  end)
end

--- Stop the zone check interval loop.
local function stopCheckLoop()
  if not checkHandle then
    return
  end

  Siku.timers.clearInterval(checkHandle)
  checkHandle = nil

  if hasInsideTick then
    Siku.spatial.unregisterTick(INSIDE_TICK_KEY)
    hasInsideTick = false
  end
end

--- Check if any proximity states remain and stop the loop if not.
local function checkLifecycle()
  if not next(proximityStates) then
    stopCheckLoop()
  end
end

--- Apply the debug flag of a zone to the debug renderer.
---@param id number The zone ID.
---@param enabled boolean Whether debug is wanted.
local function syncDebug(id, enabled)
  local entry <const> = internal.getZoneInternal(id)

  if enabled and entry then
    Siku.spatial.enableZoneDebug(id, entry.shape, entry.debugColor)
    return
  end

  Siku.spatial.disableZoneDebug(id)
end

--- Wrap a shared zone with client-side proximity callbacks.
---@param zone table The shared ActiveZone.
---@param callbacks? table Proximity callbacks { onEnter?, onExit?, onInside? }.
---@return table wrappedZone The zone with proximity tracking.
local function wrapWithCallbacks(zone, callbacks)
  if callbacks then
    proximityStates[zone.id] = {
      callbacks = callbacks,
      inside = false,
      distance = math.huge,
    }
  end

  local entry <const> = internal.getZoneInternal(zone.id)

  if entry and entry.debug then
    syncDebug(zone.id, true)
  end

  local originalRemove <const> = zone.remove
  local originalSetDebug <const> = zone.setDebug

  zone.remove = function()
    proximityStates[zone.id] = nil
    insideZones[zone.id] = nil
    Siku.spatial.disableZoneDebug(zone.id)
    originalRemove()
    checkLifecycle()
  end

  zone.setDebug = function(enabled, color)
    originalSetDebug(enabled, color)
    syncDebug(zone.id, enabled)
  end

  if callbacks and Siku.table.size(proximityStates) == 1 then
    startCheckLoop()
  end

  return zone
end

--- Add a client-side sphere zone with proximity callbacks.
---@param coords vector3 The center of the sphere.
---@param radius number The radius of the sphere.
---@param callbacks? table Proximity callbacks { onEnter?, onExit?, onInside? }.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The zone with proximity tracking.
local function addClientSphereZone(coords, radius, callbacks, options)
  return wrapWithCallbacks(Siku.spatial.addSphereZone(coords, radius, options), callbacks)
end

--- Add a client-side box zone with proximity callbacks.
---@param coords vector3 The center of the box.
---@param size vector3 The dimensions (width, length, height).
---@param heading number The heading angle in degrees.
---@param callbacks? table Proximity callbacks { onEnter?, onExit?, onInside? }.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The zone with proximity tracking.
local function addClientBoxZone(coords, size, heading, callbacks, options)
  return wrapWithCallbacks(Siku.spatial.addBoxZone(coords, size, heading, options), callbacks)
end

--- Add a client-side polygon zone with proximity callbacks.
---@param points table A list of {x, y} points defining the polygon.
---@param minZ number The minimum Z height.
---@param maxZ number The maximum Z height.
---@param callbacks? table Proximity callbacks { onEnter?, onExit?, onInside? }.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The zone with proximity tracking.
local function addClientPolyZone(points, minZ, maxZ, callbacks, options)
  return wrapWithCallbacks(Siku.spatial.addPolyZone(points, minZ, maxZ, options), callbacks)
end

--- Remove a client-side zone with cleanup.
---@param id number The zone ID.
---@return boolean removed Whether the zone was found and removed.
local function removeClientZone(id)
  proximityStates[id] = nil
  insideZones[id] = nil
  Siku.spatial.disableZoneDebug(id)

  local result <const> = Siku.spatial.removeZone(id)

  checkLifecycle()

  return result
end

--- Check if the player is currently inside a zone.
---@param id number The zone ID.
---@return boolean inside Whether the player is inside.
local function isInsideZone(id)
  return insideZones[id] ~= nil
end

--- Get all zone IDs the player is currently inside of.
---@return table zoneIds A list of zone IDs.
local function getCurrentZones()
  local results <const> = {}

  for id in pairs(insideZones) do
    results[#results + 1] = id
  end

  return results
end

return {
  addClientSphereZone = addClientSphereZone,
  addClientBoxZone = addClientBoxZone,
  addClientPolyZone = addClientPolyZone,
  removeClientZone = removeClientZone,
  isInsideZone = isInsideZone,
  getCurrentZones = getCurrentZones,
}
