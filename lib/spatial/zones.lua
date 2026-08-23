local DEFAULT_DEBUG_COLOR <const> = { r = 0, g = 150, b = 255, a = 80 }
local LOOKUP_RADIUS <const> = 500

local zones = {}
local zoneGrid <const> = internal.createGrid()
local nextZoneId = 1

--- Get the center coordinates of a zone shape.
---@param shape table The zone shape.
---@return vector3 coords The center coordinates.
local function getShapeCoords(shape)
  if shape.type == internal.SHAPE_POLY then
    return vector3(shape.centroid.x, shape.centroid.y, (shape.minZ + shape.maxZ) / 2)
  end

  return shape.coords
end

--- Get the bounding radius of a zone shape.
---@param shape table The zone shape.
---@return number radius The bounding radius.
local function getShapeRadius(shape)
  if shape.type == internal.SHAPE_SPHERE then
    return shape.radius
  end

  if shape.type == internal.SHAPE_BOX then
    return math.sqrt((shape.size.x / 2) ^ 2 + (shape.size.y / 2) ^ 2)
  end

  return shape.boundingRadius
end

--- Build a public ActiveZone interface from an internal zone.
---@param entry table The internal zone data.
---@return table activeZone The public zone interface.
local function buildActiveZone(entry)
  local zone <const> = {
    id = entry.id,
    shape = entry.shape,
    data = entry.data,
    tags = entry.tags,
  }

  --- Check if coordinates are inside this zone.
  ---@param coords vector3 The coordinates to test.
  ---@return boolean inside Whether the coordinates are inside the zone.
  function zone.contains(coords)
    return internal.containsZone(entry.shape, coords)
  end

  --- Remove this zone from the registry.
  function zone.remove()
    if entry.removed then
      return
    end

    entry.removed = true
    zoneGrid.remove(entry.id)
    zones[entry.id] = nil
  end

  --- Enable or disable debug visualization for this zone.
  ---@param enabled boolean Whether to enable debug.
  ---@param color? table RGBA color { r, g, b, a }.
  function zone.setDebug(enabled, color)
    entry.debug = enabled

    if color then
      entry.debugColor = color
    end
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

  local entry <const> = {
    id = id,
    shape = shape,
    data = options and options.data or nil,
    tags = tagSet,
    debug = options and options.debug or false,
    debugColor = (options and options.debugColor) or DEFAULT_DEBUG_COLOR,
    removed = false,
  }

  zones[id] = entry
  zoneGrid.add(getShapeCoords(shape), getShapeRadius(shape), id, options and options.tags)

  return buildActiveZone(entry)
end

--- Add a sphere zone.
---@param coords vector3 The center of the sphere.
---@param radius number The radius of the sphere.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The public zone interface.
local function addSphereZone(coords, radius, options)
  return registerZone(Siku.spatial.createSphereShape(coords, radius), options)
end

--- Add a box zone with heading rotation.
---@param coords vector3 The center of the box.
---@param size vector3 The dimensions (width, length, height).
---@param heading number The heading angle in degrees.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The public zone interface.
local function addBoxZone(coords, size, heading, options)
  return registerZone(Siku.spatial.createBoxShape(coords, size, heading), options)
end

--- Add a polygon zone from 2D points with a Z range.
---@param points table A list of {x, y} points defining the polygon.
---@param minZ number The minimum Z height.
---@param maxZ number The maximum Z height.
---@param options? table Zone options { tags?, data?, debug?, debugColor? }.
---@return table activeZone The public zone interface.
local function addPolyZone(points, minZ, maxZ, options)
  return registerZone(Siku.spatial.createPolyShape(points, minZ, maxZ), options)
end

--- Remove a zone by ID.
---@param id number The zone ID.
---@return boolean removed Whether the zone was found and removed.
local function removeZone(id)
  local entry <const> = zones[id]

  if not entry then
    return false
  end

  entry.removed = true
  zoneGrid.remove(id)
  zones[id] = nil

  return true
end

--- Get a zone by its ID.
---@param id number The zone ID.
---@return table|nil activeZone The zone or nil if not found.
local function getZoneById(id)
  local entry <const> = zones[id]

  if not entry or entry.removed then
    return nil
  end

  return buildActiveZone(entry)
end

--- Get all zones that contain the given coordinates.
---@param coords vector3 The coordinates to test.
---@param tags? table Optional tags to filter by.
---@return table zones A list of active zones containing the point.
local function getZonesAtCoords(coords, tags)
  local nearby <const> = zoneGrid.getNearby(coords, { radius = LOOKUP_RADIUS, tags = tags })
  local results <const> = {}

  for i = 1, #nearby do
    local entry <const> = zones[nearby[i].data]

    if entry and not entry.removed and internal.containsZone(entry.shape, coords) then
      results[#results + 1] = buildActiveZone(entry)
    end
  end

  return results
end

--- Get all registered zones.
---@return table zones A list of all active zones.
local function getAllZones()
  local results <const> = {}

  for _, entry in pairs(zones) do
    if not entry.removed then
      results[#results + 1] = buildActiveZone(entry)
    end
  end

  return results
end

--- Get the grid indexing every zone, for the client-side tracking part.
---@return table zoneGrid The spatial grid used by zones.
function internal.getZoneGrid()
  return zoneGrid
end

--- Get the internal data of a zone, for the client-side tracking part.
---@param id number The zone ID.
---@return table|nil entry The internal zone data.
function internal.getZoneInternal(id)
  return zones[id]
end

return {
  addSphereZone = addSphereZone,
  addBoxZone = addBoxZone,
  addPolyZone = addPolyZone,
  removeZone = removeZone,
  getZoneById = getZoneById,
  getZonesAtCoords = getZonesAtCoords,
  getAllZones = getAllZones,
}
