local DEFAULT_FLAGS <const> = 511
local DEFAULT_IGNORE_FLAGS <const> = 4
local RAD <const> = math.pi / 180

--- Wait for a shape test to complete and return the result.
---@param handle number The shape test handle.
---@return table result The raycast result { hit, entityHit, endCoords, surfaceNormal, materialHash }.
local function resolveShapeTest(handle)
  local retval, hit, endCoords, surfaceNormal, materialHash, entityHit

  repeat
    retval, hit, endCoords, surfaceNormal, materialHash, entityHit = GetShapeTestResultIncludingMaterial(handle)

    if retval == 1 then
      Citizen.Wait(0)
    end
  until retval ~= 1

  return {
    hit = hit ~= 0,
    entityHit = entityHit,
    endCoords = endCoords,
    surfaceNormal = surfaceNormal,
    materialHash = materialHash,
  }
end

--- Calculate the forward direction vector from the camera rotation.
---@return vector3 forward The normalized forward vector of the camera.
local function getCameraForwardVector()
  local rot <const> = GetFinalRenderedCamRot(2)
  local radX <const> = rot.x * RAD
  local radZ <const> = rot.z * RAD

  return vector3(
    -math.sin(radZ) * math.abs(math.cos(radX)),
    math.cos(radZ) * math.abs(math.cos(radX)),
    math.sin(radX)
  )
end

--- Perform a raycast between two coordinates.
---@param origin vector3 The start position of the ray.
---@param destination vector3 The end position of the ray.
---@param flags? number The shape test flags (default: 511, all flags).
---@param ignoreEntity? number The entity to ignore (default: PlayerPedId()).
---@param ignoreFlags? number The ignore flags (default: 4).
---@return table result The raycast result { hit, entityHit, endCoords, surfaceNormal, materialHash }.
function Siku.RaycastFromCoords(origin, destination, flags, ignoreEntity, ignoreFlags)
  local handle <const> = StartShapeTestLosProbe(
    origin.x, origin.y, origin.z,
    destination.x, destination.y, destination.z,
    flags or DEFAULT_FLAGS,
    ignoreEntity or PlayerPedId(),
    ignoreFlags or DEFAULT_IGNORE_FLAGS
  )

  return resolveShapeTest(handle)
end

--- Perform a raycast from the camera position in its forward direction.
---@param distance? number The maximum raycast distance (default: 10.0).
---@param flags? number The shape test flags (default: 511).
---@param ignoreEntity? number The entity to ignore (default: PlayerPedId()).
---@param ignoreFlags? number The ignore flags (default: 4).
---@return table result The raycast result { hit, entityHit, endCoords, surfaceNormal, materialHash }.
function Siku.RaycastFromCamera(distance, flags, ignoreEntity, ignoreFlags)
  local origin <const> = GetFinalRenderedCamCoord()
  local forward <const> = getCameraForwardVector()
  local dist <const> = distance or 10.0

  local destination <const> = vector3(
    origin.x + forward.x * dist,
    origin.y + forward.y * dist,
    origin.z + forward.z * dist
  )

  return Siku.RaycastFromCoords(origin, destination, flags, ignoreEntity, ignoreFlags)
end

--- Perform a raycast from an entity's position in its forward direction.
---@param entity number The entity to raycast from.
---@param distance? number The maximum raycast distance (default: 10.0).
---@param flags? number The shape test flags (default: 511).
---@param ignoreEntity? number The entity to ignore (default: the entity itself).
---@param ignoreFlags? number The ignore flags (default: 4).
---@return table result The raycast result { hit, entityHit, endCoords, surfaceNormal, materialHash }.
function Siku.RaycastFromEntity(entity, distance, flags, ignoreEntity, ignoreFlags)
  local origin <const> = GetEntityCoords(entity, true)
  local forward <const> = GetEntityForwardVector(entity)
  local dist <const> = distance or 10.0

  local destination <const> = vector3(
    origin.x + forward.x * dist,
    origin.y + forward.y * dist,
    origin.z + forward.z * dist
  )

  return Siku.RaycastFromCoords(origin, destination, flags, ignoreEntity or entity, ignoreFlags)
end
