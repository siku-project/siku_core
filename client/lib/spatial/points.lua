local points = {}
local pointGrid = Siku.CreateSpatialGrid()
local insideSet = {}
local nearbySet = {}
local closestId = nil
local checkHandle = nil
local hasNearbyTick = false

--- Build a public ActivePoint interface from an internal point.
---@param internal table The internal point data.
---@return table activePoint The public point interface.
local function buildActivePoint(internal)
  return {
    id = internal.id,
    coords = internal.coords,
    radius = internal.radius,
    data = internal.data,
    tags = internal.tags,
    isInside = internal.inside,
    currentDistance = internal.currentDistance,
    remove = function()
      Siku.RemovePoint(internal.id)
    end,
  }
end

--- The nearby tick that updates distances and fires onNearby callbacks.
local function nearbyTick()
  local playerCoords <const> = GetEntityCoords(PlayerPedId(), false)

  for id in pairs(nearbySet) do
    local point <const> = points[id]
    if point and not point.removed then
      local dist <const> = #(playerCoords - point.coords)
      point.currentDistance = dist

      if point.onNearby then
        point.onNearby(buildActivePoint(point), dist)
      end
    end
  end
end

--- The coarse check that runs on interval to detect enter/exit/nearby.
local function coarseCheck()
  local playerCoords <const> = GetEntityCoords(PlayerPedId(), false)
  local nearby <const> = pointGrid.getNearby(playerCoords, { radius = SpatialConfig.defaultNearbyRadius })

  local newInside <const> = {}
  local newNearby <const> = {}
  local newClosestId = nil
  local newClosestDist = math.huge

  for i = 1, #nearby do
    local entry <const> = nearby[i]
    local point <const> = points[entry.id]
    if point and not point.removed then
      local dist <const> = #(playerCoords - point.coords)
      point.currentDistance = dist

      if dist <= point.radius then
        newInside[point.id] = true
        newNearby[point.id] = true

        if dist < newClosestDist then
          newClosestDist = dist
          newClosestId = point.id
        end

        if not insideSet[point.id] then
          point.inside = true
          if point.onEnter then point.onEnter(buildActivePoint(point)) end
        end
      elseif dist <= SpatialConfig.defaultNearbyRadius then
        newNearby[point.id] = true
      end
    end
  end

  for id in pairs(insideSet) do
    if not newInside[id] then
      local point <const> = points[id]
      if point and not point.removed then
        point.inside = false
        if point.onExit then point.onExit(buildActivePoint(point)) end
      end
    end
  end

  insideSet = newInside
  nearbySet = newNearby
  closestId = newClosestId

  local hasOnNearby = false
  for id in pairs(nearbySet) do
    local p <const> = points[id]
    if p and not p.removed and p.onNearby then
      hasOnNearby = true
      break
    end
  end

  if hasOnNearby and not hasNearbyTick then
    Siku.RegisterSpatialTick('points:nearby', nearbyTick)
    hasNearbyTick = true
  elseif not hasOnNearby and hasNearbyTick then
    Siku.UnregisterSpatialTick('points:nearby')
    hasNearbyTick = false
  end
end

--- Start the coarse check interval loop.
local function startCheckLoop()
  if checkHandle then return end

  coarseCheck()
  checkHandle = Siku.SetInterval(SpatialConfig.pointCheckInterval, function()
    coarseCheck()
  end)
end

--- Stop the coarse check interval loop.
local function stopCheckLoop()
  if not checkHandle then return end
  Siku.ClearInterval(checkHandle)
  checkHandle = nil

  if hasNearbyTick then
    Siku.UnregisterSpatialTick('points:nearby')
    hasNearbyTick = false
  end
end

--- Add a proximity point that tracks player enter/exit/nearby events.
---@param options table Point options { coords, radius, data?, tags?, onEnter?, onExit?, onNearby? }.
---@return table activePoint The public point interface.
function Siku.AddPoint(options)
  local internal = {
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
    owner = GetInvokingResource() or Siku.name,
    removed = false,
  }

  if options.tags then
    for i = 1, #options.tags do
      internal.tags[options.tags[i]] = true
    end
  end

  local id <const> = pointGrid.add(options.coords, options.radius, nil, options.tags)
  internal.id = id

  points[id] = internal

  local pointCount = 0
  for _ in pairs(points) do pointCount = pointCount + 1 end
  if pointCount == 1 then startCheckLoop() end

  return buildActivePoint(internal)
end

--- Remove a proximity point.
---@param id number The point ID.
---@return boolean removed Whether the point was found and removed.
function Siku.RemovePoint(id)
  local point <const> = points[id]
  if not point then return false end

  point.removed = true
  point.inside = false
  insideSet[id] = nil
  nearbySet[id] = nil
  if closestId == id then closestId = nil end
  pointGrid.remove(id)
  points[id] = nil

  if not next(points) then stopCheckLoop() end

  return true
end

--- Get the closest point the player is inside of.
---@return table|nil activePoint The closest point or nil.
function Siku.GetClosestPoint()
  if not closestId then return nil end
  local point <const> = points[closestId]
  if not point or point.removed then return nil end
  return buildActivePoint(point)
end

--- Get all points the player is currently inside of.
---@return table points A list of active points.
function Siku.GetPointsInside()
  local results <const> = {}
  for id in pairs(insideSet) do
    local point <const> = points[id]
    if point and not point.removed then
      results[#results + 1] = buildActivePoint(point)
    end
  end
  return results
end

--- Get all points that are nearby the player.
---@return table points A list of active points.
function Siku.GetPointsNearby()
  local results <const> = {}
  for id in pairs(nearbySet) do
    local point <const> = points[id]
    if point and not point.removed then
      results[#results + 1] = buildActivePoint(point)
    end
  end
  return results
end

AddEventHandler('onResourceStop', function(resource)
  local owned <const> = {}

  for id, point in pairs(points) do
    if point.owner == resource then
      owned[#owned + 1] = id
    end
  end

  for i = 1, #owned do
    Siku.RemovePoint(owned[i])
  end
end)
