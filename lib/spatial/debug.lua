local DEBUG_TICK_KEY <const> = 'zones:debug'
local MAX_RENDER_DISTANCE <const> = 200
local MAX_RENDER_DIST_SQ <const> = MAX_RENDER_DISTANCE * MAX_RENDER_DISTANCE
local SPHERE_MARKER <const> = 28
local OPAQUE <const> = 255
local MARKER_FLAGS <const> = 2

local debugZones = {}
local active = false

--- Get the center point of a zone shape for distance culling.
---@param shape table The zone shape.
---@return vector3 center The center coordinates.
local function getShapeCenter(shape)
  if shape.type == internal.SHAPE_POLY then
    return vector3(shape.centroid.x, shape.centroid.y, (shape.minZ + shape.maxZ) / 2)
  end

  return shape.coords
end

--- Draw a debug sphere using DrawMarker.
---@param shape table The sphere shape.
---@param c table RGBA color { r, g, b, a }.
local function drawDebugSphere(shape, c)
  local d <const> = shape.radius * 2

  DrawMarker(SPHERE_MARKER, shape.coords.x, shape.coords.y, shape.coords.z, 0, 0, 0, 0, 0, 0, d, d, d, c.r, c.g, c.b, math.floor(c.a * OPAQUE), false, false, MARKER_FLAGS, false, false, false, false)
end

--- Draw a debug wall between two points with a Z range.
---@param a vector3 First point.
---@param b vector3 Second point.
---@param minZ number Minimum Z height.
---@param maxZ number Maximum Z height.
---@param c table RGBA color { r, g, b, a }.
local function drawDebugWall(a, b, minZ, maxZ, c)
  local alpha <const> = math.floor(c.a * OPAQUE)

  DrawPoly(a.x, a.y, minZ, b.x, b.y, minZ, a.x, a.y, maxZ, c.r, c.g, c.b, alpha)
  DrawPoly(a.x, a.y, maxZ, b.x, b.y, minZ, a.x, a.y, minZ, c.r, c.g, c.b, alpha)
  DrawPoly(b.x, b.y, minZ, a.x, a.y, maxZ, b.x, b.y, maxZ, c.r, c.g, c.b, alpha)
  DrawPoly(b.x, b.y, maxZ, a.x, a.y, maxZ, b.x, b.y, minZ, c.r, c.g, c.b, alpha)

  DrawLine(a.x, a.y, minZ, a.x, a.y, maxZ, c.r, c.g, c.b, OPAQUE)
  DrawLine(a.x, a.y, minZ, b.x, b.y, minZ, c.r, c.g, c.b, OPAQUE)
  DrawLine(a.x, a.y, maxZ, b.x, b.y, maxZ, c.r, c.g, c.b, OPAQUE)
end

--- Draw a debug box shape.
---@param shape table The box shape.
---@param c table RGBA color { r, g, b, a }.
local function drawDebugBox(shape, c)
  local v <const> = shape.vertices

  for i = 1, #v do
    drawDebugWall(v[i], v[(i % #v) + 1], shape.minZ, shape.maxZ, c)
  end
end

--- Draw a debug polygon shape.
---@param shape table The poly shape.
---@param c table RGBA color { r, g, b, a }.
local function drawDebugPoly(shape, c)
  local pts <const> = shape.points

  for i = 1, #pts do
    local a <const> = pts[i]
    local b <const> = pts[(i % #pts) + 1]

    drawDebugWall(vector3(a.x, a.y, 0), vector3(b.x, b.y, 0), shape.minZ, shape.maxZ, c)
  end
end

--- Draw one debug zone with the renderer matching its shape.
---@param zone table The debug zone { shape, color }.
local function drawDebugZone(zone)
  if zone.shape.type == internal.SHAPE_SPHERE then
    drawDebugSphere(zone.shape, zone.color)
  elseif zone.shape.type == internal.SHAPE_BOX then
    drawDebugBox(zone.shape, zone.color)
  elseif zone.shape.type == internal.SHAPE_POLY then
    drawDebugPoly(zone.shape, zone.color)
  end
end

--- The debug tick function that renders all active debug zones.
local function debugTick()
  local playerCoords <const> = GetEntityCoords(PlayerPedId(), false)

  for _, zone in pairs(debugZones) do
    local center <const> = getShapeCenter(zone.shape)
    local dx <const> = playerCoords.x - center.x
    local dy <const> = playerCoords.y - center.y
    local dz <const> = playerCoords.z - center.z

    if dx * dx + dy * dy + dz * dz <= MAX_RENDER_DIST_SQ then
      drawDebugZone(zone)
    end
  end
end

--- Update the debug tick registration based on active debug zones.
local function updateTick()
  if next(debugZones) and not active then
    Siku.spatial.registerTick(DEBUG_TICK_KEY, debugTick)
    active = true
  elseif not next(debugZones) and active then
    Siku.spatial.unregisterTick(DEBUG_TICK_KEY)
    active = false
  end
end

--- Enable debug visualization for a zone.
---@param id number The zone ID.
---@param shape table The zone shape.
---@param color table RGBA color { r, g, b, a }.
local function enableZoneDebug(id, shape, color)
  debugZones[id] = { shape = shape, color = color }
  updateTick()
end

--- Disable debug visualization for a zone.
---@param id number The zone ID.
local function disableZoneDebug(id)
  debugZones[id] = nil
  updateTick()
end

--- Check if a zone has debug visualization active.
---@param id number The zone ID.
---@return boolean isActive Whether debug is active.
local function isZoneDebugActive(id)
  return debugZones[id] ~= nil
end

return {
  enableZoneDebug = enableZoneDebug,
  disableZoneDebug = disableZoneDebug,
  isZoneDebugActive = isZoneDebugActive,
}
