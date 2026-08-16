Siku.camera = Siku.camera or {}

local CURVES <const> = {
  linear = 0,
  easeInOut = 1,
  easeIn = 2,
  easeOut = 3,
}

--- Resolves an easing name into an engine interpolation graph type.
---@param easing? string The easing name (default 'easeInOut').
---@return number curve The engine graph type.
local function resolveCurve(easing)
  local curve <const> = CURVES[easing or 'easeInOut']

  if not curve then
    Siku.print.throw(("Unknown easing '%s'"):format(tostring(easing)))
  end

  return curve
end

--- Animates a camera to a destination transform over a duration, driven
--- by the engine interpolator. Returns immediately; track the progress
--- with Siku.camera.isInterpolating.
---@param camera number The camera handle.
---@param destination table The target transform { coords?, rotation?, fov? }; missing parts keep their current value.
---@param duration? number Duration in ms (default CameraConfig.defaultDuration).
---@param easing? string Interpolation curve: 'linear', 'easeIn', 'easeOut' or 'easeInOut' (default 'easeInOut').
---@return nil
function Siku.camera.moveTo(camera, destination, duration, easing)
  local internal <const> = _SikuInternal.Camera
  local state <const> = internal.getState(camera)
  local curve <const> = resolveCurve(easing)

  local coords <const> = destination.coords or GetCamCoord(camera)
  local rotation <const> = destination.rotation or GetCamRot(camera, internal.ROTATION_ORDER)
  local fov <const> = destination.fov and internal.clampFov(destination.fov) or GetCamFov(camera)

  state.orbit = nil

  InterpolateCamWithParams(
    camera,
    coords.x, coords.y, coords.z,
    rotation.x, rotation.y, rotation.z,
    fov, duration or CameraConfig.defaultDuration,
    curve, curve, internal.ROTATION_ORDER, curve
  )
end

--- Hands the screen over from the rendering camera to another one with
--- an engine interpolation. Renders directly when nothing is rendering.
---@param camera number The camera handle to switch to.
---@param duration? number Interpolation duration in ms (default CameraConfig.defaultDuration).
---@param easing? string Interpolation curve: 'linear', 'easeIn', 'easeOut' or 'easeInOut' (default 'easeInOut').
---@return nil
function Siku.camera.switchTo(camera, duration, easing)
  local internal <const> = _SikuInternal.Camera
  internal.getState(camera)

  local curve <const> = resolveCurve(easing)
  local from <const> = internal.rendering
  local time <const> = duration or CameraConfig.defaultDuration

  if not from or from == camera or not DoesCamExist(from) then
    Siku.camera.render(camera, true, time)
    return
  end

  SetCamActive(camera, true)
  SetCamActiveWithInterp(camera, from, time, curve, curve)
  internal.rendering = camera
end
