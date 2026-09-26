local internal <const> = _SikuInternal.jobs
local state <const> = internal.state

local EVENT_DUTY_CHANGED <const> = 'dutyChanged'

--- The permission patterns a membership grants.
---@param job table The registry entry.
---@param entry table The membership.
---@return table granted The set of patterns.
local function grantedOf(job, entry)
  local grade <const> = job.grades.byId[entry.gradeId]

  return grade and grade.granted or {}
end

--- Whether a character may do something in a job right now: the job must
--- be live, the grade must grant the permission, and a permission the job
--- declared as needing the duty needs the character on duty.
---@param characterId number The character id.
---@param jobName string The job name.
---@param permission string The permission asked for.
---@return boolean allowed Whether the character may.
function Siku.jobs.hasPermission(characterId, jobName, permission)
  local job <const> = internal.getJob(jobName)

  if not job or not job.active or type(permission) ~= 'string' then
    return false
  end

  local entry <const> = internal.entryOf(characterId, job)

  if not entry then
    return false
  end

  if not _SikuInternal.MatchPermission(grantedOf(job, entry), permission) then
    return false
  end

  local declared <const> = job.permissions.byName[permission]

  if declared and declared.requiresDuty and internal.isLegal(job) and not entry.onDuty then
    return false
  end

  return true
end

--- The permission patterns a character holds in a job, duty ignored.
---@param characterId number The character id.
---@param jobName string The job name.
---@return table permissions The sorted list of patterns.
function Siku.jobs.getGrantedPermissions(characterId, jobName)
  local job <const> = internal.getJob(jobName)
  local entry <const> = job and internal.entryOf(characterId, job) or nil

  if not entry then
    return {}
  end

  local permissions <const> = {}

  for pattern in pairs(grantedOf(job, entry)) do
    permissions[#permissions + 1] = pattern
  end

  table.sort(permissions)

  return permissions
end

--- Whether a character is on duty in a legal job.
---@param characterId number The character id.
---@param jobName string The job name.
---@return boolean onDuty Whether the character is on duty, false outside the legal domain.
function Siku.jobs.isOnDuty(characterId, jobName)
  local job <const> = internal.getJob(jobName)

  if not job or not internal.isLegal(job) then
    return false
  end

  local entries <const> = state.memberships[characterId]
  local entry <const> = entries and entries[job.name] or nil

  return entry ~= nil and entry.onDuty == true
end

--- The legal jobs a character is on duty in.
---@param characterId number The character id.
---@return table jobNames The list of job names.
function Siku.jobs.getDuties(characterId)
  local duties <const> = {}
  local entries <const> = state.memberships[characterId]

  if not entries then
    return duties
  end

  for jobName, entry in pairs(entries) do
    if entry.onDuty then
      duties[#duties + 1] = jobName
    end
  end

  table.sort(duties)

  return duties
end

--- Sets the duty of a character in a legal job. The duty lives in memory
--- only, for characters in play, and ends with the session.
---@param characterId number The character id.
---@param jobName string The job name.
---@param onDuty boolean Whether the character takes or leaves the duty.
---@return boolean changed Whether the duty moved.
---@return string? reason unknown_job, inactive_job, no_duty, offline, not_member, unchanged or duty_limit.
function Siku.jobs.setDuty(characterId, jobName, onDuty)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  if not job.active then
    return false, 'inactive_job'
  end

  if not internal.isLegal(job) then
    return false, 'no_duty'
  end

  local entries <const> = state.memberships[characterId]

  if not entries then
    return false, 'offline'
  end

  local entry <const> = entries[job.name]

  if not entry then
    return false, 'not_member'
  end

  local value <const> = onDuty == true

  if entry.onDuty == value then
    return false, 'unchanged'
  end

  local limit <const> = internal.limitOf(internal.domainRules(job).maxOnDuty)

  if value and limit and #Siku.jobs.getDuties(characterId) >= limit then
    return false, 'duty_limit'
  end

  entry.onDuty = value

  local counters <const> = internal.counter(job.name)

  counters.onDuty = math.max(0, counters.onDuty + (value and 1 or -1))

  internal.push(characterId)
  internal.emit(EVENT_DUTY_CHANGED, state.sessions[characterId], characterId, job.name, value)

  return true, nil
end

--- Ends every duty held in a job, when the job goes dormant.
---@param job table The registry entry.
---@return nil
function internal.dropDuties(job)
  for characterId, entries in pairs(state.memberships) do
    local entry <const> = entries[job.name]

    if entry and entry.onDuty then
      entry.onDuty = false
      internal.counter(job.name).onDuty = math.max(0, internal.counter(job.name).onDuty - 1)
      internal.push(characterId)
      internal.emit(EVENT_DUTY_CHANGED, state.sessions[characterId], characterId, job.name, false)
    end
  end
end
