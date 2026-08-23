local DEFAULT_DISTANCE <const> = 2.0
local UNKNOWN_NAME <const> = 'Unknown'

local IDENTIFIER_KEYS <const> = {
  'license2', 'license', 'steam', 'discord',
  'fivem', 'xbl', 'live', 'ip',
}

---@class PlayerIdentifiers
---@field license string|nil The Rockstar license identifier.
---@field license2 string|nil The secondary Rockstar license identifier.
---@field steam string|nil The Steam hex identifier.
---@field discord string|nil The Discord user ID.
---@field fivem string|nil The FiveM account identifier.
---@field xbl string|nil The Xbox Live identifier.
---@field live string|nil The Microsoft Live identifier.
---@field ip string|nil The player IP address.
---@field name string The player name.

--- Get the closest player to the given coordinates (server-side).
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param ignorePlayer? number A player server ID to exclude from the search.
---@return table|nil player The closest player { playerId, ped, coords, distance } or nil if none found.
local function getClosestPlayer(coords, maxDistance, ignorePlayer)
  local players <const> = GetPlayers()
  local maxDist <const> = maxDistance or DEFAULT_DISTANCE

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

--- Get all players within a given distance, sorted by proximity (server-side).
---@param coords vector3 The reference coordinates.
---@param maxDistance? number The maximum search distance (default: 2.0).
---@param ignorePlayer? number A player server ID to exclude from the search.
---@return table players A sorted list of { playerId, ped, coords, distance } tables.
local function getNearbyPlayers(coords, maxDistance, ignorePlayer)
  local players <const> = GetPlayers()
  local maxDist <const> = maxDistance or DEFAULT_DISTANCE

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

--- Get all identifiers for a player.
---@param sessionId number The player server ID.
---@return PlayerIdentifiers identifiers The player identifiers.
local function getIdentifiers(sessionId)
  local source <const> = tostring(sessionId)
  local rawIdentifiers <const> = GetPlayerIdentifiers(source)

  local identifiers <const> = {
    license = nil,
    license2 = nil,
    steam = nil,
    discord = nil,
    fivem = nil,
    xbl = nil,
    live = nil,
    ip = nil,
    name = GetPlayerName(source) or UNKNOWN_NAME,
  }

  for i = 1, #rawIdentifiers do
    local raw <const> = rawIdentifiers[i]
    for j = 1, #IDENTIFIER_KEYS do
      local key <const> = IDENTIFIER_KEYS[j]
      local prefix <const> = key .. ':'
      if raw:sub(1, #prefix) == prefix then
        identifiers[key] = raw:sub(#prefix + 1)
        break
      end
    end
  end

  return identifiers
end

return {
  getClosest = getClosestPlayer,
  getNearby = getNearbyPlayers,
  getIdentifiers = getIdentifiers,
}
