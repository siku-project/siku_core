Siku.camera = Siku.camera or {}

local DEFAULT_DISTANCE <const> = 3.0
local DEFAULT_HEIGHT <const> = 0.5
local DEFAULT_SPEED <const> = 30.0

--- Resolves an orbit target into world coordinates.
---@param target vector3|number The target position, or an entity handle.
---@return vector3|nil coords The target coordinates, or nil when unresolvable.
local function resolveTarget(target)
  if type(target) == 'vector3' then
    return target
  end

  if type(target) == 'number' and DoesEntityExist(target) then
    return GetEntityCoords(target)
  end

  return nil
end

--- Starts orbiting a camera around a target, following it when the
--- target is an entity. Runs until stopOrbit, another orbit or move on
--- the same camera, its destruction, or the target disappearing.
---@param camera number The camera handle.
---@param options table Orbit options { target (vector3|entity), distance?, height?, speed?, angle?, focusOffset? }; speed is in degrees per second, negative to reverse.
---@return nil
function Siku.camera.orbit(camera, options)
  local internal <const> = _SikuInternal.Camera
  local state <const> = internal.getState(camera)

  if not resolveTarget(options.target) then
    Siku.print.throw('Camera orbit requires a vector3 or entity target')
  end

  local distance <const> = options.distance or DEFAULT_DISTANCE
  local height <const> = options.height or DEFAULT_HEIGHT
  local speed <const> = options.speed or DEFAULT_SPEED
  local focusOffset <const> = options.focusOffset or vector3(0.0, 0.0, 0.0)
  local angle = options.angle or 0.0

  local token <const> = {}
  state.orbit = token

  CreateThread(function()
    while true do
      Wait(0)

      local current <const> = internal.registry[camera]
      if not current or current.orbit ~= token then
        return
      end

      local target <const> = resolveTarget(options.target)
      if not target then
        current.orbit = nil
        return
      end

      angle = (angle + speed * GetFrameTime()) % 360.0

      local radians <const> = math.rad(angle)
      local focus <const> = target + focusOffset

      SetCamCoord(camera, target.x + math.cos(radians) * distance, target.y + math.sin(radians) * distance, target.z + height)
      PointCamAtCoord(camera, focus.x, focus.y, focus.z)
    end
  end)
end

--- Stops the orbit of a camera, releasing its aim lock.
---@param camera number The camera handle.
---@return nil
function Siku.camera.stopOrbit(camera)
  local internal <const> = _SikuInternal.Camera
  local state <const> = internal.getState(camera)

  if not state.orbit then
    return
  end

  state.orbit = nil
  StopCamPointing(camera)
end
