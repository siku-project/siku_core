local internal <const> = _SikuInternal.jobs
local state <const> = internal.state

local LABEL_MAX_LENGTH <const> = 100
local EVENT_REGISTERED <const> = 'registered'
local EVENT_DEACTIVATED <const> = 'deactivated'

--- Builds an empty registry entry for a job row.
---@param row table The `jobs` row.
---@return table job The entry.
local function createEntry(row)
  return {
    id = row.id,
    name = row.name,
    label = row.label,
    domain = row.domain,
    resource = row.resource,
    active = false,
    grades = { byName = {}, byId = {} },
    permissions = { byName = {}, byId = {} },
  }
end

--- Attaches a grade row to its job entry.
---@param job table The registry entry.
---@param row table The `job_grades` row.
---@return table grade The grade.
local function attachGrade(job, row)
  local grade <const> = {
    id = row.id,
    jobId = job.id,
    name = row.name,
    label = row.label,
    rank = row.rank_order,
    granted = {},
  }

  job.grades.byName[grade.name] = grade
  job.grades.byId[grade.id] = grade

  return grade
end

--- Attaches a declared permission row to its job entry.
---@param job table The registry entry.
---@param row table The `job_permissions` row.
---@return table permission The permission.
local function attachPermission(job, row)
  local permission <const> = {
    id = row.id,
    name = row.name,
    requiresDuty = row.requires_duty == 1 or row.requires_duty == true,
  }

  job.permissions.byName[permission.name] = permission
  job.permissions.byId[permission.id] = permission

  return permission
end

--- Reads one job and everything attached to it from the database into a
--- fresh entry, keeping the live flag of the entry it replaces.
---@param jobId number The job id.
---@return table? job The rebuilt entry, or nil when the row is gone.
function internal.reloadJob(jobId)
  local row <const> = MySQL.single.await('SELECT * FROM jobs WHERE id = ?', { jobId })

  if not row then
    return nil
  end

  local previous <const> = state.byId[jobId]
  local job <const> = createEntry(row)

  job.active = previous ~= nil and previous.active

  local grades <const> = MySQL.query.await('SELECT * FROM job_grades WHERE job_id = ?', { jobId })

  for index = 1, #grades do
    attachGrade(job, grades[index])
  end

  local permissions <const> = MySQL.query.await('SELECT * FROM job_permissions WHERE job_id = ?', { jobId })

  for index = 1, #permissions do
    attachPermission(job, permissions[index])
  end

  local grants <const> = MySQL.query.await(
    'SELECT gp.grade_id, gp.pattern FROM job_grade_permissions gp JOIN job_grades g ON g.id = gp.grade_id WHERE g.job_id = ?',
    { jobId }
  )

  for index = 1, #grants do
    local grade <const> = job.grades.byId[grants[index].grade_id]

    if grade then
      grade.granted[grants[index].pattern] = true
    end
  end

  if previous and previous.name ~= job.name then
    state.byName[previous.name] = nil
  end

  state.byName[job.name] = job
  state.byId[job.id] = job

  return job
end

--- Reads the whole registry from the database. Every job comes up
--- dormant: its resource wakes it up by registering.
---@return number count The number of jobs loaded.
local function loadRegistry()
  state.byName = {}
  state.byId = {}

  local rows <const> = MySQL.query.await('SELECT id FROM jobs')

  for index = 1, #rows do
    internal.reloadJob(rows[index].id)
  end

  return #rows
end

--- Normalises one permission declaration, given as a name or as a table.
---@param declaration any The declaration.
---@return table? permission { name, requiresDuty }, nil when malformed.
local function normalizePermission(declaration)
  local name <const> = type(declaration) == 'table' and declaration.name or declaration
  local requiresDuty <const> = type(declaration) == 'table' and declaration.duty == true

  if type(name) ~= 'string' or name:find('*', 1, true) or not internal.isValidPermission(name) then
    return nil
  end

  return { name = name, requiresDuty = requiresDuty }
end

--- Normalises one grade declaration.
---@param declaration any The declaration.
---@return table? grade { name, label, rank, permissions }, nil when malformed.
---@return string? reason What was wrong.
local function normalizeGrade(declaration)
  if type(declaration) ~= 'table' then
    return nil, 'grade must be a table'
  end

  if type(declaration.name) ~= 'string' or not declaration.name:match(internal.NAME_PATTERN) then
    return nil, ('grade name %q is invalid'):format(tostring(declaration.name))
  end

  if type(declaration.label) ~= 'string' or declaration.label == '' or #declaration.label > LABEL_MAX_LENGTH then
    return nil, ('grade %q needs a label'):format(declaration.name)
  end

  local rank <const> = math.tointeger(declaration.rank)

  if not rank or rank < 0 then
    return nil, ('grade %q needs a whole, positive rank'):format(declaration.name)
  end

  local permissions <const> = {}

  for index = 1, #(declaration.permissions or {}) do
    local pattern <const> = declaration.permissions[index]

    if not internal.isValidPermission(pattern) then
      return nil, ('grade %q grants an invalid permission %q'):format(declaration.name, tostring(pattern))
    end

    permissions[#permissions + 1] = pattern
  end

  return { name = declaration.name, label = declaration.label, rank = rank, permissions = permissions }, nil
end

--- Validates a job definition and returns it in the shape the registry
--- writes.
---@param definition any The declaration a resource passed.
---@return table? normalized The normalized definition, nil when refused.
---@return string? reason What was wrong.
local function normalizeDefinition(definition)
  if type(definition) ~= 'table' then
    return nil, 'definition must be a table'
  end

  if type(definition.name) ~= 'string' or not definition.name:match(internal.NAME_PATTERN) then
    return nil, ('job name %q is invalid: lowercase letters, digits and underscores'):format(tostring(definition.name))
  end

  if type(definition.label) ~= 'string' or definition.label == '' or #definition.label > LABEL_MAX_LENGTH then
    return nil, ('job %q needs a label'):format(definition.name)
  end

  local domain <const> = definition.domain or internal.DOMAIN_LEGAL

  if not internal.isValidDomain(domain) then
    return nil, ('job %q declares an unknown domain %q'):format(definition.name, tostring(domain))
  end

  local permissions <const> = {}
  local seenPermissions <const> = {}

  for index = 1, #(definition.permissions or {}) do
    local permission <const> = normalizePermission(definition.permissions[index])

    if not permission then
      return nil, ('job %q declares an invalid permission at #%d'):format(definition.name, index)
    end

    if seenPermissions[permission.name] then
      return nil, ('job %q declares permission %q twice'):format(definition.name, permission.name)
    end

    seenPermissions[permission.name] = true
    permissions[#permissions + 1] = permission
  end

  if type(definition.grades) ~= 'table' or #definition.grades == 0 then
    return nil, ('job %q needs at least one grade'):format(definition.name)
  end

  local grades <const> = {}
  local seenNames <const> = {}
  local seenRanks <const> = {}

  for index = 1, #definition.grades do
    local grade <const>, reason <const> = normalizeGrade(definition.grades[index])

    if not grade then
      return nil, ('job %q: %s'):format(definition.name, reason)
    end

    if seenNames[grade.name] then
      return nil, ('job %q declares grade %q twice'):format(definition.name, grade.name)
    end

    if seenRanks[grade.rank] then
      return nil, ('job %q gives rank %d to two grades'):format(definition.name, grade.rank)
    end

    seenNames[grade.name] = true
    seenRanks[grade.rank] = true
    grades[#grades + 1] = grade
  end

  return {
    name = definition.name,
    label = definition.label,
    domain = domain,
    permissions = permissions,
    grades = grades,
  }, nil
end

--- Whether another resource currently holds a job.
---@param job table The registry entry.
---@param resource string The resource registering.
---@return boolean taken Whether a different, running resource owns it.
local function isHeldElsewhere(job, resource)
  if not job.resource or job.resource == resource then
    return false
  end

  return job.active
end

--- Writes what the declaration adds to the stored definition: the job when
--- new, the permissions and grades that do not exist yet, never touching
--- what a patron may have edited since.
---@param normalized table The normalized definition.
---@param existing? table The registry entry, nil for a first registration.
---@param resource string The resource registering.
---@return number jobId The job id.
local function seedDefinition(normalized, existing, resource)
  local jobId = existing and existing.id or nil

  if not jobId then
    jobId = MySQL.insert.await(
      'INSERT INTO jobs (name, label, domain, resource) VALUES (?, ?, ?, ?)',
      { normalized.name, normalized.label, normalized.domain, resource }
    )
  else
    MySQL.update.await('UPDATE jobs SET domain = ?, resource = ? WHERE id = ?', { normalized.domain, resource, jobId })
  end

  for index = 1, #normalized.permissions do
    local permission <const> = normalized.permissions[index]

    MySQL.update.await(
      'INSERT INTO job_permissions (job_id, name, requires_duty) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE requires_duty = VALUES(requires_duty)',
      { jobId, permission.name, permission.requiresDuty and 1 or 0 }
    )
  end

  for index = 1, #normalized.grades do
    local grade <const> = normalized.grades[index]
    local known <const> = existing and existing.grades.byName[grade.name] or nil

    if not known then
      local rankTaken = false

      if existing then
        for _, other in pairs(existing.grades.byName) do
          if other.rank == grade.rank then
            rankTaken = true
          end
        end
      end

      if rankTaken then
        Siku.print.warn(('Job %q: grade %q skipped, rank %d is already used'):format(normalized.name, grade.name, grade.rank))
      else
        local gradeId <const> = MySQL.insert.await(
          'INSERT INTO job_grades (job_id, name, label, rank_order) VALUES (?, ?, ?, ?)',
          { jobId, grade.name, grade.label, grade.rank }
        )

        for patternIndex = 1, #grade.permissions do
          MySQL.update.await(
            'INSERT IGNORE INTO job_grade_permissions (grade_id, pattern) VALUES (?, ?)',
            { gradeId, grade.permissions[patternIndex] }
          )
        end
      end
    end
  end

  return jobId
end

--- Registers a job on behalf of the resource declaring it. The first
--- registration writes the definition; the next ones only add what the
--- declaration gained, so an edit made in game survives every restart.
--- The job is live from here until its resource stops.
---@param definition table { name, label, domain?, permissions?, grades }.
---@return boolean registered Whether the job is live.
---@return string? reason Why it was refused.
function Siku.jobs.register(definition)
  local resource <const> = GetInvokingResource() or GetCurrentResourceName()
  local normalized <const>, reason <const> = normalizeDefinition(definition)

  if not normalized then
    Siku.print.error(('Job registration from %q refused: %s'):format(resource, reason))
    return false, reason
  end

  if not internal.waitReady() then
    Siku.print.error(('Job %q could not be registered: the registry never came up'):format(normalized.name))
    return false, 'not_ready'
  end

  local existing <const> = state.byName[normalized.name]

  if existing and isHeldElsewhere(existing, resource) then
    Siku.print.error(('Job %q is owned by %q, registration from %q refused'):format(normalized.name, existing.resource, resource))
    return false, 'owned_elsewhere'
  end

  if existing and existing.resource and existing.resource ~= resource then
    Siku.print.warn(('Job %q moves from %q to %q'):format(normalized.name, existing.resource, resource))
  end

  local jobId <const> = seedDefinition(normalized, existing, resource)
  local job <const> = internal.reloadJob(jobId)

  if not job then
    return false, 'reload_failed'
  end

  job.active = true

  internal.emit(EVENT_REGISTERED, job.name, internal.publicJob(job))
  Siku.print.info(('Job %q registered by %q (%d grade(s))'):format(job.name, resource, Siku.table.size(job.grades.byName)))

  return true, nil
end

--- Puts the jobs of a stopping resource to sleep: their members keep
--- their grades, nobody keeps a duty, no permission resolves.
---@param resource string The resource that stopped.
---@return nil
local function deactivateJobsOf(resource)
  for _, job in pairs(state.byName) do
    if job.active and job.resource == resource then
      job.active = false

      internal.dropDuties(job)
      internal.emit(EVENT_DEACTIVATED, job.name)
      Siku.print.info(('Job %q is dormant: %q stopped'):format(job.name, resource))
    end
  end
end

--- Reads the registry from the database and opens the engine.
---@return nil
function _SikuInternal.InitJobs()
  local count <const> = loadRegistry()

  state.ready = true

  Siku.print.success(('Job engine initialized with %d job(s)'):format(count))
end

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    return
  end

  deactivateJobsOf(resource)
end)
