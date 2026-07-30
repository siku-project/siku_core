--- Get all objects within a given distance, sorted by proximity.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@return table objects A sorted list of { entity, coords, distance } tables.
function Siku.GetNearbyObjects(coords, maxDistance, model)
  local pool <const> = GetGamePool('CObject')
  local maxDist <const> = maxDistance or 2.0
  local filterHash <const> = model and (type(model) == 'string' and GetHashKey(model) or model) or nil

  local results <const> = {}

  for i = 1, #pool do
    local entity <const> = pool[i]

    if not filterHash or GetEntityModel(entity) == filterHash then
      local entityCoords <const> = GetEntityCoords(entity)
      local dist <const> = #(coords - entityCoords)

      if dist < maxDist then
        results[#results + 1] = {
          entity = entity,
          coords = entityCoords,
          distance = dist,
        }
      end
    end
  end

  table.sort(results, function(a, b)
    return a.distance < b.distance
  end)

  return results
end
