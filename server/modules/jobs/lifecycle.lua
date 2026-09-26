local internal <const> = _SikuInternal.jobs
local state <const> = internal.state

local CALLBACK_MY_JOBS <const> = 'siku:callback:myJobs'
local CALLBACK_JOB_COUNTS <const> = 'siku:callback:jobCounts'
local CALLBACK_JOB_DEFINITION <const> = 'siku:callback:jobDefinition'
local CALLBACK_JOB_MEMBERS <const> = 'siku:callback:jobMembers'
local EVENT_DUTY_CHANGED <const> = 'dutyChanged'

--- Brings the memberships of a character entering play into the cache,
--- counts it in and sends it what it belongs to.
---@param sessionId number The player server ID.
---@param characterData table The character row.
---@return nil
local function handleCharacterReady(sessionId, characterData)
  if type(sessionId) ~= 'number' or type(characterData) ~= 'table' or type(characterData.id) ~= 'number' then
    return
  end

  if not internal.waitReady() then
    return
  end

  local characterId <const> = characterData.id
  local entries <const> = internal.entriesOf(characterId)

  state.memberships[characterId] = entries
  state.sessions[characterId] = sessionId

  for jobName in pairs(entries) do
    internal.counter(jobName).online = internal.counter(jobName).online + 1
  end

  internal.push(characterId)
end

--- Forgets a character leaving play: every duty ends, the counters drop,
--- the cache lets go. The memberships themselves stay in the database.
---@param _ number The player server ID.
---@param characterId number The character id.
---@return nil
local function handleCharacterReleased(_, characterId)
  local entries <const> = state.memberships[characterId]

  if not entries then
    return
  end

  local sessionId <const> = state.sessions[characterId]

  for jobName, entry in pairs(entries) do
    local counters <const> = internal.counter(jobName)

    if entry.onDuty then
      entry.onDuty = false
      counters.onDuty = math.max(0, counters.onDuty - 1)
      internal.emit(EVENT_DUTY_CHANGED, sessionId, characterId, jobName, false)
    end

    counters.online = math.max(0, counters.online - 1)
  end

  state.memberships[characterId] = nil
  state.sessions[characterId] = nil
end

--- The character a session plays, for the callbacks.
---@param sessionId number The player server ID.
---@return number? characterId The character id, or nil between two.
local function characterOf(sessionId)
  return Siku.cache.getCurrentCharacterId(sessionId)
end

Siku.callback.register(CALLBACK_MY_JOBS, function(sessionId)
  local characterId <const> = characterOf(sessionId)

  if not characterId then
    return {}
  end

  return Siku.jobs.getMemberships(characterId)
end)

Siku.callback.register(CALLBACK_JOB_COUNTS, function(_, jobName)
  return Siku.jobs.count(jobName)
end)

Siku.callback.register(CALLBACK_JOB_DEFINITION, function(_, jobName)
  return Siku.jobs.getDefinition(jobName)
end)

Siku.callback.register(CALLBACK_JOB_MEMBERS, function(sessionId, jobName)
  local characterId <const> = characterOf(sessionId)

  if not characterId or not Siku.jobs.hasJob(characterId, jobName) then
    return nil
  end

  return Siku.jobs.getMembers(jobName)
end)

AddEventHandler('siku:server:createCharacterInstance', handleCharacterReady)
AddEventHandler('siku:server:releaseCharacterInstance', handleCharacterReleased)
