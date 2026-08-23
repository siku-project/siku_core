local SCRIPTED_CAMERA <const> = 'DEFAULT_SCRIPTED_CAMERA'
local ROTATION_ORDER <const> = 2
local MIN_FOV <const> = 1.0
local MAX_FOV <const> = 130.0
local DEFAULT_CATCH_UP_DISTANCE <const> = 0.0
local DEFAULT_CATCH_UP_BLEND <const> = 3

local registry <const> = {}

internal.registry = registry
internal.ROTATION_ORDER = ROTATION_ORDER
internal.rendering = nil

local camera <const> = {}

--- Clamps a field of view to the range the engine accepts.
---@param fov number The field of view in degrees.
---@return number fov The clamped field of view.
function internal.clampFov(fov)
  if fov < MIN_FOV then return MIN_FOV end
  if fov > MAX_FOV then return MAX_FOV end
  return fov
end

--- Gets the registry state of a camera, throwing when it is unknown.
---@param handle number The camera handle.
---@return table state The camera registry state.
function internal.getState(handle)
  local state <const> = registry[handle]

  if not state or not DoesCamExist(handle) then
    Siku.print.throw(("Unknown camera '%s'"):format(tostring(handle)))
  end

  return state
end

--- Creates a scripted camera and registers it for automatic cleanup.
---@param options? table Creation options { coords?, rotation?, fov?, fromGameplay?, active? }; without coords the camera starts at the gameplay camera transform.
---@return number camera The camera handle.
function camera.create(options)
  options = options or {}

  local coords = options.coords
  local rotation = options.rotation
  local fov = options.fov and internal.clampFov(options.fov) or Siku.config.camera.defaultFov

  if options.fromGameplay or not coords then
    coords = coords or GetGameplayCamCoord()
    rotation = rotation or GetGameplayCamRot(ROTATION_ORDER)

    if options.fromGameplay and not options.fov then
      fov = GetGameplayCamFov()
    end
  end

  rotation = rotation or vector3(0.0, 0.0, 0.0)

  local handle <const> = CreateCamWithParams(
    SCRIPTED_CAMERA,
    coords.x, coords.y, coords.z,
    rotation.x, rotation.y, rotation.z,
    fov, options.active ~= false, ROTATION_ORDER
  )

  registry[handle] = {}

  return handle
end

--- Destroys a camera, stopping its animations and, when it was the one
--- rendering, giving the screen back to the gameplay camera.
---@param handle number The camera handle.
---@return nil
function camera.destroy(handle)
  local state <const> = registry[handle]

  if not state then
    return
  end

  state.orbit = nil
  state.dof = nil
  registry[handle] = nil

  if internal.rendering == handle then
    internal.rendering = nil

    if IsCamRendering(handle) then
      RenderScriptCams(false, false, 0, true, false)
    end
  end

  if DoesCamExist(handle) then
    DestroyCam(handle, false)
  end
end

--- Destroys every camera this resource created.
---@return nil
function camera.destroyAll()
  local handles <const> = {}

  for handle in pairs(registry) do
    handles[#handles + 1] = handle
  end

  for i = 1, #handles do
    camera.destroy(handles[i])
  end
end

--- Renders a camera to the screen, optionally easing from the current view.
---@param handle number The camera handle.
---@param ease? boolean Whether to blend from the current view (default false).
---@param easeTime? number Blend duration in ms (default Siku.config.camera.defaultEaseTime).
---@return nil
function camera.render(handle, ease, easeTime)
  internal.getState(handle)

  SetCamActive(handle, true)
  internal.rendering = handle

  RenderScriptCams(true, ease == true, easeTime or Siku.config.camera.defaultEaseTime, true, false)
end

--- Stops rendering scripted cameras, optionally easing back to gameplay.
---@param ease? boolean Whether to blend back to the gameplay view (default false).
---@param easeTime? number Blend duration in ms (default Siku.config.camera.defaultEaseTime).
---@return nil
function camera.stopRendering(ease, easeTime)
  internal.rendering = nil
  RenderScriptCams(false, ease == true, easeTime or Siku.config.camera.defaultEaseTime, true, false)
end

--- Stops rendering by letting the gameplay camera catch up with the
--- scripted camera position for a seamless cinematic return.
---@param distanceToBlend? number Distance over which the blend happens (default 0.0).
---@param blendType? number Blend curve type, see STOP_RENDERING_SCRIPT_CAMS_USING_CATCH_UP (default 3).
---@return nil
function camera.catchUp(distanceToBlend, blendType)
  internal.rendering = nil
  StopRenderingScriptCamsUsingCatchUp(false, distanceToBlend or DEFAULT_CATCH_UP_DISTANCE, blendType or DEFAULT_CATCH_UP_BLEND)
end

--- Sets the position of a camera.
---@param handle number The camera handle.
---@param coords vector3 The world position.
---@return nil
function camera.setCoords(handle, coords)
  internal.getState(handle)
  SetCamCoord(handle, coords.x, coords.y, coords.z)
end

--- Gets the position of a camera.
---@param handle number The camera handle.
---@return vector3 coords The world position.
function camera.getCoords(handle)
  internal.getState(handle)
  return GetCamCoord(handle)
end

--- Sets the rotation of a camera.
---@param handle number The camera handle.
---@param rotation vector3 The rotation in degrees (pitch, roll, yaw).
---@return nil
function camera.setRotation(handle, rotation)
  internal.getState(handle)
  SetCamRot(handle, rotation.x, rotation.y, rotation.z, ROTATION_ORDER)
end

--- Gets the rotation of a camera.
---@param handle number The camera handle.
---@return vector3 rotation The rotation in degrees (pitch, roll, yaw).
function camera.getRotation(handle)
  internal.getState(handle)
  return GetCamRot(handle, ROTATION_ORDER)
end

--- Sets the field of view of a camera.
---@param handle number The camera handle.
---@param fov number The field of view in degrees, clamped to 1.0-130.0.
---@return nil
function camera.setFov(handle, fov)
  internal.getState(handle)
  SetCamFov(handle, internal.clampFov(fov))
end

--- Gets the field of view of a camera.
---@param handle number The camera handle.
---@return number fov The field of view in degrees.
function camera.getFov(handle)
  internal.getState(handle)
  return GetCamFov(handle)
end

--- Gets the full transform of a camera.
---@param handle number The camera handle.
---@return vector3 coords, vector3 rotation, number fov The camera transform.
function camera.getTransform(handle)
  internal.getState(handle)
  return GetCamCoord(handle), GetCamRot(handle, ROTATION_ORDER), GetCamFov(handle)
end

--- Computes the rotation a camera would need to face a target from a
--- position, to build spline nodes or plan a shot in advance.
---@param coords vector3 The camera position.
---@param target vector3 The world position to face.
---@return vector3 rotation The rotation in degrees (pitch, roll, yaw).
function camera.rotationTo(coords, target)
  local direction <const> = target - coords
  local horizontal <const> = math.sqrt(direction.x * direction.x + direction.y * direction.y)
  local pitch <const> = math.deg(math.atan(direction.z, horizontal))
  local yaw <const> = math.deg(math.atan(-direction.x, direction.y))

  return vector3(pitch, 0.0, yaw)
end

--- Rotates a camera so it faces a world position, without locking it
--- the way pointing does: the rotation stays freely editable after.
---@param handle number The camera handle.
---@param target vector3 The world position to face.
---@return nil
function camera.lookAt(handle, target)
  internal.getState(handle)

  local rotation <const> = camera.rotationTo(GetCamCoord(handle), target)

  SetCamRot(handle, rotation.x, rotation.y, rotation.z, ROTATION_ORDER)
end

--- Locks a camera aim onto a world position.
---@param handle number The camera handle.
---@param coords vector3 The world position to aim at.
---@return nil
function camera.pointAtCoords(handle, coords)
  internal.getState(handle)
  PointCamAtCoord(handle, coords.x, coords.y, coords.z)
end

--- Locks a camera aim onto an entity.
---@param handle number The camera handle.
---@param entity number The entity handle.
---@param offset? vector3 Offset from the entity (default none).
---@return nil
function camera.pointAtEntity(handle, entity, offset)
  internal.getState(handle)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  PointCamAtEntity(handle, entity, relative.x, relative.y, relative.z, true)
end

--- Locks a camera aim onto a ped bone.
---@param handle number The camera handle.
---@param ped number The ped handle.
---@param bone number The bone tag (for example 31086 for SKEL_Head).
---@param offset? vector3 Offset from the bone (default none).
---@return nil
function camera.pointAtBone(handle, ped, bone, offset)
  internal.getState(handle)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  PointCamAtPedBone(handle, ped, bone, relative.x, relative.y, relative.z, true)
end

--- Releases the aim lock of a camera.
---@param handle number The camera handle.
---@return nil
function camera.stopPointing(handle)
  internal.getState(handle)
  StopCamPointing(handle)
end

--- Attaches a camera position to an entity.
---@param handle number The camera handle.
---@param entity number The entity handle.
---@param offset? vector3 Offset from the entity (default none).
---@param isRelative? boolean Whether the offset is in entity local space (default true).
---@return nil
function camera.attachToEntity(handle, entity, offset, isRelative)
  internal.getState(handle)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  AttachCamToEntity(handle, entity, relative.x, relative.y, relative.z, isRelative ~= false)
end

--- Attaches a camera position to a ped bone.
---@param handle number The camera handle.
---@param ped number The ped handle.
---@param bone number The bone tag (for example 31086 for SKEL_Head).
---@param offset? vector3 Offset from the bone (default none).
---@param isRelative? boolean Whether the offset is in bone local space (default true).
---@return nil
function camera.attachToBone(handle, ped, bone, offset, isRelative)
  internal.getState(handle)

  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  AttachCamToPedBone(handle, ped, bone, relative.x, relative.y, relative.z, isRelative ~= false)
end

--- Hard-attaches a camera to an entity, locking position and rotation
--- to the entity transform.
---@param handle number The camera handle.
---@param entity number The entity handle.
---@param rotation? vector3 Rotation offset in degrees (default none).
---@param offset? vector3 Position offset (default none).
---@return nil
function camera.hardAttachToEntity(handle, entity, rotation, offset)
  internal.getState(handle)

  local spin <const> = rotation or vector3(0.0, 0.0, 0.0)
  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  HardAttachCamToEntity(handle, entity, spin.x, spin.y, spin.z, relative.x, relative.y, relative.z, true)
end

--- Hard-attaches a camera to a ped bone, locking position and rotation
--- to the bone transform.
---@param handle number The camera handle.
---@param ped number The ped handle.
---@param bone number The bone tag (for example 31086 for SKEL_Head).
---@param rotation? vector3 Rotation offset in degrees (default none).
---@param offset? vector3 Position offset (default none).
---@return nil
function camera.hardAttachToBone(handle, ped, bone, rotation, offset)
  internal.getState(handle)

  local spin <const> = rotation or vector3(0.0, 0.0, 0.0)
  local relative <const> = offset or vector3(0.0, 0.0, 0.0)
  HardAttachCamToPedBone(handle, ped, bone, spin.x, spin.y, spin.z, relative.x, relative.y, relative.z, true)
end

--- Detaches a camera from whatever it is attached to.
---@param handle number The camera handle.
---@return nil
function camera.detach(handle)
  internal.getState(handle)
  DetachCam(handle)
end

--- Checks whether a camera exists in the library registry.
---@param handle number The camera handle.
---@return boolean exists Whether the camera exists.
function camera.exists(handle)
  return registry[handle] ~= nil and DoesCamExist(handle)
end

--- Checks whether a camera is active.
---@param handle number The camera handle.
---@return boolean active Whether the camera is active.
function camera.isActive(handle)
  return registry[handle] ~= nil and IsCamActive(handle)
end

--- Checks whether a camera is currently rendering to the screen.
---@param handle number The camera handle.
---@return boolean rendering Whether the camera is rendering.
function camera.isRendering(handle)
  return registry[handle] ~= nil and IsCamRendering(handle)
end

--- Checks whether a camera is interpolating.
---@param handle number The camera handle.
---@return boolean interpolating Whether the camera is interpolating.
function camera.isInterpolating(handle)
  return registry[handle] ~= nil and IsCamInterpolating(handle)
end

--- Gets the camera currently rendered by the library.
---@return number|nil camera The rendering camera handle, or nil.
function camera.getRendering()
  return internal.rendering
end

--- Gets the gameplay camera transform, to start a scripted camera
--- exactly where the player is looking.
---@return vector3 coords, vector3 rotation, number fov The gameplay camera transform.
function camera.getGameplayTransform()
  return GetGameplayCamCoord(), GetGameplayCamRot(ROTATION_ORDER), GetGameplayCamFov()
end

AddEventHandler('onResourceStop', function(resource)
  if resource ~= Siku.name then
    return
  end

  camera.destroyAll()
end)

import('animation')
import('effects')
import('orbit')
import('spline')

return camera
