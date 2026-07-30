local zones = {}
local zoneGrid = Siku.CreateSpatialGrid()
local nextZoneId = 1

local DEFAULT_DEBUG_COLOR <const> = { r = 0, g = 150, b = 255, a = 80 }

--- Get the center coordinates of a zone shape.
---@param shape table The zone shape.
---@return vector3 coords The center coordinates.
local function getShapeCoords(shape)
  if shape.type == 'sphere' or shape.type == 'box' then
    return shape.coords
  elseif shape.type == 'poly' then
    return vector3(shape.centroid.x, shape.centroid.y, (shape.minZ + shape.maxZ) / 2)
  end
end

--- Get the bounding radius of a zone shape.
---@param shape table The zone shape.
---@return number radius The bounding radius.
local function getShapeRadius(shape)
  if shape.type == 'sphere' then
    return shape.radius
  elseif shape.type == 'box' then
    return math.sqrt((shape.size.x / 2) ^ 2 + (shape.size.y / 2) ^ 2)
  elseif shape.type == 'poly' then
    return shape.boundingRadius
  end
end

--- Build a public ActiveZone interface from an internal zone.
---@param internal table The internal zone data.
---@return table activeZone The public zone interface.
local function buildActiveZone(internal)
  local zone <const> = {
    id = internal.id,
    shape = internal.shape,
    data = internal.data,
    tags = internal.tags,
  }

  --- Check if coordinates are inside this zone.
  ---@param coords vector3 The coordinates to test.
  ---@return boolean inside Whether the coordinates are inside the zone.
  function zone.contains(coords)
    return Siku.ContainsZone(internal.shape, coords)
  end

  --- Remove this zone from the registry.
  function zone.remove()
    if internal.removed then return end
    internal.removed = true
    zoneGrid.remove(internal.id)
    zones[internal.id] = nil
  end

  --- Enable or disable debug visualization for this zone.
  ---@param enabled boolean Whether to enable debug.
  ---@param color? table RGBA color { r, g, b, a }.
  function zone.setDebug(enabled, color)
    internal.debug = enabled
    if color then internal.debugColor = color end
  end

  return zone
end

--- Register a zone with a shape and options.
---@param shape table The zone shape.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The public zone interface.
local function registerZone(shape, options)
  local id <const> = nextZoneId
  nextZoneId = nextZoneId + 1

  local tagSet <const> = {}
  if options and options.tags then
    for i = 1, #options.tags do
      tagSet[options.tags[i]] = true
    end
  end

  local internal <const> = {
    id = id,
    shape = shape,
    data = options and options.data or nil,
    tags = tagSet,
    debug = options and options.debug or false,
    debugColor = (options and options.debugColor) or DEFAULT_DEBUG_COLOR,
    owner = GetInvokingResource() or Siku.name,
    removed = false,
  }

  zones[id] = internal
  local coords <const> = getShapeCoords(shape)
  local radius <const> = getShapeRadius(shape)
  zoneGrid.add(coords, radius, id, options and options.tags)

  return buildActiveZone(internal)
end

--- Add a sphere zone.
---@param coords vector3 The center of the sphere.
---@param radius number The radius of the sphere.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The public zone interface.
function Siku.AddSphereZone(coords, radius, options)
  return registerZone(Siku.CreateSphereShape(coords, radius), options)
end

--- Add a box zone with heading rotation.
---@param coords vector3 The center of the box.
---@param size vector3 The dimensions (width, length, height).
---@param heading number The heading angle in degrees.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The public zone interface.
function Siku.AddBoxZone(coords, size, heading, options)
  return registerZone(Siku.CreateBoxShape(coords, size, heading), options)
end

--- Add a polygon zone from 2D points with a Z range.
---@param points table A list of {x, y} points defining the polygon.
---@param minZ number The minimum Z height.
---@param maxZ number The maximum Z height.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The public zone interface.
function Siku.AddPolyZone(points, minZ, maxZ, options)
  return registerZone(Siku.CreatePolyShape(points, minZ, maxZ), options)
end

--- Remove a zone by ID.
---@param id number The zone ID.
---@return boolean removed Whether the zone was found and removed.
function Siku.RemoveZone(id)
  local internal <const> = zones[id]
  if not internal then return false end
  internal.removed = true
  zoneGrid.remove(id)
  zones[id] = nil
  return true
end

--- Get a zone by its ID.
---@param id number The zone ID.
---@return table|nil activeZone The zone or nil if not found.
function Siku.GetZoneById(id)
  local internal <const> = zones[id]
  if not internal or internal.removed then return nil end
  return buildActiveZone(internal)
end

--- Get all zones that contain the given coordinates.
---@param coords vector3 The coordinates to test.
---@param tags? table Optional tags to filter by.
---@return table zones A list of active zones containing the point.
function Siku.GetZonesAtCoords(coords, tags)
  local nearby <const> = zoneGrid.getNearby(coords, { radius = 500, tags = tags })
  local results <const> = {}

  for i = 1, #nearby do
    local internal <const> = zones[nearby[i].data]
    if internal and not internal.removed then
      if Siku.ContainsZone(internal.shape, coords) then
        results[#results + 1] = buildActiveZone(internal)
      end
    end
  end

  return results
end

--- Get all registered zones.
---@return table zones A list of all active zones.
function Siku.GetAllZones()
  local results <const> = {}
  for _, internal in pairs(zones) do
    if not internal.removed then
      results[#results + 1] = buildActiveZone(internal)
    end
  end
  return results
end

--- Get the internal zone grid (for client-side integration).
---@return table zoneGrid The spatial grid used by zones.
function _SikuInternal.GetZoneGrid()
  return zoneGrid
end

--- Get the internal zone data (for client-side integration).
---@param id number The zone ID.
---@return table|nil internal The internal zone data.
function _SikuInternal.GetZoneInternal(id)
  return zones[id]
end

AddEventHandler('onResourceStop', function(resource)
  for id, internal in pairs(zones) do
    if internal.owner == resource then
      internal.removed = true
      zoneGrid.remove(id)
      zones[id] = nil
    end
  end
end)
