local DEFAULT_DISTANCE <const> = 2.0

--- Resolve an optional model filter into a hash.
---@param model? string|number The model name or hash.
---@return number? hash The model hash, or nil when no filter applies.
local function resolveModelHash(model)
  if not model then
    return nil
  end

  return type(model) == 'string' and GetHashKey(model) or model
end

--- Sort entries by ascending distance.
---@param a table The first entry.
---@param b table The second entry.
---@return boolean closer Whether a is closer than b.
local function byDistance(a, b)
  return a.distance < b.distance
end

--- Resolve the vehicle the local player sits in, when it must be skipped.
---@param includeCurrentVehicle? boolean Whether the current vehicle stays in the results.
---@return number? vehicle The vehicle to skip, or nil.
local function resolveExcludedVehicle(includeCurrentVehicle)
  if includeCurrentVehicle then
    return nil
  end

  local vehicle <const> = GetVehiclePedIsIn(PlayerPedId(), false)

  return vehicle ~= 0 and vehicle or nil
end

--- Find the closest entity of a pool matching a filter.
---@param pool table The entity handles to scan.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param accepts fun(entity: number): boolean Whether an entity may be considered.
---@return table|nil entity The closest entity { entity, coords, distance } or nil if none found.
local function findClosest(pool, coords, maxDistance, accepts)
  local maxDist <const> = maxDistance or DEFAULT_DISTANCE
  local best = nil

  for i = 1, #pool do
    local entity <const> = pool[i]

    if accepts(entity) then
      local entityCoords <const> = GetEntityCoords(entity)
      local dist <const> = #(coords - entityCoords)

      if dist < maxDist and (not best or dist < best.distance) then
        best = {
          entity = entity,
          coords = entityCoords,
          distance = dist,
        }
      end
    end
  end

  return best
end

--- Collect every entity of a pool within a distance, sorted by proximity.
---@param pool table The entity handles to scan.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param accepts fun(entity: number): boolean Whether an entity may be considered.
---@return table entities A sorted list of { entity, coords, distance } tables.
local function findNearby(pool, coords, maxDistance, accepts)
  local maxDist <const> = maxDistance or DEFAULT_DISTANCE
  local results <const> = {}

  for i = 1, #pool do
    local entity <const> = pool[i]

    if accepts(entity) then
      local entityCoords <const> = GetEntityCoords(entity)
      local dist <const> = #(coords - entityCoords)

      if dist < maxDist then
        results[#results + 1] = {
          entity = entity,
          coords = entityCoords,
          distance = dist,
        }
      end
    end
  end

  table.sort(results, byDistance)

  return results
end

--- Build the filter accepting objects of an optional model.
---@param model? string|number Optional model name or hash to filter by.
---@return fun(entity: number): boolean accepts The filter.
local function objectFilter(model)
  local filterHash <const> = resolveModelHash(model)

  return function(entity)
    return not filterHash or GetEntityModel(entity) == filterHash
  end
end

--- Build the filter accepting peds of an optional model, skipping players unless asked.
---@param model? string|number Optional model name or hash to filter by.
---@param includePlayers? boolean Whether to include player peds (default: false).
---@return fun(entity: number): boolean accepts The filter.
local function pedFilter(model, includePlayers)
  local filterHash <const> = resolveModelHash(model)

  return function(entity)
    return (includePlayers or not IsPedAPlayer(entity)) and not (filterHash and GetEntityModel(entity) ~= filterHash)
  end
end

--- Build the filter accepting vehicles of an optional model, skipping the player's own unless asked.
---@param model? string|number Optional model name or hash to filter by.
---@param includeCurrentVehicle? boolean Whether to include the player's current vehicle (default: false).
---@return fun(entity: number): boolean accepts The filter.
local function vehicleFilter(model, includeCurrentVehicle)
  local filterHash <const> = resolveModelHash(model)
  local excluded <const> = resolveExcludedVehicle(includeCurrentVehicle)

  return function(entity)
    return entity ~= excluded and not (filterHash and GetEntityModel(entity) ~= filterHash)
  end
end

--- Get the closest object to the given coordinates.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@return table|nil object The closest object { entity, coords, distance } or nil if none found.
local function getClosestObject(coords, maxDistance, model)
  return findClosest(GetGamePool('CObject'), coords, maxDistance, objectFilter(model))
end

--- Get all objects within a given distance, sorted by proximity.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@return table objects A sorted list of { entity, coords, distance } tables.
local function getNearbyObjects(coords, maxDistance, model)
  return findNearby(GetGamePool('CObject'), coords, maxDistance, objectFilter(model))
end

--- Get the closest ped to the given coordinates.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@param includePlayers? boolean Whether to include player peds (default: false).
---@return table|nil ped The closest ped { entity, coords, distance } or nil if none found.
local function getClosestPed(coords, maxDistance, model, includePlayers)
  return findClosest(GetGamePool('CPed'), coords, maxDistance, pedFilter(model, includePlayers))
end

--- Get all peds within a given distance, sorted by proximity.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@param includePlayers? boolean Whether to include player peds (default: false).
---@return table peds A sorted list of { entity, coords, distance } tables.
local function getNearbyPeds(coords, maxDistance, model, includePlayers)
  return findNearby(GetGamePool('CPed'), coords, maxDistance, pedFilter(model, includePlayers))
end

--- Get the closest vehicle to the given coordinates.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@param includeCurrentVehicle? boolean Whether to include the player's current vehicle (default: false).
---@return table|nil vehicle The closest vehicle { entity, coords, distance } or nil if none found.
local function getClosestVehicle(coords, maxDistance, model, includeCurrentVehicle)
  return findClosest(GetGamePool('CVehicle'), coords, maxDistance, vehicleFilter(model, includeCurrentVehicle))
end

--- Get all vehicles within a given distance, sorted by proximity.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@param includeCurrentVehicle? boolean Whether to include the player's current vehicle (default: false).
---@return table vehicles A sorted list of { entity, coords, distance } tables.
local function getNearbyVehicles(coords, maxDistance, model, includeCurrentVehicle)
  return findNearby(GetGamePool('CVehicle'), coords, maxDistance, vehicleFilter(model, includeCurrentVehicle))
end

return {
  getClosestObject = getClosestObject,
  getNearbyObjects = getNearbyObjects,
  getClosestPed = getClosestPed,
  getNearbyPeds = getNearbyPeds,
  getClosestVehicle = getClosestVehicle,
  getNearbyVehicles = getNearbyVehicles,
}
