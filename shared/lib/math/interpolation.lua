--- Clamp a value between 0 and 1.
---@param t number The value to clamp.
---@return number clamped The clamped value.
local function clamp01(t)
  if t < 0 then return 0 end
  if t > 1 then return 1 end
  return t
end

--- Linear interpolation between two numbers.
---@param a number Start value.
---@param b number End value.
---@param t number Progress (0-1, clamped).
---@return number result The interpolated value.
function Siku.math.lerp(a, b, t)
  return a + (b - a) * clamp01(t)
end

--- Linear interpolation between two vector2 values.
---@param a vector2 Start vector.
---@param b vector2 End vector.
---@param t number Progress (0-1, clamped).
---@return vector2 result The interpolated vector.
function Siku.math.lerpVec2(a, b, t)
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
function Siku.math.lerpVec3(a, b, t)
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
function Siku.math.lerpVec4(a, b, t)
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
function Siku.math.lerpObject(a, b, t)
  local result <const> = {}

  for k, v in pairs(a) do
    result[k] = v
  end

  for k, vb in pairs(b) do
    local va <const> = a[k]
    if type(va) == 'number' and type(vb) == 'number' then
      result[k] = Siku.math.lerp(va, vb, t)
    elseif type(va) == 'table' and type(vb) == 'table' then
      result[k] = Siku.math.lerpObject(va, vb, t)
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
function Siku.math.getValueAt(from, to, progress)
  local t <const> = clamp01(progress)
  local ft <const> = type(from)

  if ft == 'number' and type(to) == 'number' then
    return Siku.math.lerp(from, to, t)
  end

  if ft == 'vector4' and type(to) == 'vector4' then
    return Siku.math.lerpVec4(from, to, t)
  end

  if ft == 'vector3' and type(to) == 'vector3' then
    return Siku.math.lerpVec3(from, to, t)
  end

  if ft == 'vector2' and type(to) == 'vector2' then
    return Siku.math.lerpVec2(from, to, t)
  end

  if ft == 'table' and type(to) == 'table' then
    return Siku.math.lerpObject(from, to, t)
  end

  return t >= 1 and to or from
end

--- Create an interpolation state machine that tracks progress over time.
---@param from any Start value.
---@param to any End value.
---@param duration number Duration in milliseconds.
---@param startTime? number The start time in ms (default: GetGameTimer()).
---@return table state The interpolation state { from, to, duration, startTime, getValue(now), getProgress(now), isComplete(now) }.
function Siku.math.createInterpolator(from, to, duration, startTime)
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
    if duration <= 0 then return to end
    return Siku.math.getValueAt(from, to, (now - start) / duration)
  end

  --- Get the interpolation progress at a given time.
  ---@param now number The current time in ms.
  ---@return number progress The progress (0-1).
  function state.getProgress(now)
    if duration <= 0 then return 1 end
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
