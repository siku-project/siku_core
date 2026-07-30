local proximityStates = {}
local insideZones = {}
local checkHandle = nil
local hasInsideTick = false

--- The inside tick that fires onInside callbacks every frame.
local function insideTick()
  for id in pairs(insideZones) do
    local state <const> = proximityStates[id]
    if state then
      local internal <const> = _SikuInternal.GetZoneInternal(id)
      if internal and not internal.removed then
        if state.callbacks.onInside then
          state.callbacks.onInside(Siku.GetZoneById(id))
        end
      end
    end
  end
end

--- The coarse check that runs on interval to detect zone enter/exit.
local function coarseCheck()
  local playerCoords <const> = GetEntityCoords(PlayerPedId(), false)
  local nearby <const> = _SikuInternal.GetZoneGrid().getNearby(playerCoords, { radius = SpatialConfig.defaultNearbyRadius })

  local newInside <const> = {}

  for i = 1, #nearby do
    local zoneId <const> = nearby[i].data
    local state <const> = proximityStates[zoneId]
    if state then
      local internal <const> = _SikuInternal.GetZoneInternal(zoneId)
      if internal and not internal.removed then
        state.distance = nearby[i].distance

        if Siku.ContainsZone(internal.shape, playerCoords) then
          newInside[zoneId] = true

          if not state.inside then
            state.inside = true
            if state.callbacks.onEnter then
              state.callbacks.onEnter(Siku.GetZoneById(zoneId))
            end
          end
        end
      end
    end
  end

  for id in pairs(insideZones) do
    if not newInside[id] then
      local state <const> = proximityStates[id]
      if state then
        state.inside = false
        if state.callbacks.onExit then
          local internal <const> = _SikuInternal.GetZoneInternal(id)
          if internal and not internal.removed then
            state.callbacks.onExit(Siku.GetZoneById(id))
          end
        end
      end
    end
  end

  insideZones = newInside

  local hasInside = false
  for id in pairs(insideZones) do
    local state <const> = proximityStates[id]
    if state and state.callbacks.onInside then
      hasInside = true
      break
    end
  end

  if hasInside and not hasInsideTick then
    Siku.RegisterSpatialTick('zones:inside', insideTick)
    hasInsideTick = true
  elseif not hasInside and hasInsideTick then
    Siku.UnregisterSpatialTick('zones:inside')
    hasInsideTick = false
  end
end

--- Start the zone check interval loop.
local function startCheckLoop()
  if checkHandle then return end
  coarseCheck()
  checkHandle = Siku.SetInterval(SpatialConfig.zoneCheckInterval, function()
    coarseCheck()
  end)
end

--- Stop the zone check interval loop.
local function stopCheckLoop()
  if not checkHandle then return end
  Siku.ClearInterval(checkHandle)
  checkHandle = nil
  if hasInsideTick then
    Siku.UnregisterSpatialTick('zones:inside')
    hasInsideTick = false
  end
end

--- Check if any proximity states remain and stop the loop if not.
local function checkLifecycle()
  if not next(proximityStates) then stopCheckLoop() end
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
      owner = GetInvokingResource() or Siku.name,
    }
  end

  local internal <const> = _SikuInternal.GetZoneInternal(zone.id)
  if internal and internal.debug then
    Siku.EnableZoneDebug(zone.id, internal.shape, internal.debugColor)
  end

  local originalRemove <const> = zone.remove

  zone.remove = function()
    proximityStates[zone.id] = nil
    insideZones[zone.id] = nil
    Siku.DisableZoneDebug(zone.id)
    originalRemove()
    checkLifecycle()
  end

  local originalSetDebug <const> = zone.setDebug

  zone.setDebug = function(enabled, color)
    originalSetDebug(enabled, color)
    local int <const> = _SikuInternal.GetZoneInternal(zone.id)
    if enabled and int then
      Siku.EnableZoneDebug(zone.id, int.shape, int.debugColor)
    else
      Siku.DisableZoneDebug(zone.id)
    end
  end

  local stateCount = 0
  for _ in pairs(proximityStates) do stateCount = stateCount + 1 end
  if stateCount == 1 and callbacks then startCheckLoop() end

  return zone
end

--- Add a client-side sphere zone with proximity callbacks.
---@param coords vector3 The center of the sphere.
---@param radius number The radius of the sphere.
---@param callbacks? table Proximity callbacks { onEnter?, onExit?, onInside? }.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The zone with proximity tracking.
function Siku.AddClientSphereZone(coords, radius, callbacks, options)
  return wrapWithCallbacks(Siku.AddSphereZone(coords, radius, options), callbacks)
end

--- Add a client-side box zone with proximity callbacks.
---@param coords vector3 The center of the box.
---@param size vector3 The dimensions (width, length, height).
---@param heading number The heading angle in degrees.
---@param callbacks? table Proximity callbacks { onEnter?, onExit?, onInside? }.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The zone with proximity tracking.
function Siku.AddClientBoxZone(coords, size, heading, callbacks, options)
  return wrapWithCallbacks(Siku.AddBoxZone(coords, size, heading, options), callbacks)
end

--- Add a client-side polygon zone with proximity callbacks.
---@param points table A list of {x, y} points defining the polygon.
---@param minZ number The minimum Z height.
---@param maxZ number The maximum Z height.
---@param callbacks? table Proximity callbacks { onEnter?, onExit?, onInside? }.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The zone with proximity tracking.
function Siku.AddClientPolyZone(points, minZ, maxZ, callbacks, options)
  return wrapWithCallbacks(Siku.AddPolyZone(points, minZ, maxZ, options), callbacks)
end

--- Remove a client-side zone with cleanup.
---@param id number The zone ID.
---@return boolean removed Whether the zone was found and removed.
function Siku.RemoveClientZone(id)
  proximityStates[id] = nil
  insideZones[id] = nil
  Siku.DisableZoneDebug(id)
  local result <const> = Siku.RemoveZone(id)
  checkLifecycle()
  return result
end

--- Check if the player is currently inside a zone.
---@param id number The zone ID.
---@return boolean inside Whether the player is inside.
function Siku.IsInsideZone(id)
  return insideZones[id] ~= nil
end

--- Get all zone IDs the player is currently inside of.
---@return table zoneIds A list of zone IDs.
function Siku.GetCurrentZones()
  local results <const> = {}
  for id in pairs(insideZones) do
    results[#results + 1] = id
  end
  return results
end

AddEventHandler('onResourceStop', function(resource)
  for id, state in pairs(proximityStates) do
    if state.owner == resource then
      proximityStates[id] = nil
      insideZones[id] = nil
      Siku.DisableZoneDebug(id)
    end
  end
  checkLifecycle()
end)
