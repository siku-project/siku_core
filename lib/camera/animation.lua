local CURVES <const> = {
  linear = 0,
  easeInOut = 1,
  easeIn = 2,
  easeOut = 3,
}

local DEFAULT_EASING <const> = 'easeInOut'

--- Resolves an easing name into an engine interpolation graph type.
---@param easing? string The easing name (default 'easeInOut').
---@return number curve The engine graph type.
local function resolveCurve(easing)
  local curve <const> = CURVES[easing or DEFAULT_EASING]

  if not curve then
    Siku.print.throw(("Unknown easing '%s'"):format(tostring(easing)))
  end

  return curve
end

--- Animates a camera to a destination transform over a duration, driven
--- by the engine interpolator. Returns immediately; track the progress
--- with Siku.camera.isInterpolating.
---@param handle number The camera handle.
---@param destination table The target transform { coords?, rotation?, fov? }; missing parts keep their current value.
---@param duration? number Duration in ms (default Siku.config.camera.defaultDuration).
---@param easing? string Interpolation curve: 'linear', 'easeIn', 'easeOut' or 'easeInOut' (default 'easeInOut').
---@return nil
local function moveTo(handle, destination, duration, easing)
  local state <const> = internal.getState(handle)
  local curve <const> = resolveCurve(easing)

  local coords <const> = destination.coords or GetCamCoord(handle)
  local rotation <const> = destination.rotation or GetCamRot(handle, internal.ROTATION_ORDER)
  local fov <const> = destination.fov and internal.clampFov(destination.fov) or GetCamFov(handle)

  state.orbit = nil

  InterpolateCamWithParams(
    handle,
    coords.x, coords.y, coords.z,
    rotation.x, rotation.y, rotation.z,
    fov, duration or Siku.config.camera.defaultDuration,
    curve, curve, internal.ROTATION_ORDER, curve
  )
end

--- Hands the screen over from the rendering camera to another one with
--- an engine interpolation. Renders directly when nothing is rendering.
---@param handle number The camera handle to switch to.
---@param duration? number Interpolation duration in ms (default Siku.config.camera.defaultDuration).
---@param easing? string Interpolation curve: 'linear', 'easeIn', 'easeOut' or 'easeInOut' (default 'easeInOut').
---@return nil
local function switchTo(handle, duration, easing)
  internal.getState(handle)

  local curve <const> = resolveCurve(easing)
  local from <const> = internal.rendering
  local time <const> = duration or Siku.config.camera.defaultDuration

  if not from or from == handle or not DoesCamExist(from) then
    Siku.camera.render(handle, true, time)
    return
  end

  SetCamActive(handle, true)
  SetCamActiveWithInterp(handle, from, time, curve, curve)
  internal.rendering = handle
end

return {
  moveTo = moveTo,
  switchTo = switchTo,
}
