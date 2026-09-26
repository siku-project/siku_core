local internal <const> = _SikuInternal.jobs
local state <const> = internal.state

local LABEL_MAX_LENGTH <const> = 100
local EVENT_DEFINITION_CHANGED <const> = 'definitionChanged'

--- Whether a label is one the engine stores.
---@param label any The candidate.
---@return boolean valid Whether it is a non-empty string within bounds.
local function isValidLabel(label)
  return type(label) == 'string' and label ~= '' and #label <= LABEL_MAX_LENGTH
end

--- Reloads a job after an edit and tells its members and the ecosystem.
---@param job table The registry entry before the edit.
---@return nil
local function settle(job)
  local reloaded <const> = internal.reloadJob(job.id)

  if not reloaded then
    return
  end

  for characterId, entries in pairs(state.memberships) do
    if entries[reloaded.name] then
      internal.push(characterId)
    end
  end

  internal.emit(EVENT_DEFINITION_CHANGED, reloaded.name, internal.publicJob(reloaded))
end

--- Whether a rank is free in a job, apart from one grade.
---@param job table The registry entry.
---@param rank number The rank wanted.
---@param except? table The grade allowed to hold it already.
---@return boolean free Whether no other grade holds the rank.
local function isRankFree(job, rank, except)
  for _, grade in pairs(job.grades.byName) do
    if grade ~= except and grade.rank == rank then
      return false
    end
  end

  return true
end

--- Renames a job for the players. Who may edit a job is the job
--- resource's rule, checked with its own permissions before calling;
--- the actor is only recorded here.
---@param jobName string The job name.
---@param label string The new label.
---@param performedBy? number The character acting, for the audit log.
---@return boolean changed Whether the label moved.
---@return string? reason unknown_job, invalid_label or unchanged.
function Siku.jobs.setLabel(jobName, label, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  if not isValidLabel(label) then
    return false, 'invalid_label'
  end

  if job.label == label then
    return false, 'unchanged'
  end

  MySQL.update.await('UPDATE jobs SET label = ? WHERE id = ?', { label, job.id })

  internal.audit('label_changed', job.id, nil, performedBy, ('from=%s to=%s'):format(job.label, label))
  settle(job)

  return true, nil
end

--- Adds a grade to a job.
---@param jobName string The job name.
---@param grade table { name, label, rank, permissions? }.
---@param performedBy? number The character acting, for the audit log.
---@return boolean created Whether the grade exists now.
---@return string? reason unknown_job, invalid_grade, duplicate, rank_taken or invalid_permission.
function Siku.jobs.createGrade(jobName, grade, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  if type(grade) ~= 'table' or type(grade.name) ~= 'string' or not grade.name:match(internal.NAME_PATTERN) then
    return false, 'invalid_grade'
  end

  local rank <const> = math.tointeger(grade.rank)

  if not isValidLabel(grade.label) or not rank or rank < 0 then
    return false, 'invalid_grade'
  end

  if job.grades.byName[grade.name] then
    return false, 'duplicate'
  end

  if not isRankFree(job, rank) then
    return false, 'rank_taken'
  end

  local permissions <const> = grade.permissions or {}

  for index = 1, #permissions do
    if not internal.isValidPermission(permissions[index]) then
      return false, 'invalid_permission'
    end
  end

  local gradeId <const> = MySQL.insert.await(
    'INSERT INTO job_grades (job_id, name, label, rank_order) VALUES (?, ?, ?, ?)',
    { job.id, grade.name, grade.label, rank }
  )

  for index = 1, #permissions do
    MySQL.update.await('INSERT IGNORE INTO job_grade_permissions (grade_id, pattern) VALUES (?, ?)', { gradeId, permissions[index] })
  end

  internal.audit('grade_created', job.id, nil, performedBy, ('grade=%s rank=%d'):format(grade.name, rank))
  settle(job)

  return true, nil
end

--- Changes the label or the rank of a grade.
---@param jobName string The job name.
---@param gradeName string The grade name.
---@param changes table { label?, rank? }.
---@param performedBy? number The character acting, for the audit log.
---@return boolean changed Whether something moved.
---@return string? reason unknown_job, unknown_grade, invalid_grade, rank_taken or unchanged.
function Siku.jobs.updateGrade(jobName, gradeName, changes, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local grade <const> = internal.getGrade(job, gradeName)

  if not grade then
    return false, 'unknown_grade'
  end

  if type(changes) ~= 'table' then
    return false, 'invalid_grade'
  end

  local label <const> = changes.label ~= nil and changes.label or grade.label
  local rank <const> = changes.rank ~= nil and math.tointeger(changes.rank) or grade.rank

  if not isValidLabel(label) or not rank or rank < 0 then
    return false, 'invalid_grade'
  end

  if label == grade.label and rank == grade.rank then
    return false, 'unchanged'
  end

  if not isRankFree(job, rank, grade) then
    return false, 'rank_taken'
  end

  MySQL.update.await('UPDATE job_grades SET label = ?, rank_order = ? WHERE id = ?', { label, rank, grade.id })

  internal.audit('grade_updated', job.id, nil, performedBy, ('grade=%s label=%s rank=%d'):format(grade.name, label, rank))
  settle(job)

  return true, nil
end

--- Removes a grade, moving its members to the grade just below. The
--- lowest grade cannot go while anyone holds it: there is nowhere to go.
---@param jobName string The job name.
---@param gradeName string The grade name.
---@param performedBy? number The character acting, for the audit log.
---@return boolean deleted Whether the grade is gone.
---@return string? reason unknown_job, unknown_grade or lowest_grade.
---@return table? demoted The character ids moved down.
function Siku.jobs.deleteGrade(jobName, gradeName, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local grade <const> = internal.getGrade(job, gradeName)

  if not grade then
    return false, 'unknown_grade'
  end

  local holders <const> = MySQL.query.await('SELECT character_id FROM job_memberships WHERE grade_id = ?', { grade.id })
  local below <const> = internal.gradeBelow(job, grade.rank)

  if #holders > 0 and not below then
    return false, 'lowest_grade'
  end

  local demoted <const> = {}

  for index = 1, #holders do
    local characterId <const> = holders[index].character_id
    local entry <const> = internal.entryOf(characterId, job)

    if entry then
      internal.applyGrade(characterId, job, entry, below)
      internal.audit('grade_changed', job.id, characterId, performedBy, ('from=%s to=%s cause=grade_deleted'):format(grade.name, below.name))
      demoted[#demoted + 1] = characterId
    end
  end

  MySQL.update.await('DELETE FROM job_grades WHERE id = ?', { grade.id })

  internal.audit('grade_deleted', job.id, nil, performedBy, ('grade=%s demoted=%d'):format(grade.name, #demoted))
  settle(job)

  return true, nil, demoted
end

--- Declares a permission a job offers, with its duty requirement. The
--- name is the job's own vocabulary: the engine gives it no meaning.
---@param jobName string The job name.
---@param permission table|string { name, duty? } or the name.
---@param performedBy? number The character acting, for the audit log.
---@return boolean declared Whether the permission exists now.
---@return string? reason unknown_job, invalid_permission or duplicate.
function Siku.jobs.declarePermission(jobName, permission, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local name <const> = type(permission) == 'table' and permission.name or permission
  local requiresDuty <const> = type(permission) == 'table' and permission.duty == true

  if type(name) ~= 'string' or name:find('*', 1, true) or not internal.isValidPermission(name) then
    return false, 'invalid_permission'
  end

  if job.permissions.byName[name] then
    return false, 'duplicate'
  end

  MySQL.insert.await(
    'INSERT INTO job_permissions (job_id, name, requires_duty) VALUES (?, ?, ?)',
    { job.id, name, requiresDuty and 1 or 0 }
  )

  internal.audit('permission_declared', job.id, nil, performedBy, ('permission=%s duty=%s'):format(name, tostring(requiresDuty)))
  settle(job)

  return true, nil
end

--- Forgets a permission a job declared. Grades keep the patterns they
--- were granted; the permission simply loses its duty rule.
---@param jobName string The job name.
---@param name string The permission name.
---@param performedBy? number The character acting, for the audit log.
---@return boolean removed Whether the permission is gone.
---@return string? reason unknown_job or unknown_permission.
function Siku.jobs.removePermission(jobName, name, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local permission <const> = job.permissions.byName[name]

  if not permission then
    return false, 'unknown_permission'
  end

  MySQL.update.await('DELETE FROM job_permissions WHERE id = ?', { permission.id })

  internal.audit('permission_removed', job.id, nil, performedBy, ('permission=%s'):format(name))
  settle(job)

  return true, nil
end

--- Grants a permission pattern to a grade.
---@param jobName string The job name.
---@param gradeName string The grade name.
---@param pattern string The pattern, wildcards and negation allowed.
---@param performedBy? number The character acting, for the audit log.
---@return boolean granted Whether the grade holds it now.
---@return string? reason unknown_job, unknown_grade, invalid_permission or unchanged.
function Siku.jobs.grantPermission(jobName, gradeName, pattern, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local grade <const> = internal.getGrade(job, gradeName)

  if not grade then
    return false, 'unknown_grade'
  end

  if not internal.isValidPermission(pattern) then
    return false, 'invalid_permission'
  end

  if grade.granted[pattern] then
    return false, 'unchanged'
  end

  MySQL.update.await('INSERT IGNORE INTO job_grade_permissions (grade_id, pattern) VALUES (?, ?)', { grade.id, pattern })

  internal.audit('permission_granted', job.id, nil, performedBy, ('grade=%s pattern=%s'):format(grade.name, pattern))
  settle(job)

  return true, nil
end

--- Takes a permission pattern away from a grade.
---@param jobName string The job name.
---@param gradeName string The grade name.
---@param pattern string The pattern as it was granted.
---@param performedBy? number The character acting, for the audit log.
---@return boolean revoked Whether the grade lost it.
---@return string? reason unknown_job, unknown_grade or unchanged.
function Siku.jobs.revokePermission(jobName, gradeName, pattern, performedBy)
  local job <const> = internal.getJob(jobName)

  if not job then
    return false, 'unknown_job'
  end

  local grade <const> = internal.getGrade(job, gradeName)

  if not grade then
    return false, 'unknown_grade'
  end

  if not grade.granted[pattern] then
    return false, 'unchanged'
  end

  MySQL.update.await('DELETE FROM job_grade_permissions WHERE grade_id = ? AND pattern = ?', { grade.id, pattern })

  internal.audit('permission_revoked', job.id, nil, performedBy, ('grade=%s pattern=%s'):format(grade.name, pattern))
  settle(job)

  return true, nil
end
