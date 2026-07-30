--- Get the closest object to the given coordinates.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@return table|nil object The closest object { entity, coords, distance } or nil if none found.
function Siku.GetClosestObject(coords, maxDistance, model)
  local pool <const> = GetGamePool('CObject')
  local maxDist <const> = maxDistance or 2.0
  local filterHash <const> = model and (type(model) == 'string' and GetHashKey(model) or model) or nil

  local best = nil

  for i = 1, #pool do
    local entity <const> = pool[i]

    if not filterHash or GetEntityModel(entity) == filterHash then
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
