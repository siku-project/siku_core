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

--- Get all identifiers for a player.
---@param sessionId number The player server ID.
---@return PlayerIdentifiers identifiers The player identifiers.
function Siku.GetIdentifiers(sessionId)
  local source <const> = tostring(sessionId)
  local rawIdentifiers <const> = GetPlayerIdentifiers(source)

  local identifiers = {
    license = nil,
    license2 = nil,
    steam = nil,
    discord = nil,
    fivem = nil,
    xbl = nil,
    live = nil,
    ip = nil,
    name = GetPlayerName(source) or 'Unknown',
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
