local DEFAULT_DISTANCE <const> = 2.0

--- Get the closest player to the given coordinates.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param includeSelf? boolean Whether to include the local player (default: false).
---@return table|nil player The closest player { playerId, ped, coords, distance } or nil if none found.
local function getClosestPlayer(coords, maxDistance, includeSelf)
  local players <const> = GetActivePlayers()
  local maxDist <const> = maxDistance or DEFAULT_DISTANCE
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

--- Get all nearby players within a given distance, sorted by proximity.
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param includeSelf? boolean Whether to include the local player (default: false).
---@return table players A sorted list of { playerId, ped, coords, distance } tables.
local function getNearbyPlayers(coords, maxDistance, includeSelf)
  local players <const> = GetActivePlayers()
  local maxDist <const> = maxDistance or DEFAULT_DISTANCE
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

return {
  getClosest = getClosestPlayer,
  getNearby = getNearbyPlayers,
}
