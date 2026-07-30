--- Get all nearby players within a given distance, sorted by proximity.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param includeSelf? boolean Whether to include the local player (default: false).
---@return table players A sorted list of { playerId, ped, coords, distance } tables.
function Siku.GetNearbyPlayers(coords, maxDistance, includeSelf)
  local players <const> = GetActivePlayers()
  local maxDist <const> = maxDistance or 2.0
  local selfIncluded <const> = includeSelf or false
  local localPlayer <const> = PlayerId()

  local results <const> = {}

  for i = 1, #players do
    local playerId <const> = players[i]

    if selfIncluded or playerId ~= localPlayer then
      local ped <const> = GetPlayerPed(playerId)
      local playerCoords <const> = GetEntityCoords(ped, false)
      local dist <const> = #(coords - playerCoords)

      if dist < maxDist then
        results[#results + 1] = {
          playerId = playerId,
          ped = ped,
          coords = playerCoords,
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
