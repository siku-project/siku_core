--- Get the closest vehicle to the given coordinates.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@param includeCurrentVehicle? boolean Whether to include the player's current vehicle (default: false).
---@return table|nil vehicle The closest vehicle { entity, coords, distance } or nil if none found.
function Siku.GetClosestVehicle(coords, maxDistance, model, includeCurrentVehicle)
  local pool <const> = GetGamePool('CVehicle')
  local maxDist <const> = maxDistance or 2.0
  local filterHash <const> = model and (type(model) == 'string' and GetHashKey(model) or model) or nil

  local currentVehicle = nil
  if not includeCurrentVehicle and PlayerPedId then
    local ped <const> = PlayerPedId()
    local veh <const> = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then currentVehicle = veh end
  end

  local best = nil

  for i = 1, #pool do
    local entity <const> = pool[i]

    if not (currentVehicle and entity == currentVehicle) and not (filterHash and GetEntityModel(entity) ~= filterHash) then
      local entityCoords <const> = GetEntityCoords(entity)
      local dist <const> = #(coords - entityCoords)

      if dist < maxDist and (not best or dist < best.distance) then
        best = {
          entity = entity,
          coords = entityCoords,
          distance = dist,
        }
      end
    end
  end

  return best
end
