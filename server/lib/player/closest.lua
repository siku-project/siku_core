--- Get the closest player to the given coordinates (server-side).
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param ignorePlayer? number A player server ID to exclude from the search.
---@return table|nil player The closest player { playerId, ped, coords, distance } or nil if none found.
function Siku.GetClosestPlayer(coords, maxDistance, ignorePlayer)
  local players <const> = GetPlayers()
  local maxDist <const> = maxDistance or 2.0

  local best = nil

  for i = 1, #players do
    local playerId <const> = tonumber(players[i])

    if not (ignorePlayer and playerId == ignorePlayer) then
      local ped <const> = GetPlayerPed(tostring(playerId))
      local playerCoords <const> = GetEntityCoords(ped)
      local dist <const> = #(coords - playerCoords)

      if dist < maxDist and (not best or dist < best.distance) then
        best = {
          playerId = playerId,
          ped = ped,
          coords = playerCoords,
          distance = dist,
        }
      end
    end
  end

  return best
end
