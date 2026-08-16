---@type table<number, number>
local pending = {}
local pendingCount = 0

--- Removes pending connections older than the configured timeout.
---@return nil
local function prunePending()
  local now <const> = os.time()
  for tempId, startedAt in pairs(pending) do
    if now - startedAt > ConnectionConfig.pendingTimeout then
      pending[tempId] = nil
      pendingCount = pendingCount - 1
    end
  end
end

--- Releases the pending slot held by a connection.
---@param tempId number The temporary server ID of the connection.
---@return nil
local function releasePending(tempId)
  if pending[tempId] then
    pending[tempId] = nil
    pendingCount = pendingCount - 1
  end
end

--- Rejects a connecting player when the server is full, and holds a
--- pending slot for them otherwise.
---@param name string The connecting player name.
---@param _ fun(reason: string) Unused legacy kick reason setter.
---@param deferrals table The connection deferral controller.
---@return nil
local function handlePlayerConnecting(name, _, deferrals)
  if not ConnectionConfig.enforceMaxClients then
    return
  end

  local tempId <const> = source
  prunePending()

  local maxClients <const> = GetConvarInt('sv_maxclients', 48)
  local occupancy <const> = GetNumPlayerIndices() + pendingCount

  if occupancy >= maxClients then
    Siku.print.warn(('Connection refused for %s: server full (%d/%d)'):format(name, occupancy, maxClients))
    deferrals.defer()
    Wait(0)
    deferrals.done(T('connection_server_full', maxClients))
    return
  end

  if not pending[tempId] then
    pending[tempId] = os.time()
    pendingCount = pendingCount + 1
  end
end

--- Releases the pending slot of a player who finished joining.
---@param oldId string The temporary server ID the player connected with.
---@return nil
local function handlePlayerJoining(oldId)
  local tempId <const> = tonumber(oldId)
  if tempId then
    releasePending(tempId)
  end
end

--- Releases the pending slot of a connection that dropped while loading.
---@return nil
local function handlePlayerDropped()
  releasePending(source)
end

AddEventHandler('playerConnecting', handlePlayerConnecting)
AddEventHandler('playerJoining', handlePlayerJoining)
AddEventHandler('playerDropped', handlePlayerDropped)
