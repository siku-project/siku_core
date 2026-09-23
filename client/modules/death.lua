local POLL_INTERVAL_MS <const> = 500
local DEATH_EVENT <const> = 'siku:server:deathStateChanged'

--- Whether the local ped is dead or going down.
---@return boolean dead The ped state.
local function isPedDead()
  return IsPedDeadOrDying(PlayerPedId(), true)
end

--- Watches the local ped and reports each change of its death state to
--- the server, which verifies it and flags the character. The first
--- reading after a character enters play is only a baseline: what the
--- spawn does with the ped is not a transition, and a character brought
--- back dead must not be reported alive for the tick that precedes it.
---@return nil
local function watchDeath()
  local reported = nil

  while true do
    Wait(POLL_INTERVAL_MS)

    if not Siku.player.getCharacter() then
      reported = nil
    else
      local dead <const> = isPedDead()

      if reported == nil then
        reported = dead
      elseif dead ~= reported then
        reported = dead
        TriggerServerEvent(DEATH_EVENT, dead)
      end
    end
  end
end

CreateThread(watchDeath)
