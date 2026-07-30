local RAD <const> = math.pi / 180

--- Get coordinates relative to a position rotated by a heading angle (2D rotation on XY plane).
---@param coords vector3 The base position.
---@param heading number The heading angle in degrees.
---@param offset vector3 The offset to apply.
---@return vector3 result The rotated position.
function Siku.math.getRelativeCoords(coords, heading, offset)
  local rad <const> = heading * RAD
  local sin <const> = math.sin(rad)
  local cos <const> = math.cos(rad)

  return vector3(
    coords.x + offset.x * cos - offset.y * sin,
    coords.y + offset.x * sin + offset.y * cos,
    coords.z + offset.z
  )
end

--- Get coordinates relative to a position rotated by a full 3D rotation (pitch, roll, yaw).
---@param coords vector3 The base position.
---@param rotation vector3 The rotation angles in degrees { pitch (x), roll (y), yaw (z) }.
---@param offset vector3 The offset to apply.
---@return vector3 result The rotated position.
function Siku.math.getRelativeCoords3D(coords, rotation, offset)
  local pitch <const> = rotation.x * RAD
  local roll <const> = rotation.y * RAD
  local yaw <const> = rotation.z * RAD

  local sp <const> = math.sin(pitch)
  local cp <const> = math.cos(pitch)
  local sr <const> = math.sin(roll)
  local cr <const> = math.cos(roll)
  local sy <const> = math.sin(yaw)
  local cy <const> = math.cos(yaw)

  return vector3(
    coords.x + offset.x * (cy * cr) + offset.y * (cy * sr * sp - sy * cp) + offset.z * (cy * sr * cp + sy * sp),
    coords.y + offset.x * (sy * cr) + offset.y * (sy * sr * sp + cy * cp) + offset.z * (sy * sr * cp - cy * sp),
    coords.z + offset.x * (-sr) + offset.y * (cr * sp) + offset.z * (cr * cp)
  )
end
