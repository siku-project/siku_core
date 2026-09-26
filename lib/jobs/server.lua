local CORE <const> = 'siku_core'
local SERVICES_EXPORT <const> = 'objectExport'

local service <const> = exports[CORE][SERVICES_EXPORT]().jobs

--- A handle on one job. Every read is a copy answered by the core, every
--- write goes back to it: the handle carries a name and nothing else, so
--- nothing can drift from the authority.
---@class SikuJob
---@field name string The job name.
local Job <const> = Siku.class('Job')

--- Builds a handle.
---@param name string The job name.
function Job:constructor(name)
  self.name = name
end

--- Registers this job from a declaration, on behalf of the calling resource.
---@param definition table { label, domain?, permissions?, grades }.
---@return boolean registered Whether the job is live.
---@return string? reason Why it was refused.
function Job:register(definition)
  local declaration <const> = {}

  for key, value in pairs(definition) do
    declaration[key] = value
  end

  declaration.name = self.name

  return service.register(declaration)
end

--- Whether the job is known to the core.
---@return boolean exists Whether it is registered.
function Job:exists()
  return service.exists(self.name)
end

--- Whether the job is live.
---@return boolean active Whether its resource registered it since boot.
function Job:isActive()
  return service.isActive(self.name)
end

--- Whether the job is legal.
---@return boolean legal Whether it has a duty.
function Job:isLegal()
  return service.isLegal(self.name)
end

--- The definition: identity, sorted grades, declared permissions.
---@return table? definition The public definition, or nil.
function Job:getDefinition()
  return service.getDefinition(self.name)
end

--- The grades from the lowest rank up.
---@return table grades The public grades.
function Job:getGrades()
  return service.getGrades(self.name)
end

--- One grade.
---@param gradeName string The grade name.
---@return table? grade The public grade, or nil.
function Job:getGrade(gradeName)
  return service.getGrade(self.name, gradeName)
end

--- The declared permissions with their duty rule.
---@return table permissions The list of { name, requiresDuty }.
function Job:getPermissions()
  return service.getPermissions(self.name)
end

--- The online and on-duty counts.
---@return table counts { online, onDuty }.
function Job:count()
  return service.count(self.name)
end

--- How many characters belong to the job.
---@return number total The number of memberships.
function Job:countMembers()
  return service.countMembers(self.name)
end

--- Every member, from the highest rank down.
---@return table members The list.
function Job:getMembers()
  return service.getMembers(self.name)
end

--- The members in play.
---@return table members The list of { characterId, sessionId, grade, rank, onDuty? }.
function Job:getOnlineMembers()
  return service.getOnlineMembers(self.name)
end

--- Whether a character belongs to the job.
---@param characterId number The character id.
---@return boolean member Whether a membership exists.
function Job:hasMember(characterId)
  return service.hasJob(characterId, self.name)
end

--- The membership of a character.
---@param characterId number The character id.
---@return table? membership The public membership, or nil.
function Job:getMembership(characterId)
  return service.getMembership(characterId, self.name)
end

--- Whether a character may do something in the job right now.
---@param characterId number The character id.
---@param permission string The permission.
---@return boolean allowed Whether the character may.
function Job:hasPermission(characterId, permission)
  return service.hasPermission(characterId, self.name, permission)
end

--- Whether a character is on duty in the job.
---@param characterId number The character id.
---@return boolean onDuty Whether the character is on duty.
function Job:isOnDuty(characterId)
  return service.isOnDuty(characterId, self.name)
end

--- Adds a character at a grade.
---@param characterId number The character id.
---@param gradeName string The grade name.
---@param context? table { performedBy?, enforceHierarchy? }.
---@return boolean hired, string? reason Whether it happened, and why not.
function Job:hire(characterId, gradeName, context)
  return service.hire(characterId, self.name, gradeName, context)
end

--- Removes a character.
---@param characterId number The character id.
---@param context? table { performedBy?, enforceHierarchy? }.
---@return boolean fired, string? reason Whether it happened, and why not.
function Job:fire(characterId, context)
  return service.fire(characterId, self.name, context)
end

--- Moves a member to another grade.
---@param characterId number The character id.
---@param gradeName string The grade name.
---@param context? table { performedBy?, enforceHierarchy? }.
---@return boolean changed, string? reason Whether it happened, and why not.
function Job:setGrade(characterId, gradeName, context)
  return service.setGrade(characterId, self.name, gradeName, context)
end

--- Sets the duty of a member.
---@param characterId number The character id.
---@param onDuty boolean Whether the member takes or leaves the duty.
---@return boolean changed, string? reason Whether it happened, and why not.
function Job:setDuty(characterId, onDuty)
  return service.setDuty(characterId, self.name, onDuty)
end

--- Renames the job.
---@param label string The new label.
---@param performedBy? number The character acting.
---@return boolean changed, string? reason Whether it happened, and why not.
function Job:setLabel(label, performedBy)
  return service.setLabel(self.name, label, performedBy)
end

--- Adds a grade.
---@param grade table { name, label, rank, permissions? }.
---@param performedBy? number The character acting.
---@return boolean created, string? reason Whether it happened, and why not.
function Job:createGrade(grade, performedBy)
  return service.createGrade(self.name, grade, performedBy)
end

--- Changes the label or the rank of a grade.
---@param gradeName string The grade name.
---@param changes table { label?, rank? }.
---@param performedBy? number The character acting.
---@return boolean changed, string? reason Whether it happened, and why not.
function Job:updateGrade(gradeName, changes, performedBy)
  return service.updateGrade(self.name, gradeName, changes, performedBy)
end

--- Removes a grade, moving its members just below.
---@param gradeName string The grade name.
---@param performedBy? number The character acting.
---@return boolean deleted, string? reason, table? demoted Whether it happened, why not, and who moved down.
function Job:deleteGrade(gradeName, performedBy)
  return service.deleteGrade(self.name, gradeName, performedBy)
end

--- Declares a permission the job offers.
---@param permission table|string { name, duty? } or the name.
---@param performedBy? number The character acting.
---@return boolean declared, string? reason Whether it happened, and why not.
function Job:declarePermission(permission, performedBy)
  return service.declarePermission(self.name, permission, performedBy)
end

--- Forgets a declared permission.
---@param name string The permission name.
---@param performedBy? number The character acting.
---@return boolean removed, string? reason Whether it happened, and why not.
function Job:removePermission(name, performedBy)
  return service.removePermission(self.name, name, performedBy)
end

--- Grants a pattern to a grade.
---@param gradeName string The grade name.
---@param pattern string The pattern.
---@param performedBy? number The character acting.
---@return boolean granted, string? reason Whether it happened, and why not.
function Job:grantPermission(gradeName, pattern, performedBy)
  return service.grantPermission(self.name, gradeName, pattern, performedBy)
end

--- Takes a pattern away from a grade.
---@param gradeName string The grade name.
---@param pattern string The pattern.
---@param performedBy? number The character acting.
---@return boolean revoked, string? reason Whether it happened, and why not.
function Job:revokePermission(gradeName, pattern, performedBy)
  return service.revokePermission(self.name, gradeName, pattern, performedBy)
end

local namespace <const> = {}

for key, value in pairs(service) do
  namespace[key] = value
end

--- A handle on a job, registered or not. Reading through it answers
--- copies, acting through it goes back to the core.
---@param name string The job name.
---@return SikuJob job The handle.
function namespace.get(name)
  return Job.new(name)
end

return namespace
