--- Get the closest player to the given coordinates.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param includeSelf? boolean Whether to include the local player (default: false).
---@return table|nil player The closest player { playerId, ped, coords, distance } or nil if none found.
function Siku.GetClosestPlayer(coords, maxDistance, includeSelf)
  local players <const> = GetActivePlayers()
  local maxDist <const> = maxDistance or 2.0
  local selfIncluded <const> = includeSelf or false
  local localPlayer <const> = PlayerId()

  local best = nil

  for i = 1, #players do
    local playerId <const> = players[i]

    if selfIncluded or playerId ~= localPlayer then
      local ped <const> = GetPlayerPed(playerId)
      local playerCoords <const> = GetEntityCoords(ped, false)
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
