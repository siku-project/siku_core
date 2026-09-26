local DOMAINS <const> = {
  LEGAL = 'legal',
  ILLEGAL = 'illegal',
}

local CLIENT_EVENT <const> = 'siku:client:jobsUpdated'

local CALLBACKS <const> = {
  MY_JOBS = 'siku:callback:myJobs',
  COUNTS = 'siku:callback:jobCounts',
  DEFINITION = 'siku:callback:jobDefinition',
  MEMBERS = 'siku:callback:jobMembers',
}

internal.DOMAINS = DOMAINS
internal.CLIENT_EVENT = CLIENT_EVENT
internal.CALLBACKS = CALLBACKS

--- Finds a membership by job name in a list the engine published.
---@param memberships table The public memberships.
---@param jobName string The job name.
---@return table? membership The membership, or nil.
function internal.findMembership(memberships, jobName)
  for index = 1, #memberships do
    if memberships[index].job == jobName then
      return memberships[index]
    end
  end

  return nil
end

return {
  DOMAINS = DOMAINS,
}
