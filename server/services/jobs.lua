Siku.jobs = {}

local DOMAIN_LEGAL <const> = 'legal'
local DOMAIN_ILLEGAL <const> = 'illegal'
local EVENT_FORMAT <const> = 'siku:jobs:%s'
local CLIENT_EVENT <const> = 'siku:client:jobsUpdated'
local SEGMENT_PATTERN <const> = '^[%w_]+$'
local NAME_PATTERN <const> = '^[%l][%l%d_]*$'
local NEGATION <const> = '-'
local WILDCARD <const> = '*'
local READY_POLL_MS <const> = 100
local READY_TIMEOUT_MS <const> = 30000

local state <const> = {
  ready = false,
  byName = {},
  byId = {},
  memberships = {},
  sessions = {},
  counters = {},
}

_SikuInternal.jobs = {
  state = state,
  DOMAIN_LEGAL = DOMAIN_LEGAL,
  DOMAIN_ILLEGAL = DOMAIN_ILLEGAL,
  NAME_PATTERN = NAME_PATTERN,
  CLIENT_EVENT = CLIENT_EVENT,
}

--- Fires one engine event, prefixed the way every other core event is.
---@param name string The event name after `siku:jobs:`.
---@vararg any The payload.
---@return nil
function _SikuInternal.jobs.emit(name, ...)
  TriggerEvent(EVENT_FORMAT:format(name), ...)
end

--- Blocks the calling thread until the registry has been read from the
--- database, which happens once at boot.
---@return boolean ready Whether the registry came up in time.
function _SikuInternal.jobs.waitReady()
  if state.ready then
    return true
  end

  local start <const> = GetGameTimer()

  while not state.ready do
    if GetGameTimer() - start > READY_TIMEOUT_MS then
      return false
    end

    Wait(READY_POLL_MS)
  end

  return true
end

--- Whether a string is a permission pattern the engine accepts: an optional
--- negation, then dot-separated segments, each an identifier or a lone
--- wildcard. One segment is enough, a job's permissions are already scoped
--- to the job.
---@param permission any The candidate.
---@return boolean valid Whether the pattern is well formed.
function _SikuInternal.jobs.isValidPermission(permission)
  if type(permission) ~= 'string' or permission == '' then
    return false
  end

  local clean <const> = permission:sub(1, 1) == NEGATION and permission:sub(2) or permission

  if clean == '' then
    return false
  end

  for segment in (clean .. '.'):gmatch('(.-)%.') do
    if segment ~= WILDCARD and not segment:match(SEGMENT_PATTERN) then
      return false
    end
  end

  return true
end

--- Whether a domain name is one the engine knows.
---@param domain any The candidate.
---@return boolean valid Whether it is legal or illegal.
function _SikuInternal.jobs.isValidDomain(domain)
  return domain == DOMAIN_LEGAL or domain == DOMAIN_ILLEGAL
end

--- A registered job by name.
---@param jobName any The job name.
---@return table? job The registry entry, or nil.
function _SikuInternal.jobs.getJob(jobName)
  if type(jobName) ~= 'string' then
    return nil
  end

  return state.byName[jobName]
end

--- A grade of a job by name.
---@param job table The registry entry.
---@param gradeName any The grade name.
---@return table? grade The grade, or nil.
function _SikuInternal.jobs.getGrade(job, gradeName)
  if type(gradeName) ~= 'string' then
    return nil
  end

  return job.grades.byName[gradeName]
end

--- The grades of a job from the lowest rank to the highest.
---@param job table The registry entry.
---@return table grades The sorted list.
function _SikuInternal.jobs.sortedGrades(job)
  local grades <const> = {}

  for _, grade in pairs(job.grades.byName) do
    grades[#grades + 1] = grade
  end

  table.sort(grades, function(a, b)
    return a.rank < b.rank
  end)

  return grades
end

--- The highest grade ranked strictly below a rank.
---@param job table The registry entry.
---@param rank number The rank to look under.
---@return table? grade The grade just below, or nil when none is.
function _SikuInternal.jobs.gradeBelow(job, rank)
  local below = nil

  for _, grade in pairs(job.grades.byName) do
    if grade.rank < rank and (not below or grade.rank > below.rank) then
      below = grade
    end
  end

  return below
end

--- Whether a job belongs to the legal domain, the only one with a duty.
---@param job table The registry entry.
---@return boolean legal Whether the job is legal.
function _SikuInternal.jobs.isLegal(job)
  return job.domain == DOMAIN_LEGAL
end

--- The domain rules of a job from the configuration.
---@param job table The registry entry.
---@return table rules { maxJobs, maxOnDuty? }.
function _SikuInternal.jobs.domainRules(job)
  return JobsConfig.domains[job.domain] or {}
end

--- Reads a configured limit: a whole positive number bounds, anything
--- else, false first of all, means no limit.
---@param value any The configured value.
---@return number? limit The bound, or nil when there is none.
function _SikuInternal.jobs.limitOf(value)
  local limit <const> = math.tointeger(value)

  if not limit or limit <= 0 then
    return nil
  end

  return limit
end

--- The public view of a grade: what leaves the engine.
---@param grade table The grade.
---@return table public { name, label, rank, permissions }.
function _SikuInternal.jobs.publicGrade(grade)
  local permissions <const> = {}

  for pattern in pairs(grade.granted) do
    permissions[#permissions + 1] = pattern
  end

  table.sort(permissions)

  return {
    name = grade.name,
    label = grade.label,
    rank = grade.rank,
    permissions = permissions,
  }
end

--- The public view of a job definition: identity, sorted grades and
--- declared permissions, as a copy nobody can write back through.
---@param job table The registry entry.
---@return table public The definition.
function _SikuInternal.jobs.publicJob(job)
  local grades <const> = {}
  local sorted <const> = _SikuInternal.jobs.sortedGrades(job)

  for index = 1, #sorted do
    grades[index] = _SikuInternal.jobs.publicGrade(sorted[index])
  end

  local permissions <const> = {}

  for _, permission in pairs(job.permissions.byName) do
    permissions[#permissions + 1] = { name = permission.name, requiresDuty = permission.requiresDuty }
  end

  table.sort(permissions, function(a, b)
    return a.name < b.name
  end)

  return {
    id = job.id,
    name = job.name,
    label = job.label,
    domain = job.domain,
    resource = job.resource,
    active = job.active,
    grades = grades,
    permissions = permissions,
  }
end

--- The duty of a membership as it leaves the engine: a boolean for a
--- legal job, nothing at all for an illegal one, which has no duty.
---@param job table The registry entry.
---@param entry? table The membership, nil when the character is not in play.
---@return boolean? onDuty The duty, or nil outside the legal domain.
function _SikuInternal.jobs.dutyOf(job, entry)
  if not _SikuInternal.jobs.isLegal(job) then
    return nil
  end

  return entry ~= nil and entry.onDuty == true
end

--- The public view of a membership.
---@param job table The registry entry.
---@param entry table The cached or loaded membership.
---@return table public { job, label, domain, active, grade, gradeLabel, rank, onDuty?, hiredAt }.
function _SikuInternal.jobs.publicMembership(job, entry)
  local grade <const> = job.grades.byId[entry.gradeId]

  return {
    job = job.name,
    label = job.label,
    domain = job.domain,
    active = job.active,
    grade = grade and grade.name or nil,
    gradeLabel = grade and grade.label or nil,
    rank = grade and grade.rank or 0,
    onDuty = _SikuInternal.jobs.dutyOf(job, entry),
    hiredAt = entry.hiredAt,
  }
end

--- The counters of a job, created on first touch.
---@param jobName string The job name.
---@return table counters { online, onDuty }.
function _SikuInternal.jobs.counter(jobName)
  local counters = state.counters[jobName]

  if not counters then
    counters = { online = 0, onDuty = 0 }
    state.counters[jobName] = counters
  end

  return counters
end

--- Writes one line of the job audit log when auditing is enabled.
---@param action string The action performed.
---@param jobId? number The job concerned.
---@param targetCharacterId? number The character concerned.
---@param performedBy? number The character acting, nil for the console or code.
---@param details? string What changed.
---@return nil
function _SikuInternal.jobs.audit(action, jobId, targetCharacterId, performedBy, details)
  if not JobsConfig.audit then
    return
  end

  MySQL.insert.await(
    'INSERT INTO job_audit_log (action, job_id, target_character_id, performed_by, details) VALUES (?, ?, ?, ?, ?)',
    { action, jobId, targetCharacterId, performedBy, details }
  )
end

--- Sends a character its own memberships, and nobody else: what a character
--- belongs to is not for every client to read off a state bag.
---@param characterId number The character id.
---@return nil
function _SikuInternal.jobs.push(characterId)
  local sessionId <const> = state.sessions[characterId]

  if not sessionId then
    return
  end

  TriggerClientEvent(CLIENT_EVENT, sessionId, Siku.jobs.getMemberships(characterId))
end

--- Whether a job is registered, started or not.
---@param jobName string The job name.
---@return boolean exists Whether the job is known.
function Siku.jobs.exists(jobName)
  return _SikuInternal.jobs.getJob(jobName) ~= nil
end

--- Whether the resource owning a job has registered it since the last
--- boot. A dormant job keeps its members but resolves no permission.
---@param jobName string The job name.
---@return boolean active Whether the job is live.
function Siku.jobs.isActive(jobName)
  local job <const> = _SikuInternal.jobs.getJob(jobName)

  return job ~= nil and job.active
end

--- Whether a job belongs to the legal domain.
---@param jobName string The job name.
---@return boolean legal Whether it is legal, false for an unknown job.
function Siku.jobs.isLegal(jobName)
  local job <const> = _SikuInternal.jobs.getJob(jobName)

  return job ~= nil and _SikuInternal.jobs.isLegal(job)
end

--- The definition of a job: identity, grades sorted by rank, declared
--- permissions.
---@param jobName string The job name.
---@return table? definition The public definition, or nil for an unknown job.
function Siku.jobs.getDefinition(jobName)
  local job <const> = _SikuInternal.jobs.getJob(jobName)

  if not job then
    return nil
  end

  return _SikuInternal.jobs.publicJob(job)
end

--- Every registered job, sorted by label.
---@param domain? string Only the jobs of this domain when given.
---@return table definitions The public definitions.
function Siku.jobs.getAll(domain)
  local definitions <const> = {}

  for _, job in pairs(state.byName) do
    if not domain or job.domain == domain then
      definitions[#definitions + 1] = _SikuInternal.jobs.publicJob(job)
    end
  end

  table.sort(definitions, function(a, b)
    return a.label < b.label
  end)

  return definitions
end

--- The grades of a job from the lowest rank to the highest.
---@param jobName string The job name.
---@return table grades The public grades, empty for an unknown job.
function Siku.jobs.getGrades(jobName)
  local job <const> = _SikuInternal.jobs.getJob(jobName)

  if not job then
    return {}
  end

  local grades <const> = {}
  local sorted <const> = _SikuInternal.jobs.sortedGrades(job)

  for index = 1, #sorted do
    grades[index] = _SikuInternal.jobs.publicGrade(sorted[index])
  end

  return grades
end

--- One grade of a job.
---@param jobName string The job name.
---@param gradeName string The grade name.
---@return table? grade The public grade, or nil.
function Siku.jobs.getGrade(jobName, gradeName)
  local job <const> = _SikuInternal.jobs.getJob(jobName)
  local grade <const> = job and _SikuInternal.jobs.getGrade(job, gradeName) or nil

  if not grade then
    return nil
  end

  return _SikuInternal.jobs.publicGrade(grade)
end

--- The permissions a job declares, with their duty requirement.
---@param jobName string The job name.
---@return table permissions The list of { name, requiresDuty }, empty for an unknown job.
function Siku.jobs.getPermissions(jobName)
  local definition <const> = Siku.jobs.getDefinition(jobName)

  return definition and definition.permissions or {}
end

--- The online and on-duty counts of a job, kept in memory.
---@param jobName string The job name.
---@return table counts { online, onDuty }.
function Siku.jobs.count(jobName)
  local counters <const> = state.counters[jobName]

  return {
    online = counters and counters.online or 0,
    onDuty = counters and counters.onDuty or 0,
  }
end
