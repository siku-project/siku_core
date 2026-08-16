Siku.camera = Siku.camera or {}

local SPLINE_CAMERA <const> = 'DEFAULT_SPLINE_CAMERA'
local DEFAULT_NODE_DURATION <const> = 1000

--- Clamps a spline phase to the 0-1 range.
---@param phase number The phase value.
---@return number phase The clamped phase.
local function clampPhase(phase)
  if phase < 0.0 then return 0.0 end
  if phase > 1.0 then return 1.0 end
  return phase
end

--- Creates a spline camera following a path of nodes, registered for
--- automatic cleanup like any other camera. Render it and the camera
--- travels the path; drive it manually with setSplinePhase.
---@param options table Spline options { nodes (at least 2 of { coords, rotation?, duration? }), duration?, smoothingStyle?, fov? }; node duration is the travel time in ms from the previous node.
---@return number camera The spline camera handle.
function Siku.camera.createSpline(options)
  local internal <const> = _SikuInternal.Camera
  local nodes <const> = options.nodes

  if type(nodes) ~= 'table' or #nodes < 2 then
    Siku.print.throw('Camera spline requires at least 2 nodes')
  end

  local camera <const> = CreateCam(SPLINE_CAMERA, false)

  SetCamFov(camera, internal.clampFov(options.fov or CameraConfig.defaultFov))

  for i = 1, #nodes do
    local node <const> = nodes[i]
    local rotation <const> = node.rotation or vector3(0.0, 0.0, 0.0)

    AddCamSplineNode(
      camera,
      node.coords.x, node.coords.y, node.coords.z,
      rotation.x, rotation.y, rotation.z,
      node.duration or DEFAULT_NODE_DURATION, 0, 0
    )
  end

  if options.duration then
    SetCamSplineDuration(camera, options.duration)
  end

  if options.smoothingStyle then
    SetCamSplineSmoothingStyle(camera, options.smoothingStyle)
  end

  internal.registry[camera] = { owner = GetInvokingResource() or Siku.name }

  return camera
end

--- Sets the progress of a spline camera along its path.
---@param camera number The spline camera handle.
---@param phase number The progress along the path (0.0 to 1.0).
---@return nil
function Siku.camera.setSplinePhase(camera, phase)
  _SikuInternal.Camera.getState(camera)
  SetCamSplinePhase(camera, clampPhase(phase))
end

--- Gets the progress of a spline camera along its path.
---@param camera number The spline camera handle.
---@return number phase The progress along the path (0.0 to 1.0).
function Siku.camera.getSplinePhase(camera)
  _SikuInternal.Camera.getState(camera)
  return GetCamSplinePhase(camera)
end
