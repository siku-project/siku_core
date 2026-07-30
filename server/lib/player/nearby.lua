--- Get all players within a given distance, sorted by proximity (server-side).
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param ignorePlayer? number A player server ID to exclude from the search.
---@return table players A sorted list of { playerId, ped, coords, distance } tables.
function Siku.GetNearbyPlayers(coords, maxDistance, ignorePlayer)
  local players <const> = GetPlayers()
  local maxDist <const> = maxDistance or 2.0

  local results <const> = {}

  for i = 1, #players do
    local playerId <const> = tonumber(players[i])

    if not (ignorePlayer and playerId == ignorePlayer) then
      local ped <const> = GetPlayerPed(tostring(playerId))
      local playerCoords <const> = GetEntityCoords(ped)
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
