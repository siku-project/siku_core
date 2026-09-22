local DEFAULT_DISTANCE <const> = 2.0
local CHARACTER_STATE_KEY <const> = 'siku:state:character'

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

--- The character a player is playing, as the server published it on the
--- player's state bag: identity and death state, nothing to act on.
---@param playerId? number The player index, the local player when omitted.
---@return table|nil character { id, firstName, lastName, fullName, gender, dob, age, height, nationality, birthplace, pedModel, isDead }, nil before a character is in play.
local function getCharacter(playerId)
  local state <const> = playerId and Player(playerId).state or LocalPlayer.state
  local character <const> = state[CHARACTER_STATE_KEY]

  return type(character) == 'table' and character or nil
end

--- The character behind a server id, for what came through the network.
---@param serverId number The player server id.
---@return table|nil character The published character, nil when unknown here.
local function getCharacterByServerId(serverId)
  local playerId <const> = GetPlayerFromServerId(serverId)

  if playerId == -1 then
    return nil
  end

  return getCharacter(playerId)
end

return {
  getClosest = getClosestPlayer,
  getNearby = getNearbyPlayers,
  getCharacter = getCharacter,
  getCharacterByServerId = getCharacterByServerId,
}
