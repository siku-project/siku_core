Siku.camera = Siku.camera or {}

local SCRIPTED_CAMERA <const> = 'DEFAULT_SCRIPTED_CAMERA'
local ROTATION_ORDER <const> = 2
local MIN_FOV <const> = 1.0
local MAX_FOV <const> = 130.0

local registry = {}

local internal <const> = {
  registry = registry,
  ROTATION_ORDER = ROTATION_ORDER,
  rendering = nil,
}

_SikuInternal.Camera = internal

--- Clamps a field of view to the range the engine accepts.
---@param fov number The field of view in degrees.
---@return number fov The clamped field of view.
function internal.clampFov(fov)
  if fov < MIN_FOV then return MIN_FOV end
  if fov > MAX_FOV then return MAX_FOV end
  return fov
end

--- Gets the registry state of a camera, throwing when it is unknown.
---@param camera number The camera handle.
---@return table state The camera registry state.
function internal.getState(camera)
  local state <const> = registry[camera]

  if not state or not DoesCamExist(camera) then
    Siku.print.throw(("Unknown camera '%s'"):format(tostring(camera)))
  end

  return state
end

--- Creates a scripted camera and registers it for automatic cleanup.
---@param options? table Creation options { coords?, rotation?, fov?, fromGameplay?, active? }; without coords the camera starts at the gameplay camera transform.
---@return number camera The camera handle.
function Siku.camera.create(options)
  options = options or {}

  local coords = options.coords
  local rotation = options.rotation
  local fov = options.fov and internal.clampFov(options.fov) or CameraConfig.defaultFov

  if options.fromGameplay or not coords then
    coords = coords or GetGameplayCamCoord()
    rotation = rotation or GetGameplayCamRot(ROTATION_ORDER)

    if options.fromGameplay and not options.fov then
      fov = GetGameplayCamFov()
    end
  end

  rotation = rotation or vector3(0.0, 0.0, 0.0)

  local camera <const> = CreateCamWithParams(
    SCRIPTED_CAMERA,
    coords.x, coords.y, coords.z,
    rotation.x, rotation.y, rotation.z,
    fov, options.active ~= false, ROTATION_ORDER
  )

  registry[camera] = { owner = GetInvokingResource() or Siku.name }

  return camera
end

--- Destroys a camera, stopping its animations and, when it was the one
--- rendering, giving the screen back to the gameplay camera.
---@param camera number The camera handle.
---@return nil
function Siku.camera.destroy(camera)
  local state <const> = registry[camera]

  if not state then
    return
  end

  state.orbit = nil
  state.dof = nil
  registry[camera] = nil

  if internal.rendering == camera then
    internal.rendering = nil

    if IsCamRendering(camera) then
      RenderScriptCams(false, false, 0, true, false)
    end
  end

  if DoesCamExist(camera) then
    DestroyCam(camera, false)
  end
end

--- Destroys every camera created by the calling resource.
---@return nil
function Siku.camera.destroyAll()
  local owner <const> = GetInvokingResource() or Siku.name
  local owned <const> = {}

  for camera, state in pairs(registry) do
    if state.owner == owner then
      owned[#owned + 1] = camera
    end
  end

  for i = 1, #owned do
    Siku.camera.destroy(owned[i])
  end
end

--- Renders a camera to the screen, optionally easing from the current view.
---@param camera number The camera handle.
---@param ease? boolean Whether to blend from the current view (default false).
---@param easeTime? number Blend duration in ms (default CameraConfig.defaultEaseTime).
---@return nil
function Siku.camera.render(camera, ease, easeTime)
  internal.getState(camera)

  SetCamActive(camera, true)
  internal.rendering = camera

  RenderScriptCams(true, ease == true, easeTime or CameraConfig.defaultEaseTime, true, false)
end

--- Stops rendering scripted cameras, optionally easing back to gameplay.
---@param ease? boolean Whether to blend back to the gameplay view (default false).
---@param easeTime? number Blend duration in ms (default CameraConfig.defaultEaseTime).
---@return nil
function Siku.camera.stopRendering(ease, easeTime)
  internal.rendering = nil
  RenderScriptCams(false, ease == true, easeTime or CameraConfig.defaultEaseTime, true, false)
end

--- Stops rendering by letting the gameplay camera catch up with the
--- scripted camera position for a seamless cinematic return.
---@param distanceToBlend? number Distance over which the blend happens (default 0.0).
---@param blendType? number Blend curve type, see STOP_RENDERING_SCRIPT_CAMS_USING_CATCH_UP (default 3).
---@return nil
function Siku.camera.catchUp(distanceToBlend, blendType)
  internal.rendering = nil
  StopRenderingScriptCamsUsingCatchUp(false, distanceToBlend or 0.0, blendType or 3)
end

--- Sets the position of a camera.
---@param camera number The camera handle.
---@param coords vector3 The world position.
---@return nil
function Siku.camera.setCoords(camera, coords)
  internal.getState(camera)
  SetCamCoord(camera, coords.x, coords.y, coords.z)
end

--- Gets the position of a camera.
---@param camera number The camera handle.
---@return vector3 coords The world position.
function Siku.camera.getCoords(camera)
  internal.getState(camera)
  return GetCamCoord(camera)
end

--- Sets the rotation of a camera.
---@param camera number The camera handle.
---@param rotation vector3 The rotation in degrees (pitch, roll, yaw).
---@return nil
function Siku.camera.setRotation(camera, rotation)
  internal.getState(camera)
  SetCamRot(camera, rotation.x, rotation.y, rotation.z, ROTATION_ORDER)
end

--- Gets the rotation of a camera.
---@param camera number The camera handle.
---@return vector3 rotation The rotation in degrees (pitch, roll, yaw).
function Siku.camera.getRotation(camera)
  internal.getState(camera)
  return GetCamRot(camera, ROTATION_ORDER)
end

--- Sets the field of view of a camera.
---@param camera number The camera handle.
---@param fov number The field of view in degrees, clamped to 1.0-130.0.
---@return nil
function Siku.camera.setFov(camera, fov)
  internal.getState(camera)
  SetCamFov(camera, internal.clampFov(fov))
end

--- Gets the field of view of a camera.
---@param camera number The camera handle.
---@return number fov The field of view in degrees.
function Siku.camera.getFov(camera)
  internal.getState(camera)
  return GetCamFov(camera)
end

--- Gets the full transform of a camera.
---@param camera number The camera handle.
---@return vector3 coords, vector3 rotation, number fov The camera transform.
function Siku.camera.getTransform(camera)
  internal.getState(camera)
  return GetCamCoord(camera), GetCamRot(camera, ROTATION_ORDER), GetCamFov(camera)
end

--- Rotates a camera so it faces a world position, without locking it
--- the way pointing does — the rotation stays freely editable after.
---@param camera number The camera handle.
---@param target vector3 The world position to face.
---@return nil
function Siku.camera.lookAt(camera, target)
  internal.getState(camera)

  local from <const> = GetCamCoord(camera)
  local direction <const> = target - from
  local horizontal <const> = math.sqrt(direction.x * direction.x + direction.y * direction.y)
  local pitch <const> = math.deg(math.atan(direction.z, horizontal))
  local yaw <const> = math.deg(math.atan(-direction.x, direction.y))

  SetCamRot(camera, pitch, 0.0, yaw, ROTATION_ORDER)
end

--- Locks a camera aim onto a world position.
---@param camera number The camera handle.
---@param coords vector3 The world position to aim at.
---@return nil
function Siku.camera.pointAtCoords(camera, coords)
  internal.getState(camera)
  PointCamAtCoord(camera, coords.x, coords.y, coords.z)
end

--- Locks a camera aim onto an entity.
---@param camera number The camera handle.
---@param entity number The entity handle.
---@param offset? vector3 Offset from the entity (default none).
---@return nil
function Siku.camera.pointAtEntity(camera, entity, offset)
  internal.getState(camera)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  PointCamAtEntity(camera, entity, relative.x, relative.y, relative.z, true)
end

--- Locks a camera aim onto a ped bone.
---@param camera number The camera handle.
---@param ped number The ped handle.
---@param bone number The bone tag (for example 31086 for SKEL_Head).
---@param offset? vector3 Offset from the bone (default none).
---@return nil
function Siku.camera.pointAtBone(camera, ped, bone, offset)
  internal.getState(camera)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  PointCamAtPedBone(camera, ped, bone, relative.x, relative.y, relative.z, true)
end

--- Releases the aim lock of a camera.
---@param camera number The camera handle.
---@return nil
function Siku.camera.stopPointing(camera)
  internal.getState(camera)
  StopCamPointing(camera)
end

--- Attaches a camera position to an entity.
---@param camera number The camera handle.
---@param entity number The entity handle.
---@param offset? vector3 Offset from the entity (default none).
---@param isRelative? boolean Whether the offset is in entity local space (default true).
---@return nil
function Siku.camera.attachToEntity(camera, entity, offset, isRelative)
  internal.getState(camera)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  AttachCamToEntity(camera, entity, relative.x, relative.y, relative.z, isRelative ~= false)
end

--- Attaches a camera position to a ped bone.
---@param camera number The camera handle.
---@param ped number The ped handle.
---@param bone number The bone tag (for example 31086 for SKEL_Head).
---@param offset? vector3 Offset from the bone (default none).
---@param isRelative? boolean Whether the offset is in bone local space (default true).
---@return nil
function Siku.camera.attachToBone(camera, ped, bone, offset, isRelative)
  internal.getState(camera)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  AttachCamToPedBone(camera, ped, bone, relative.x, relative.y, relative.z, isRelative ~= false)
end

--- Hard-attaches a camera to an entity, locking position and rotation
--- to the entity transform.
---@param camera number The camera handle.
---@param entity number The entity handle.
---@param rotation? vector3 Rotation offset in degrees (default none).
---@param offset? vector3 Position offset (default none).
---@return nil
function Siku.camera.hardAttachToEntity(camera, entity, rotation, offset)
  internal.getState(camera)

  local spin <const> = rotation or vector3(0.0, 0.0, 0.0)
  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  HardAttachCamToEntity(camera, entity, spin.x, spin.y, spin.z, relative.x, relative.y, relative.z, true)
end

--- Hard-attaches a camera to a ped bone, locking position and rotation
--- to the bone transform.
---@param camera number The camera handle.
---@param ped number The ped handle.
---@param bone number The bone tag (for example 31086 for SKEL_Head).
---@param rotation? vector3 Rotation offset in degrees (default none).
---@param offset? vector3 Position offset (default none).
---@return nil
function Siku.camera.hardAttachToBone(camera, ped, bone, rotation, offset)
  internal.getState(camera)

  local spin <const> = rotation or vector3(0.0, 0.0, 0.0)
  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  HardAttachCamToPedBone(camera, ped, bone, spin.x, spin.y, spin.z, relative.x, relative.y, relative.z, true)
end

--- Detaches a camera from whatever it is attached to.
---@param camera number The camera handle.
---@return nil
function Siku.camera.detach(camera)
  internal.getState(camera)
  DetachCam(camera)
end

--- Checks whether a camera exists in the library registry.
---@param camera number The camera handle.
---@return boolean exists Whether the camera exists.
function Siku.camera.exists(camera)
  return registry[camera] ~= nil and DoesCamExist(camera)
end

--- Checks whether a camera is active.
---@param camera number The camera handle.
---@return boolean active Whether the camera is active.
function Siku.camera.isActive(camera)
  return registry[camera] ~= nil and IsCamActive(camera)
end

--- Checks whether a camera is currently rendering to the screen.
---@param camera number The camera handle.
---@return boolean rendering Whether the camera is rendering.
function Siku.camera.isRendering(camera)
  return registry[camera] ~= nil and IsCamRendering(camera)
end

--- Checks whether a camera is interpolating.
---@param camera number The camera handle.
---@return boolean interpolating Whether the camera is interpolating.
function Siku.camera.isInterpolating(camera)
  return registry[camera] ~= nil and IsCamInterpolating(camera)
end

--- Gets the camera currently rendered by the library.
---@return number|nil camera The rendering camera handle, or nil.
function Siku.camera.getRendering()
  return internal.rendering
end

--- Gets the gameplay camera transform, handy to start a scripted camera
--- exactly where the player is looking.
---@return vector3 coords, vector3 rotation, number fov The gameplay camera transform.
function Siku.camera.getGameplayTransform()
  return GetGameplayCamCoord(), GetGameplayCamRot(ROTATION_ORDER), GetGameplayCamFov()
end

AddEventHandler('onResourceStop', function(resource)
  local owned <const> = {}

  for camera, state in pairs(registry) do
    if state.owner == resource then
      owned[#owned + 1] = camera
    end
  end

  for i = 1, #owned do
    Siku.camera.destroy(owned[i])
  end
end)
