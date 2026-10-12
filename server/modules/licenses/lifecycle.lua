local internal <const> = _SikuInternal.licenses
local state <const> = internal.state

local STATE_EXPIRED <const> = internal.STATE_EXPIRED
local CALLBACK_MY_LICENSES <const> = 'siku:callback:myLicenses'
local CALLBACK_LICENSE_DEFINITION <const> = 'siku:callback:licenseDefinition'
local CALLBACK_LICENSE_DEFINITIONS <const> = 'siku:callback:licenseDefinitions'
local EVENT_EXPIRED <const> = 'expired'
local TRANSITION_CRON <const> = '* * * * *'

local function handleCharacterReady(sessionId, characterData)
  if type(sessionId) ~= 'number' or type(characterData) ~= 'table' or type(characterData.id) ~= 'number' then
    return
  end

  if not internal.waitReady() then
    return
  end

  local characterId <const> = characterData.id

  state.sessions[characterId] = sessionId
  state.holdings[characterId] = internal.entriesOf(characterId)
  state.announced[characterId] = {}

  internal.push(characterId)
end

local function handleCharacterReleased(_, characterId)
  state.holdings[characterId] = nil
  state.sessions[characterId] = nil
  state.announced[characterId] = nil
end

local function characterOf(sessionId)
  return Siku.cache.getCurrentCharacterId(sessionId)
end

local function announceExpiry(characterId, license, entry)
  local announced <const> = state.announced[characterId]

  if not announced or announced[license.name] or internal.readState(entry) ~= STATE_EXPIRED then
    return false
  end

  announced[license.name] = true

  internal.emit(EVENT_EXPIRED, characterId, license.name, state.sessions[characterId])

  return true
end

local function settleTransitions()
  for characterId, entries in pairs(state.holdings) do
    local changed = false

    for licenseName, entry in pairs(entries) do
      local license <const> = state.byName[licenseName]

      if license then
        if internal.settleSuspension(characterId, license, entry) then
          changed = true
        end

        if announceExpiry(characterId, license, entry) then
          changed = true
        end
      end
    end

    if changed then
      internal.push(characterId)
    end
  end
end

Siku.callback.register(CALLBACK_MY_LICENSES, function(sessionId)
  local characterId <const> = characterOf(sessionId)

  if not characterId then
    return {}
  end

  return Siku.licenses.getHoldings(characterId)
end)

Siku.callback.register(CALLBACK_LICENSE_DEFINITION, function(_, licenseName)
  return Siku.licenses.getDefinition(licenseName)
end)

Siku.callback.register(CALLBACK_LICENSE_DEFINITIONS, function(_, group)
  return Siku.licenses.getAll(type(group) == 'string' and group or nil)
end)

AddEventHandler('siku:server:createCharacterInstance', handleCharacterReady)
AddEventHandler('siku:server:releaseCharacterInstance', handleCharacterReleased)

Siku.cron.create(TRANSITION_CRON, function()
  if state.ready then
    settleTransitions()
  end
end)
