Siku.camera = Siku.camera or {}

local DEFAULT_SHAKE <const> = 'HAND_SHAKE'
local DEFAULT_SHAKE_INTENSITY <const> = 0.1

local SHAKE_TYPES <const> = {
  DEATH_FAIL_IN_EFFECT_SHAKE = true,
  DRUNK_SHAKE = true,
  FAMILY5_DRUG_TRIP_SHAKE = true,
  HAND_SHAKE = true,
  JOLT_SHAKE = true,
  LARGE_EXPLOSION_SHAKE = true,
  MEDIUM_EXPLOSION_SHAKE = true,
  SMALL_EXPLOSION_SHAKE = true,
  ROAD_VIBRATION_SHAKE = true,
  SKY_DIVING_SHAKE = true,
  VIBRATE_SHAKE = true,
}

local dofThreadRunning = false

--- Clamps a value between 0 and 1.
---@param value number The value to clamp.
---@return number clamped The clamped value.
local function clamp01(value)
  if value < 0.0 then return 0.0 end
  if value > 1.0 then return 1.0 end
  return value
end

--- Keeps the high quality depth of field pipeline active while at least
--- one camera with depth of field is rendering, as the engine requires
--- it to be requested every frame.
---@return nil
local function ensureDofThread()
  if dofThreadRunning then
    return
  end

  dofThreadRunning = true

  CreateThread(function()
    while true do
      Wait(0)

      local anyDof = false

      for camera, state in pairs(_SikuInternal.Camera.registry) do
        if state.dof then
          anyDof = true

          if IsCamRendering(camera) then
            SetUseHiDof()
          end
        end
      end

      if not anyDof then
        dofThreadRunning = false
        return
      end
    end
  end)
end

--- Shakes a camera with a named shake effect.
---@param camera number The camera handle.
---@param shakeType? string The shake name, see SHAKE_CAM (default 'HAND_SHAKE').
---@param intensity? number The shake amplitude (default 0.1).
---@return nil
function Siku.camera.shake(camera, shakeType, intensity)
  _SikuInternal.Camera.getState(camera)

  local name <const> = shakeType or DEFAULT_SHAKE

  if not SHAKE_TYPES[name] then
    Siku.print.throw(("Unknown camera shake '%s'"):format(tostring(shakeType)))
  end

  ShakeCam(camera, name, intensity or DEFAULT_SHAKE_INTENSITY)
end

--- Stops the shake of a camera.
---@param camera number The camera handle.
---@param immediately? boolean Whether to cut the shake instead of letting it fade (default false).
---@return nil
function Siku.camera.stopShake(camera, immediately)
  _SikuInternal.Camera.getState(camera)
  StopCamShaking(camera, immediately == true)
end

--- Adjusts the amplitude of the running shake of a camera.
---@param camera number The camera handle.
---@param amplitude number The new shake amplitude.
---@return nil
function Siku.camera.setShakeAmplitude(camera, amplitude)
  _SikuInternal.Camera.getState(camera)
  SetCamShakeAmplitude(camera, amplitude)
end

--- Checks whether a camera is shaking.
---@param camera number The camera handle.
---@return boolean shaking Whether the camera is shaking.
function Siku.camera.isShaking(camera)
  return _SikuInternal.Camera.registry[camera] ~= nil and IsCamShaking(camera)
end

--- Configures the depth of field of a camera, enabling the high quality
--- pipeline while the camera renders.
---@param camera number The camera handle.
---@param options table Depth of field options { near?, far?, strength?, shallow? }; near and far are distances in meters, strength goes from 0.0 to 1.0.
---@return nil
function Siku.camera.setDepthOfField(camera, options)
  local state <const> = _SikuInternal.Camera.getState(camera)

  SetCamUseShallowDofMode(camera, options.shallow ~= false)

  if options.near then
    SetCamNearDof(camera, options.near)
  end

  if options.far then
    SetCamFarDof(camera, options.far)
  end

  SetCamDofStrength(camera, clamp01(options.strength or 1.0))

  state.dof = true
  ensureDofThread()
end

--- Clears the depth of field of a camera.
---@param camera number The camera handle.
---@return nil
function Siku.camera.clearDepthOfField(camera)
  local state <const> = _SikuInternal.Camera.getState(camera)

  state.dof = nil
  SetCamUseShallowDofMode(camera, false)
  SetCamDofStrength(camera, 0.0)
end

--- Sets the motion blur strength of a camera.
---@param camera number The camera handle.
---@param strength number The blur strength (0.0 to 1.0).
---@return nil
function Siku.camera.setMotionBlur(camera, strength)
  _SikuInternal.Camera.getState(camera)
  SetCamMotionBlurStrength(camera, clamp01(strength))
end
