--- Get all peds within a given distance, sorted by proximity.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param model? string|number Optional model name or hash to filter by.
---@param includePlayers? boolean Whether to include player peds (default: false).
---@return table peds A sorted list of { entity, coords, distance } tables.
function Siku.GetNearbyPeds(coords, maxDistance, model, includePlayers)
  local pool <const> = GetGamePool('CPed')
  local maxDist <const> = maxDistance or 2.0
  local filterHash <const> = model and (type(model) == 'string' and GetHashKey(model) or model) or nil

  local results <const> = {}

  for i = 1, #pool do
    local entity <const> = pool[i]

    if (includePlayers or not IsPedAPlayer(entity)) and not (filterHash and GetEntityModel(entity) ~= filterHash) then
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
