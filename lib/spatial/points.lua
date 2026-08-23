local NEARBY_TICK_KEY <const> = 'points:nearby'

local points = {}
local pointGrid <const> = internal.createGrid()
local insideSet = {}
local nearbySet = {}
local closestId = nil
local checkHandle = nil
local hasNearbyTick = false

local removePoint

--- Build a public ActivePoint interface from an internal point.
---@param entry table The internal point data.
---@return table activePoint The public point interface.
local function buildActivePoint(entry)
  return {
    id = entry.id,
    coords = entry.coords,
    radius = entry.radius,
    data = entry.data,
    tags = entry.tags,
    isInside = entry.inside,
    currentDistance = entry.currentDistance,
    remove = function()
      removePoint(entry.id)
    end,
  }
end

--- Resolve a point that still exists.
---@param id number The point ID.
---@return table? entry The internal point, nil when it was removed.
local function livePoint(id)
  local point <const> = points[id]

  if not point or point.removed then
    return nil
  end

  return point
end

--- The nearby tick that updates distances and fires onNearby callbacks.
local function nearbyTick()
  local playerCoords <const> = GetEntityCoords(PlayerPedId(), false)

  for id in pairs(nearbySet) do
    local point <const> = livePoint(id)

    if point then
      local dist <const> = #(playerCoords - point.coords)
      point.currentDistance = dist

      if point.onNearby then
        point.onNearby(buildActivePoint(point), dist)
      end
    end
  end
end

--- Classify one nearby point as inside or merely nearby, firing onEnter on entrance.
---@param point table The internal point.
---@param dist number The distance to the player.
---@param scan table The scan accumulator { inside, nearby, closestId, closestDist, nearbyRadius }.
local function classifyPoint(point, dist, scan)
  point.currentDistance = dist

  if dist > point.radius then
    if dist <= scan.nearbyRadius then
      scan.nearby[point.id] = true
    end

    return
  end

  scan.inside[point.id] = true
  scan.nearby[point.id] = true

  if dist < scan.closestDist then
    scan.closestDist = dist
    scan.closestId = point.id
  end

  if insideSet[point.id] then
    return
  end

  point.inside = true

  if point.onEnter then
    point.onEnter(buildActivePoint(point))
  end
end

--- Fire onExit for every point the player just left.
---@param newInside table The set of points the player is inside after this check.
local function trackExits(newInside)
  for id in pairs(insideSet) do
    if not newInside[id] then
      local point <const> = livePoint(id)

      if point then
        point.inside = false

        if point.onExit then
          point.onExit(buildActivePoint(point))
        end
      end
    end
  end
end

--- Start or stop the per-frame nearby tick depending on whether any nearby point wants it.
local function syncNearbyTick()
  local hasOnNearby = false

  for id in pairs(nearbySet) do
    local point <const> = livePoint(id)

    if point and point.onNearby then
      hasOnNearby = true
      break
    end
  end

  if hasOnNearby and not hasNearbyTick then
    Siku.spatial.registerTick(NEARBY_TICK_KEY, nearbyTick)
    hasNearbyTick = true
  elseif not hasOnNearby and hasNearbyTick then
    Siku.spatial.unregisterTick(NEARBY_TICK_KEY)
    hasNearbyTick = false
  end
end

--- The coarse check that runs on interval to detect enter/exit/nearby.
local function coarseCheck()
  local playerCoords <const> = GetEntityCoords(PlayerPedId(), false)
  local nearbyRadius <const> = Siku.config.spatial.defaultNearbyRadius
  local nearby <const> = pointGrid.getNearby(playerCoords, { radius = nearbyRadius })

  local scan <const> = {
    inside = {},
    nearby = {},
    closestId = nil,
    closestDist = math.huge,
    nearbyRadius = nearbyRadius,
  }

  for i = 1, #nearby do
    local point <const> = livePoint(nearby[i].id)

    if point then
      classifyPoint(point, #(playerCoords - point.coords), scan)
    end
  end

  trackExits(scan.inside)

  insideSet = scan.inside
  nearbySet = scan.nearby
  closestId = scan.closestId

  syncNearbyTick()
end

--- Start the coarse check interval loop.
local function startCheckLoop()
  if checkHandle then
    return
  end

  coarseCheck()

  checkHandle = Siku.timers.setInterval(Siku.config.spatial.pointCheckInterval, function()
    coarseCheck()
  end)
end

--- Stop the coarse check interval loop.
local function stopCheckLoop()
  if not checkHandle then
    return
  end

  Siku.timers.clearInterval(checkHandle)
  checkHandle = nil

  if hasNearbyTick then
    Siku.spatial.unregisterTick(NEARBY_TICK_KEY)
    hasNearbyTick = false
  end
end

--- Add a proximity point that tracks player enter/exit/nearby events.
---@param options table Point options { coords, radius, data?, tags?, onEnter?, onExit?, onNearby? }.
---@return table activePoint The public point interface.
local function addPoint(options)
  local entry <const> = {
    id = 0,
    coords = options.coords,
    radius = options.radius,
    data = options.data or nil,
    tags = {},
    onEnter = options.onEnter,
    onExit = options.onExit,
    onNearby = options.onNearby,
    inside = false,
    currentDistance = math.huge,
    removed = false,
  }

  if options.tags then
    for i = 1, #options.tags do
      entry.tags[options.tags[i]] = true
    end
  end

  local id <const> = pointGrid.add(options.coords, options.radius, nil, options.tags)
  entry.id = id

  local wasEmpty <const> = next(points) == nil

  points[id] = entry

  if wasEmpty then
    startCheckLoop()
  end

  return buildActivePoint(entry)
end

--- Remove a proximity point.
---@param id number The point ID.
---@return boolean removed Whether the point was found and removed.
removePoint = function(id)
  local point <const> = points[id]

  if not point then
    return false
  end

  point.removed = true
  point.inside = false
  insideSet[id] = nil
  nearbySet[id] = nil

  if closestId == id then
    closestId = nil
  end

  pointGrid.remove(id)
  points[id] = nil

  if not next(points) then
    stopCheckLoop()
  end

  return true
end

--- Get the closest point the player is inside of.
---@return table|nil activePoint The closest point or nil.
local function getClosestPoint()
  if not closestId then
    return nil
  end

  local point <const> = livePoint(closestId)

  return point and buildActivePoint(point) or nil
end

--- Collect the public interfaces of every live point in a set.
---@param set table The set of point IDs.
---@return table points A list of active points.
local function collectPoints(set)
  local results <const> = {}

  for id in pairs(set) do
    local point <const> = livePoint(id)

    if point then
      results[#results + 1] = buildActivePoint(point)
    end
  end

  return results
end

--- Get all points the player is currently inside of.
---@return table points A list of active points.
local function getPointsInside()
  return collectPoints(insideSet)
end

--- Get all points that are nearby the player.
---@return table points A list of active points.
local function getPointsNearby()
  return collectPoints(nearbySet)
end

return {
  addPoint = addPoint,
  removePoint = removePoint,
  getClosestPoint = getClosestPoint,
  getPointsInside = getPointsInside,
  getPointsNearby = getPointsNearby,
}
