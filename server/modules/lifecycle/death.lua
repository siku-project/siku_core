local DEATH_EVENT <const> = 'siku:server:deathStateChanged'
local VERIFY_ATTEMPTS <const> = 5
local VERIFY_INTERVAL_MS <const> = 200

--- Whether the ped of a session is dead, read from the server's own copy
--- of the entity rather than from what the client claimed.
---@param sessionId number The player server ID.
---@return boolean dead The ped state.
local function isPedDead(sessionId)
  local ped <const> = GetPlayerPed(tostring(sessionId))

  return ped ~= 0 and GetEntityHealth(ped) <= 0
end

--- Waits for the server's copy of the ped to agree with a reported state,
--- since replication lags the client by a few frames.
---@param sessionId number The player server ID.
---@param dead boolean The reported state.
---@return boolean verified Whether the ped reached that state in time.
local function matchesPed(sessionId, dead)
  for _ = 1, VERIFY_ATTEMPTS do
    if isPedDead(sessionId) == dead then
      return true
    end

    Wait(VERIFY_INTERVAL_MS)
  end

  return false
end

--- Flags the character of a session dead or alive after its ped changed
--- state, once the server saw the same thing.
---@param sessionId number The player server ID.
---@param dead boolean The reported state.
---@return nil
local function handleDeathStateChanged(sessionId, dead)
  local character <const> = Siku.cache.getCurrentCharacter(sessionId)

  if not character or character.isDead == dead then
    return
  end

  if not matchesPed(sessionId, dead) then
    Siku.print.warn(T('death_report_rejected', sessionId, character.id))
    return
  end

  local current <const> = Siku.cache.getCurrentCharacter(sessionId)

  if not current or current.id ~= character.id then
    return
  end

  current:setDead(dead)
  Siku.print.debug(('Character %d is now %s (session %d)'):format(current.id, dead and 'dead' or 'alive', sessionId))
end

RegisterNetEvent(DEATH_EVENT, function(dead)
  local sessionId <const> = source

  if type(dead) ~= 'boolean' then
    return
  end

  handleDeathStateChanged(sessionId, dead)
end)
