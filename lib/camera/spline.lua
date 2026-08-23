local SPLINE_CAMERA <const> = 'DEFAULT_SPLINE_CAMERA'
local DEFAULT_NODE_DURATION <const> = 1000
local MIN_NODES <const> = 2

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
local function createSpline(options)
  local nodes <const> = options.nodes

  if type(nodes) ~= 'table' or #nodes < MIN_NODES then
    Siku.print.throw(('Camera spline requires at least %d nodes'):format(MIN_NODES))
  end

  local handle <const> = CreateCam(SPLINE_CAMERA, true)

  SetCamFov(handle, internal.clampFov(options.fov or Siku.config.camera.defaultFov))

  for i = 1, #nodes do
    local node <const> = nodes[i]
    local rotation <const> = node.rotation or vector3(0.0, 0.0, 0.0)

    AddCamSplineNode(
      handle,
      node.coords.x, node.coords.y, node.coords.z,
      rotation.x, rotation.y, rotation.z,
      node.duration or DEFAULT_NODE_DURATION, 0, 0
    )
  end

  if options.duration then
    SetCamSplineDuration(handle, options.duration)
  end

  if options.smoothingStyle then
    SetCamSplineSmoothingStyle(handle, options.smoothingStyle)
  end

  internal.registry[handle] = {}

  return handle
end

--- Sets the progress of a spline camera along its path.
---@param handle number The spline camera handle.
---@param phase number The progress along the path (0.0 to 1.0).
---@return nil
local function setSplinePhase(handle, phase)
  internal.getState(handle)
  SetCamSplinePhase(handle, clampPhase(phase))
end

--- Gets the progress of a spline camera along its path.
---@param handle number The spline camera handle.
---@return number phase The progress along the path (0.0 to 1.0).
local function getSplinePhase(handle)
  internal.getState(handle)
  return GetCamSplinePhase(handle)
end

return {
  createSpline = createSpline,
  setSplinePhase = setSplinePhase,
  getSplinePhase = getSplinePhase,
}
