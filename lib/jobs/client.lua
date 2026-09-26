local CLIENT_EVENT <const> = internal.CLIENT_EVENT
local CALLBACKS <const> = internal.CALLBACKS
local DOMAINS <const> = internal.DOMAINS

local memberships = {}
local listeners <const> = {}
local synced = false

--- Replaces the local copy and tells whoever asked to know.
---@param list table The public memberships the server sent.
---@return nil
local function apply(list)
  memberships = type(list) == 'table' and list or {}
  synced = true

  for index = 1, #listeners do
    local ok <const>, err <const> = pcall(listeners[index], memberships)

    if not ok then
      Siku.print.error(('Jobs listener failed: %s'):format(tostring(err)))
    end
  end
end

--- The memberships of the local character, as the server last sent them.
---@return table memberships The public memberships.
local function getMine()
  return memberships
end

--- The membership of the local character in one job.
---@param jobName string The job name.
---@return table? membership The membership, or nil.
local function get(jobName)
  return internal.findMembership(memberships, jobName)
end

--- Whether the local character belongs to a job.
---@param jobName string The job name.
---@return boolean member Whether a membership exists.
local function has(jobName)
  return get(jobName) ~= nil
end

--- Whether the local character is on duty in a job.
---@param jobName string The job name.
---@return boolean onDuty Whether the membership is on duty.
local function isOnDuty(jobName)
  local membership <const> = get(jobName)

  return membership ~= nil and membership.onDuty == true
end

--- The jobs the local character is on duty in.
---@return table jobNames The list of job names.
local function getDuties()
  local duties <const> = {}

  for index = 1, #memberships do
    if memberships[index].onDuty then
      duties[#duties + 1] = memberships[index].job
    end
  end

  return duties
end

--- Whether the local character holds no legal job.
---@return boolean unemployed Whether the character is unemployed.
local function isUnemployed()
  for index = 1, #memberships do
    if memberships[index].domain == DOMAINS.LEGAL then
      return false
    end
  end

  return true
end

--- Whether the server has sent the memberships yet.
---@return boolean synced Whether the local copy is meaningful.
local function isSynced()
  return synced
end

--- Registers a function called with the memberships each time they change.
---@param handler function The listener.
---@return boolean registered Whether it was stored.
local function onChanged(handler)
  if not Siku.isCallable(handler) then
    return false
  end

  listeners[#listeners + 1] = handler

  return true
end

--- Asks the server the online and on-duty counts of a job.
---@param jobName string The job name.
---@return table? counts { online, onDuty }, nil when the server did not answer.
local function getCounts(jobName)
  local ok <const>, counts <const> = Siku.callback.triggerServer(CALLBACKS.COUNTS, jobName)

  return ok and counts or nil
end

--- Asks the server the definition of a job.
---@param jobName string The job name.
---@return table? definition The public definition, nil when unknown or unanswered.
local function getDefinition(jobName)
  local ok <const>, definition <const> = Siku.callback.triggerServer(CALLBACKS.DEFINITION, jobName)

  return ok and definition or nil
end

--- Asks the server the members of a job, which it only gives to a member
--- allowed to see them.
---@param jobName string The job name.
---@return table? members The list, nil when refused or unanswered.
local function getMembers(jobName)
  local ok <const>, members <const> = Siku.callback.triggerServer(CALLBACKS.MEMBERS, jobName)

  return ok and members or nil
end

RegisterNetEvent(CLIENT_EVENT, apply)

CreateThread(function()
  local ok <const>, list <const> = Siku.callback.triggerServer(CALLBACKS.MY_JOBS)

  if ok and not synced then
    apply(list)
  end
end)

return {
  getMine = getMine,
  get = get,
  has = has,
  isOnDuty = isOnDuty,
  getDuties = getDuties,
  isUnemployed = isUnemployed,
  isSynced = isSynced,
  onChanged = onChanged,
  getCounts = getCounts,
  getDefinition = getDefinition,
  getMembers = getMembers,
}
