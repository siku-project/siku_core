--- Check if a point is inside a 2D polygon using the ray casting algorithm.
---@param vertices table A list of {x, y} vertices defining the polygon.
---@param point table A point with x and y fields.
---@return boolean inside Whether the point is inside the polygon.
local function pointInPolygon2D(vertices, point)
  local crossings = 0
  local len <const> = #vertices

  for i = 1, len do
    local a <const> = vertices[i]
    local b <const> = vertices[(i % len) + 1]

    if (a.y <= point.y and b.y > point.y) or (b.y <= point.y and a.y > point.y) then
      local t <const> = (point.y - a.y) / (b.y - a.y)
      if point.x < a.x + t * (b.x - a.x) then
        crossings = crossings + 1
      end
    end
  end

  return crossings % 2 == 1
end

--- Check if coordinates are inside a sphere shape.
---@param shape table The sphere shape { type, coords, radius }.
---@param coords vector3 The coordinates to test.
---@return boolean inside Whether the point is inside the sphere.
function Siku.ContainsSphere(shape, coords)
  local dx <const> = coords.x - shape.coords.x
  local dy <const> = coords.y - shape.coords.y
  local dz <const> = coords.z - shape.coords.z
  return dx * dx + dy * dy + dz * dz <= shape.radius * shape.radius
end

--- Check if coordinates are inside a box shape.
---@param shape table The box shape { type, coords, size, heading, vertices, minZ, maxZ }.
---@param coords vector3 The coordinates to test.
---@return boolean inside Whether the point is inside the box.
function Siku.ContainsBox(shape, coords)
  if coords.z < shape.minZ or coords.z > shape.maxZ then return false end
  return pointInPolygon2D(shape.vertices, coords)
end

--- Check if coordinates are inside a polygon shape.
---@param shape table The poly shape { type, points, centroid, minZ, maxZ, boundingRadius }.
---@param coords vector3 The coordinates to test.
---@return boolean inside Whether the point is inside the polygon.
function Siku.ContainsPoly(shape, coords)
  if coords.z < shape.minZ or coords.z > shape.maxZ then return false end
  return pointInPolygon2D(shape.points, coords)
end

--- Check if coordinates are inside any zone shape (sphere, box, or poly).
---@param shape table The zone shape.
---@param coords vector3 The coordinates to test.
---@return boolean inside Whether the point is inside the zone.
function Siku.ContainsZone(shape, coords)
  if shape.type == 'sphere' then
    return Siku.ContainsSphere(shape, coords)
  elseif shape.type == 'box' then
    return Siku.ContainsBox(shape, coords)
  elseif shape.type == 'poly' then
    return Siku.ContainsPoly(shape, coords)
  end
  return false
end

--- Create a sphere shape definition.
---@param coords vector3 The center of the sphere.
---@param radius number The radius of the sphere.
---@return table shape The sphere shape.
function Siku.CreateSphereShape(coords, radius)
  return { type = 'sphere', coords = coords, radius = radius }
end

--- Create a box shape definition with heading rotation.
---@param coords vector3 The center of the box.
---@param size vector3 The dimensions of the box (width, length, height).
---@param heading number The heading angle in degrees.
---@return table shape The box shape.
function Siku.CreateBoxShape(coords, size, heading)
  local halfW <const> = size.x / 2
  local halfL <const> = size.y / 2
  local halfH <const> = size.z / 2

  local offsets <const> = {
    vector3(-halfW, -halfL, 0),
    vector3(halfW, -halfL, 0),
    vector3(halfW, halfL, 0),
    vector3(-halfW, halfL, 0),
  }

  local vertices <const> = {}
  for i = 1, 4 do
    vertices[i] = Siku.math.getRelativeCoords(coords, heading, offsets[i])
  end

  return {
    type = 'box',
    coords = coords,
    size = size,
    heading = heading,
    vertices = vertices,
    minZ = coords.z - halfH,
    maxZ = coords.z + halfH,
  }
end

--- Create a polygon shape definition from 2D points with a Z range.
---@param points table A list of {x, y} points defining the polygon.
---@param minZ number The minimum Z height.
---@param maxZ number The maximum Z height.
---@return table shape The polygon shape.
function Siku.CreatePolyShape(points, minZ, maxZ)
  local cx, cy = 0, 0
  local len <const> = #points

  for i = 1, len do
    cx = cx + points[i].x
    cy = cy + points[i].y
  end

  local centroid <const> = { x = cx / len, y = cy / len }

  local maxDistSq = 0
  for i = 1, len do
    local dx <const> = points[i].x - centroid.x
    local dy <const> = points[i].y - centroid.y
    local dSq <const> = dx * dx + dy * dy
    if dSq > maxDistSq then maxDistSq = dSq end
  end

  return {
    type = 'poly',
    points = points,
    centroid = centroid,
    minZ = minZ,
    maxZ = maxZ,
    boundingRadius = math.sqrt(maxDistSq),
  }
end
