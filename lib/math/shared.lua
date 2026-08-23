local RAD <const> = math.pi / 180
local THOUSANDS_GROUP <const> = 3
local DEFAULT_THOUSANDS_SEPARATOR <const> = ' '
local DECIMAL_SEPARATOR <const> = '.'
local NUMBER_PARTS_PATTERN <const> = '([^%.]+)%.?(.*)'

local mathLib <const> = {}

--- Get coordinates relative to a position rotated by a heading angle (2D rotation on XY plane).
---@param coords vector3 The base position.
---@param heading number The heading angle in degrees.
---@param offset vector3 The offset to apply.
---@return vector3 result The rotated position.
function mathLib.getRelativeCoords(coords, heading, offset)
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
function mathLib.getRelativeCoords3D(coords, rotation, offset)
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

--- Insert a separator every 3 digits in the integer part of a number string.
---@param intPart string The integer part as a string.
---@param sep string The separator to insert.
---@return string formatted The formatted integer string.
local function insertThousands(intPart, sep)
  local result = intPart
  local pos = #result - THOUSANDS_GROUP

  while pos > 0 do
    result = result:sub(1, pos) .. sep .. result:sub(pos + 1)
    pos = pos - THOUSANDS_GROUP
  end

  return result
end

--- Format a number with space-separated thousands.
---@param value number The number to format.
---@return string formatted The formatted number string.
function mathLib.formatNumber(value)
  local sign <const> = value < 0 and '-' or ''
  local intPart <const>, decPart <const> = tostring(math.abs(value)):match(NUMBER_PARTS_PATTERN)
  local formatted <const> = insertThousands(intPart, DEFAULT_THOUSANDS_SEPARATOR)

  if decPart ~= '' then
    return sign .. formatted .. DECIMAL_SEPARATOR .. decPart
  end

  return sign .. formatted
end

--- Format a number as currency with two decimal places and a symbol.
---@param value number The amount to format.
---@param symbol string The currency symbol (e.g. '$', '€').
---@return string formatted The formatted currency string.
function mathLib.formatCurrency(value, symbol)
  local sign <const> = value < 0 and '-' or ''
  local fixed <const> = string.format('%.2f', math.abs(value))
  local intPart <const>, decPart <const> = fixed:match(NUMBER_PARTS_PATTERN)
  local formatted <const> = insertThousands(intPart, DEFAULT_THOUSANDS_SEPARATOR)

  return sign .. formatted .. DECIMAL_SEPARATOR .. decPart .. ' ' .. symbol
end

--- Format a number with a custom thousands separator.
---@param value number The number to format.
---@param separator string The separator character (e.g. ',', '.', ' ').
---@return string formatted The formatted number string.
function mathLib.formatWithSeparator(value, separator)
  if separator == DECIMAL_SEPARATOR and math.floor(value) ~= value then
    Siku.print.warn(('formatWithSeparator: using "." as separator on a decimal number (%s) — may be ambiguous'):format(value))
  end

  local sign <const> = value < 0 and '-' or ''
  local intPart <const>, decPart <const> = tostring(math.abs(value)):match(NUMBER_PARTS_PATTERN)
  local formatted <const> = insertThousands(intPart, separator)

  if decPart ~= '' then
    return sign .. formatted .. DECIMAL_SEPARATOR .. decPart
  end

  return sign .. formatted
end

--- Clamp a value between 0 and 1.
---@param t number The value to clamp.
---@return number clamped The clamped value.
local function clamp01(t)
  if t < 0 then
    return 0
  end

  if t > 1 then
    return 1
  end

  return t
end

--- Linear interpolation between two numbers.
---@param a number Start value.
---@param b number End value.
---@param t number Progress (0-1, clamped).
---@return number result The interpolated value.
function mathLib.lerp(a, b, t)
  return a + (b - a) * clamp01(t)
end

--- Linear interpolation between two vector2 values.
---@param a vector2 Start vector.
---@param b vector2 End vector.
---@param t number Progress (0-1, clamped).
---@return vector2 result The interpolated vector.
function mathLib.lerpVec2(a, b, t)
  local ct <const> = clamp01(t)

  return vector2(
    a.x + (b.x - a.x) * ct,
    a.y + (b.y - a.y) * ct
  )
end

--- Linear interpolation between two vector3 values.
---@param a vector3 Start vector.
---@param b vector3 End vector.
---@param t number Progress (0-1, clamped).
---@return vector3 result The interpolated vector.
function mathLib.lerpVec3(a, b, t)
  local ct <const> = clamp01(t)

  return vector3(
    a.x + (b.x - a.x) * ct,
    a.y + (b.y - a.y) * ct,
    a.z + (b.z - a.z) * ct
  )
end

--- Linear interpolation between two vector4 values.
---@param a vector4 Start vector.
---@param b vector4 End vector.
---@param t number Progress (0-1, clamped).
---@return vector4 result The interpolated vector.
function mathLib.lerpVec4(a, b, t)
  local ct <const> = clamp01(t)

  return vector4(
    a.x + (b.x - a.x) * ct,
    a.y + (b.y - a.y) * ct,
    a.z + (b.z - a.z) * ct,
    a.w + (b.w - a.w) * ct
  )
end

--- Linear interpolation between two tables (recursively interpolates number fields).
---@param a table Start table.
---@param b table End table.
---@param t number Progress (0-1, clamped).
---@return table result The interpolated table.
function mathLib.lerpObject(a, b, t)
  local result <const> = {}

  for k, v in pairs(a) do
    result[k] = v
  end

  for k, vb in pairs(b) do
    local va <const> = a[k]

    if type(va) == 'number' and type(vb) == 'number' then
      result[k] = mathLib.lerp(va, vb, t)
    elseif type(va) == 'table' and type(vb) == 'table' then
      result[k] = mathLib.lerpObject(va, vb, t)
    else
      result[k] = vb
    end
  end

  return result
end

--- Auto-detect value type and interpolate accordingly (number, vector2/3/4, or table).
---@param from any Start value.
---@param to any End value.
---@param progress number Progress (0-1, clamped).
---@return any result The interpolated value.
function mathLib.getValueAt(from, to, progress)
  local t <const> = clamp01(progress)
  local ft <const> = type(from)

  if ft == 'number' and type(to) == 'number' then
    return mathLib.lerp(from, to, t)
  end

  if ft == 'vector4' and type(to) == 'vector4' then
    return mathLib.lerpVec4(from, to, t)
  end

  if ft == 'vector3' and type(to) == 'vector3' then
    return mathLib.lerpVec3(from, to, t)
  end

  if ft == 'vector2' and type(to) == 'vector2' then
    return mathLib.lerpVec2(from, to, t)
  end

  if ft == 'table' and type(to) == 'table' then
    return mathLib.lerpObject(from, to, t)
  end

  return t >= 1 and to or from
end

--- Create an interpolation state machine that tracks progress over time.
---@param from any Start value.
---@param to any End value.
---@param duration number Duration in milliseconds.
---@param startTime? number The start time in ms (default: GetGameTimer()).
---@return table state The interpolation state { from, to, duration, startTime, getValue(now), getProgress(now), isComplete(now) }.
function mathLib.createInterpolator(from, to, duration, startTime)
  local start <const> = startTime or GetGameTimer()

  local state <const> = {
    from = from,
    to = to,
    duration = duration,
    startTime = start,
  }

  --- Get the interpolated value at a given time.
  ---@param now number The current time in ms.
  ---@return any value The interpolated value.
  function state.getValue(now)
    if duration <= 0 then
      return to
    end

    return mathLib.getValueAt(from, to, (now - start) / duration)
  end

  --- Get the interpolation progress at a given time.
  ---@param now number The current time in ms.
  ---@return number progress The progress (0-1).
  function state.getProgress(now)
    if duration <= 0 then
      return 1
    end

    return clamp01((now - start) / duration)
  end

  --- Check if the interpolation is complete.
  ---@param now number The current time in ms.
  ---@return boolean complete Whether the interpolation has finished.
  function state.isComplete(now)
    return now - start >= duration
  end

  return state
end

--- Round a number with optional decimal precision and rounding mode.
---@param value number The number to round.
---@param decimals? number The number of decimal places (default: 0).
---@param mode? string The rounding mode: 'default', 'ceil', or 'floor' (default: 'default').
---@return number result The rounded number.
function mathLib.round(value, decimals, mode)
  local factor <const> = 10 ^ (decimals or 0)
  local scaled <const> = value * factor

  if mode == 'ceil' then
    return math.ceil(scaled) / factor
  end

  if mode == 'floor' then
    return math.floor(scaled) / factor
  end

  return math.floor(scaled + 0.5) / factor
end

import('random')

return mathLib
