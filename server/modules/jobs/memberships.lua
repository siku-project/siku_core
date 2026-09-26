local internal <const> = _SikuInternal.jobs
local state <const> = internal.state

local EVENT_MEMBER_ADDED <const> = 'memberAdded'
local EVENT_MEMBER_REMOVED <const> = 'memberRemoved'
local EVENT_GRADE_CHANGED <const> = 'gradeChanged'

--- Reads the memberships of a character from the database, keyed by job
--- name. A membership of a job the registry does not know is skipped.
---@param characterId number The character id.
---@return table entries The memberships by job name.
local function loadEntries(characterId)
  local rows <const> = MySQL.query.await(
    'SELECT job_id, grade_id, hired_at FROM job_memberships WHERE character_id = ?',
    { characterId }
  )

  local entries <const> = {}

  for index = 1, #rows do
    local row <const> = rows[index]
    local job <const> = state.byId[row.job_id]

    if job then
      entries[job.name] = {
        jobId = job.id,
        gradeId = row.grade_id,
        hiredAt = row.hired_at,
        onDuty = false,
      }
    else
      Siku.print.warn(('Character %d holds a membership of unknown job #%d'):format(characterId, row.job_id))
    end
  end

  return entries
end

--- The memberships of a character: the cache when it is in play, the
--- database otherwise.
---@param characterId number The character id.
---@return table entries The memberships by job name.
function internal.entriesOf(characterId)
  return state.memberships[characterId] or loadEntries(characterId)
end

--- One membership of a character.
---@param characterId number The character id.
---@param job table The registry entry.
---@return table? entry The membership, or nil.
function internal.entryOf(characterId, job)
  return internal.entriesOf(characterId)[job.name]
end

--- Whether a character row exists, for a hire aimed at someone offline.
---@param characterId number The character id.
---@return boolean exists Whether the character is in the database.
local function characterExists(characterId)
  if state.memberships[characterId] then
    return true
  end

  return MySQL.scalar.await('SELECT id FROM characters WHERE id = ?', { characterId }) ~= nil
end

--- How many jobs of a domain a character holds.
---@param entries table The memberships by job name.
---@param domain string The domain.
---@return number count The number held.
local function countDomain(entries, domain)
  local count = 0

  for jobName in pairs(entries) do
    local job <const> = state.byName[jobName]

    if job and job.domain == domain then
      count = count + 1
    end
  end

  return count
end

--- Whether a member acting on their own job outranks what the action
--- touches. Which permission allows the action is the job resource's
--- vocabulary and its check to make before calling; the engine only holds
--- the hierarchy. Staff and code acting from outside the job, or a caller
--- that turned the check off, go through.
---@param context? table { performedBy?, enforceHierarchy? }.
---@param job table The registry entry.
---@param touchedRank number The highest rank the action touches.
---@return boolean allowed Whether the actor may act.
---@return string? reason Why not.
local function checkHierarchy(context, job, touchedRank)
  if type(context) ~= 'table' or not context.performedBy or context.enforceHierarchy == false then
    return true, nil
  end

  local actor <const> = internal.entryOf(context.performedBy, job)

  if not actor then
    return true, nil
  end

  local actorGrade <const> = job.grades.byId[actor.gradeId]

  if not actorGrade or actorGrade.rank <= touchedRank then
    return false, 'hierarchy'
  end

  return true, nil
end

--- The character acting, for the audit log.
---@param context? table The mutation context.
---@return number? performedBy The character id, or nil.
local function performerOf(context)
  return type(context) == 'table' and context.performedBy or nil
end

--- The memberships of a character, sorted by domain then label.
---@param characterId number The character id.
---@return table memberships The public memberships.
function Siku.jobs.getMemberships(characterId)
  local memberships <const> = {}

  for jobName, entry in pairs(internal.entriesOf(characterId)) do
    local job <const> = state.byName[jobName]

    if job then
      memberships[#memberships + 1] = internal.publicMembership(job, entry)
    end
  end

  table.sort(memberships, function(a, b)
    if a.domain ~= b.domain then
      return a.domain < b.domain
    end

    return a.label < b.label
  end)

  return memberships
end

--- The membership of a character in one job.
---@param characterId number The character id.
---@param jobName string The job name.
---@return table? membership The public membership, or nil.
function Siku.jobs.getMembership(characterId, jobName)
  local job <const> = internal.getJob(jobName)
  local entry <const> = job and internal.entryOf(characterId, job) or nil

  if not entry then
    return nil
  end

  return internal.publicMembership(job, entry)
end

--- Whether a character belongs to a job.
---@param characterId number The character id.
---@param jobName string The job name.
---@return boolean member Whether a membership exists.
function Siku.jobs.hasJob(characterId, jobName)
  local job <const> = internal.getJob(jobName)

  return job ~= nil and internal.entryOf(characterId, job) ~= nil
end

--- Whether a character holds no legal job. An illegal organisation is no
--- declared employment.
---@param characterId number The character id.
---@return boolean unemployed Whether the character is unemployed.
function Siku.jobs.isUnemployed(characterId)
  return countDomain(internal.entriesOf(characterId), internal.DOMAIN_LEGAL) == 0
end

--- Adds a character to a job at a grade.
---@param characterId number The character id.
---@param jobName string The job name.
---@param gradeName string The grade name.
---@param context? table { performedBy?, enforceHierarchy? }.
---@return boolean hired Whether the membership was created.
---@return string? reason unknown_job, inactive_job, unknown_grade, unknown_character, already_member, domain_limit or hierarchy.
function Siku.jobs.hire(characterId, jobName, gradeName, context)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  if not job.active then
    return false, 'inactive_job'
  end

  local grade <const> = internal.getGrade(job, gradeName)

  if not grade then
    return false, 'unknown_grade'
  end

  if type(characterId) ~= 'number' or not characterExists(characterId) then
    return false, 'unknown_character'
  end

  local entries <const> = internal.entriesOf(characterId)

  if entries[job.name] then
    return false, 'already_member'
  end

  local limit <const> = internal.limitOf(internal.domainRules(job).maxJobs)

  if limit and countDomain(entries, job.domain) >= limit then
    return false, 'domain_limit'
  end

  local allowed <const>, reason <const> = checkHierarchy(context, job, grade.rank)

  if not allowed then
    return false, reason
  end

  MySQL.insert.await(
    'INSERT INTO job_memberships (character_id, job_id, grade_id) VALUES (?, ?, ?)',
    { characterId, job.id, grade.id }
  )

  local cached <const> = state.memberships[characterId]

  if cached then
    cached[job.name] = { jobId = job.id, gradeId = grade.id, hiredAt = os.date('%Y-%m-%d %H:%M:%S'), onDuty = false }
    internal.counter(job.name).online = internal.counter(job.name).online + 1
    internal.push(characterId)
  end

  internal.audit('hired', job.id, characterId, performerOf(context), ('grade=%s'):format(grade.name))
  internal.emit(EVENT_MEMBER_ADDED, characterId, job.name, grade.name, state.sessions[characterId])

  return true, nil
end

--- Removes a character from a job, ending its duty first.
---@param characterId number The character id.
---@param jobName string The job name.
---@param context? table { performedBy?, enforceHierarchy? }.
---@return boolean fired Whether the membership was removed.
---@return string? reason unknown_job, not_member or hierarchy.
function Siku.jobs.fire(characterId, jobName, context)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local entry <const> = internal.entryOf(characterId, job)

  if not entry then
    return false, 'not_member'
  end

  local grade <const> = job.grades.byId[entry.gradeId]
  local allowed <const>, reason <const> = checkHierarchy(context, job, grade and grade.rank or 0)

  if not allowed then
    return false, reason
  end

  if entry.onDuty then
    Siku.jobs.setDuty(characterId, job.name, false)
  end

  MySQL.update.await('DELETE FROM job_memberships WHERE character_id = ? AND job_id = ?', { characterId, job.id })

  local cached <const> = state.memberships[characterId]

  if cached then
    cached[job.name] = nil
    internal.counter(job.name).online = math.max(0, internal.counter(job.name).online - 1)
    internal.push(characterId)
  end

  internal.audit('fired', job.id, characterId, performerOf(context), grade and ('grade=%s'):format(grade.name) or nil)
  internal.emit(EVENT_MEMBER_REMOVED, characterId, job.name, state.sessions[characterId])

  return true, nil
end

--- Moves a member to another grade of the same job.
---@param characterId number The character id.
---@param jobName string The job name.
---@param gradeName string The grade name.
---@param context? table { performedBy?, enforceHierarchy? }.
---@return boolean changed Whether the grade moved.
---@return string? reason unknown_job, not_member, unknown_grade, same_grade or hierarchy.
function Siku.jobs.setGrade(characterId, jobName, gradeName, context)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local entry <const> = internal.entryOf(characterId, job)

  if not entry then
    return false, 'not_member'
  end

  local grade <const> = internal.getGrade(job, gradeName)

  if not grade then
    return false, 'unknown_grade'
  end

  if entry.gradeId == grade.id then
    return false, 'same_grade'
  end

  local previous <const> = job.grades.byId[entry.gradeId]
  local touched <const> = math.max(grade.rank, previous and previous.rank or 0)
  local allowed <const>, reason <const> = checkHierarchy(context, job, touched)

  if not allowed then
    return false, reason
  end

  internal.applyGrade(characterId, job, entry, grade)
  internal.audit(
    'grade_changed',
    job.id,
    characterId,
    performerOf(context),
    ('from=%s to=%s'):format(previous and previous.name or '?', grade.name)
  )

  return true, nil
end

--- Writes a grade change and tells whoever listens, shared by setGrade
--- and by the demotion a deleted grade causes.
---@param characterId number The character id.
---@param job table The registry entry.
---@param entry table The membership.
---@param grade table The grade to move to.
---@return nil
function internal.applyGrade(characterId, job, entry, grade)
  local previous <const> = job.grades.byId[entry.gradeId]

  MySQL.update.await(
    'UPDATE job_memberships SET grade_id = ? WHERE character_id = ? AND job_id = ?',
    { grade.id, characterId, job.id }
  )

  entry.gradeId = grade.id

  internal.push(characterId)
  internal.emit(EVENT_GRADE_CHANGED, characterId, job.name, grade.name, previous and previous.name or nil, state.sessions[characterId])
end

--- Every member of a job, online or not, from the highest rank down.
---@param jobName string The job name.
---@return table members The list of { characterId, firstName, lastName, grade, gradeLabel, rank, online, onDuty?, hiredAt }.
function Siku.jobs.getMembers(jobName)
  local job <const> = internal.getJob(jobName)

  if not job then
    return {}
  end

  local rows <const> = MySQL.query.await(
    'SELECT m.character_id, m.grade_id, m.hired_at, c.first_name, c.last_name FROM job_memberships m JOIN characters c ON c.id = m.character_id WHERE m.job_id = ?',
    { job.id }
  )

  local members <const> = {}

  for index = 1, #rows do
    local row <const> = rows[index]
    local cached <const> = state.memberships[row.character_id]
    local entry <const> = cached and cached[job.name] or nil
    local grade <const> = job.grades.byId[entry and entry.gradeId or row.grade_id]

    members[#members + 1] = {
      characterId = row.character_id,
      firstName = row.first_name,
      lastName = row.last_name,
      grade = grade and grade.name or nil,
      gradeLabel = grade and grade.label or nil,
      rank = grade and grade.rank or 0,
      online = entry ~= nil,
      onDuty = internal.dutyOf(job, entry),
      hiredAt = row.hired_at,
    }
  end

  table.sort(members, function(a, b)
    if a.rank ~= b.rank then
      return a.rank > b.rank
    end

    return a.lastName < b.lastName
  end)

  return members
end

--- The members of a job currently in play.
---@param jobName string The job name.
---@return table members The list of { characterId, sessionId, grade, rank, onDuty? }.
function Siku.jobs.getOnlineMembers(jobName)
  local job <const> = internal.getJob(jobName)

  if not job then
    return {}
  end

  local members <const> = {}

  for characterId, entries in pairs(state.memberships) do
    local entry <const> = entries[job.name]

    if entry then
      local grade <const> = job.grades.byId[entry.gradeId]

      members[#members + 1] = {
        characterId = characterId,
        sessionId = state.sessions[characterId],
        grade = grade and grade.name or nil,
        rank = grade and grade.rank or 0,
        onDuty = internal.dutyOf(job, entry),
      }
    end
  end

  return members
end

--- How many characters belong to a job, in play or not.
---@param jobName string The job name.
---@return number total The number of memberships.
function Siku.jobs.countMembers(jobName)
  local job <const> = internal.getJob(jobName)

  if not job then
    return 0
  end

  local total <const> = MySQL.scalar.await('SELECT COUNT(*) FROM job_memberships WHERE job_id = ?', { job.id })

  return type(total) == 'number' and total or 0
end
