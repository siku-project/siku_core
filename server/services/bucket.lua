Siku.bucket = {}

local activeBuckets = {}
local playerBuckets = {}
local entityBuckets = {}

local DEFAULT_BUCKET <const> = 0

local VALID_LOCKDOWN_MODES <const> = {
  strict = true,
  relaxed = true,
  inactive = true,
}

--- Register a bucket as active with its configuration.
---@param bucketId number The bucket ID.
---@param owner string The resource or system that created this bucket.
---@param lockdown string The lockdown mode (strict, relaxed, inactive).
---@param population boolean Whether population is enabled.
local function registerBucket(bucketId, owner, lockdown, population)
  activeBuckets[bucketId] = {
    id = bucketId,
    owner = owner,
    lockdown = lockdown,
    population = population,
    players = {},
    entities = {},
    createdAt = os.time(),
  }
end

--- Check if a bucket exists in the tracking.
---@param bucketId number The bucket ID.
---@return boolean exists Whether the bucket is tracked.
function Siku.bucket.exists(bucketId)
  return activeBuckets[bucketId] ~= nil
end

--- Create a routing bucket with a specific ID and optional configuration.
---@param bucketId number The bucket ID to create.
---@param lockdown? string The entity lockdown mode: 'strict', 'relaxed', or 'inactive'. Default: 'strict'.
---@param population? boolean Whether to enable NPC population in this bucket. Default: false.
---@return number|nil bucketId The created bucket ID or nil on failure.
function Siku.bucket.create(bucketId, lockdown, population)
  if type(bucketId) ~= 'number' then
    Siku.print.error(('Bucket ID must be a number, got %s'):format(type(bucketId)))
    return nil
  end

  if bucketId == DEFAULT_BUCKET then
    Siku.print.error('Cannot create bucket 0 — reserved as default world')
    return nil
  end

  if activeBuckets[bucketId] then
    Siku.print.error(('Bucket %d already exists (owner: %s)'):format(bucketId, activeBuckets[bucketId].owner))
    return nil
  end

  local lock <const> = lockdown or 'strict'

  if not VALID_LOCKDOWN_MODES[lock] then
    Siku.print.error(('Invalid lockdown mode: \'%s\' — expected strict, relaxed, or inactive'):format(lock))
    return nil
  end

  local pop <const> = population ~= nil and population or false
  local owner <const> = GetInvokingResource() or Siku.name

  SetRoutingBucketEntityLockdownMode(bucketId, lock)
  SetRoutingBucketPopulationEnabled(bucketId, pop)

  registerBucket(bucketId, owner, lock, pop)

  Siku.print.info(('Bucket %d created (lockdown: %s, population: %s, owner: %s)'):format(bucketId, lock, tostring(pop), owner))

  return bucketId
end

--- Destroy a routing bucket and move all players and entities back to the default bucket.
---@param bucketId number The bucket ID to destroy.
---@return boolean success Whether the bucket was destroyed.
function Siku.bucket.destroy(bucketId)
  if bucketId == DEFAULT_BUCKET then return false end

  local bucket <const> = activeBuckets[bucketId]
  if not bucket then return false end

  for sessionId in pairs(bucket.players) do
    SetPlayerRoutingBucket(tostring(sessionId), DEFAULT_BUCKET)
    playerBuckets[sessionId] = nil
  end

  for entityId in pairs(bucket.entities) do
    SetEntityRoutingBucket(entityId, DEFAULT_BUCKET)
    entityBuckets[entityId] = nil
  end

  SetRoutingBucketEntityLockdownMode(bucketId, 'inactive')
  SetRoutingBucketPopulationEnabled(bucketId, true)

  activeBuckets[bucketId] = nil

  Siku.print.info(('Bucket %d destroyed'):format(bucketId))

  return true
end

--- Set a player into a specific routing bucket.
---@param sessionId number The player's server ID.
---@param bucketId number The target bucket ID.
---@return boolean success Whether the player was moved.
function Siku.bucket.setPlayer(sessionId, bucketId)
  if not GetPlayerName(tostring(sessionId)) then return false end

  if playerBuckets[sessionId] == bucketId then return true end

  local previousBucket <const> = playerBuckets[sessionId]

  if previousBucket and activeBuckets[previousBucket] then
    activeBuckets[previousBucket].players[sessionId] = nil
  end

  SetPlayerRoutingBucket(tostring(sessionId), bucketId)
  playerBuckets[sessionId] = bucketId

  if activeBuckets[bucketId] then
    activeBuckets[bucketId].players[sessionId] = true
  end

  return true
end

--- Move a player back to the default bucket (world 0).
---@param sessionId number The player's server ID.
---@return boolean success Whether the player was moved.
function Siku.bucket.resetPlayer(sessionId)
  return Siku.bucket.setPlayer(sessionId, DEFAULT_BUCKET)
end

--- Get the current bucket ID of a player.
---@param sessionId number The player's server ID.
---@return number bucketId The player's current bucket ID.
function Siku.bucket.getPlayer(sessionId)
  return playerBuckets[sessionId] or GetPlayerRoutingBucket(tostring(sessionId))
end

--- Set an entity into a specific routing bucket.
---@param entity number The entity handle.
---@param bucketId number The target bucket ID.
---@return boolean success Whether the entity was moved.
function Siku.bucket.setEntity(entity, bucketId)
  if not DoesEntityExist(entity) then return false end

  if entityBuckets[entity] == bucketId then return true end

  local previousBucket <const> = entityBuckets[entity]

  if previousBucket and activeBuckets[previousBucket] then
    activeBuckets[previousBucket].entities[entity] = nil
  end

  SetEntityRoutingBucket(entity, bucketId)
  entityBuckets[entity] = bucketId

  if activeBuckets[bucketId] then
    activeBuckets[bucketId].entities[entity] = true
  end

  return true
end

--- Move an entity back to the default bucket (world 0).
---@param entity number The entity handle.
---@return boolean success Whether the entity was moved.
function Siku.bucket.resetEntity(entity)
  return Siku.bucket.setEntity(entity, DEFAULT_BUCKET)
end

--- Get the current bucket ID of an entity.
---@param entity number The entity handle.
---@return number bucketId The entity's current bucket ID.
function Siku.bucket.getEntity(entity)
  return entityBuckets[entity] or GetEntityRoutingBucket(entity)
end

--- Create a private instance for a player using their session ID as bucket ID.
--- Automatically creates a new bucket with strict lockdown and no population,
--- then moves the player into it.
---@param sessionId number The player's server ID.
---@return number|nil bucketId The created bucket ID or nil on failure.
function Siku.bucket.createPlayerInstance(sessionId)
  if not GetPlayerName(tostring(sessionId)) then
    Siku.print.error(('Cannot create instance — player %s does not exist'):format(tostring(sessionId)))
    return nil
  end

  if Siku.bucket.isPlayerInstanced(sessionId) then
    Siku.print.error(('Cannot create instance — player %d already in bucket %d'):format(sessionId, playerBuckets[sessionId]))
    return nil
  end

  local bucketId <const> = Siku.bucket.create(sessionId, 'strict', false)
  if not bucketId then return nil end

  Siku.bucket.setPlayer(sessionId, bucketId)
  return bucketId
end

--- Release a player from their private instance and destroy the bucket if empty.
---@param sessionId number The player's server ID.
---@return boolean success Whether the player was released.
function Siku.bucket.releasePlayerInstance(sessionId)
  local bucketId <const> = playerBuckets[sessionId]

  if not bucketId or bucketId == DEFAULT_BUCKET then return false end

  Siku.bucket.resetPlayer(sessionId)

  local bucket <const> = activeBuckets[bucketId]
  if bucket and not next(bucket.players) and not next(bucket.entities) then
    Siku.bucket.destroy(bucketId)
  end

  return true
end

--- Check if a player is in a private instance (not in the default bucket).
---@param sessionId number The player's server ID.
---@return boolean instanced Whether the player is in an instance.
function Siku.bucket.isPlayerInstanced(sessionId)
  local bucketId <const> = playerBuckets[sessionId]
  return bucketId ~= nil and bucketId ~= DEFAULT_BUCKET
end

--- Get the info of a specific bucket (read-only copy).
---@param bucketId number The bucket ID.
---@return table|nil info The bucket info or nil if not found.
function Siku.bucket.getInfo(bucketId)
  local bucket <const> = activeBuckets[bucketId]
  if not bucket then return nil end

  return Siku.table.freeze({
    id = bucket.id,
    owner = bucket.owner,
    lockdown = bucket.lockdown,
    population = bucket.population,
    playerCount = Siku.bucket.getPlayerCount(bucketId),
    createdAt = bucket.createdAt,
  })
end

--- Get all active bucket IDs.
---@return table bucketIds A list of active bucket IDs.
function Siku.bucket.getAll()
  local result <const> = {}
  for id in pairs(activeBuckets) do
    result[#result + 1] = id
  end
  return result
end

--- Get how many active buckets exist.
---@return number count The number of active buckets.
function Siku.bucket.getCount()
  local count = 0
  for _ in pairs(activeBuckets) do
    count = count + 1
  end
  return count
end

--- Get all players in a specific bucket.
---@param bucketId number The bucket ID.
---@return table sessionIds A list of session IDs in this bucket.
function Siku.bucket.getPlayers(bucketId)
  local bucket <const> = activeBuckets[bucketId]
  if not bucket then return {} end

  local result <const> = {}
  for sessionId in pairs(bucket.players) do
    result[#result + 1] = sessionId
  end
  return result
end

--- Get how many players are in a specific bucket.
---@param bucketId number The bucket ID.
---@return number count The player count.
function Siku.bucket.getPlayerCount(bucketId)
  local bucket <const> = activeBuckets[bucketId]
  if not bucket then return 0 end

  local count = 0
  for _ in pairs(bucket.players) do
    count = count + 1
  end
  return count
end

--- Clean up player tracking when they disconnect.
---@param sessionId number The player's server ID.
local function onPlayerDropped(sessionId)
  local bucketId <const> = playerBuckets[sessionId]
  if not bucketId then return end

  if activeBuckets[bucketId] then
    activeBuckets[bucketId].players[sessionId] = nil

    if bucketId ~= DEFAULT_BUCKET and not next(activeBuckets[bucketId].players) and not next(activeBuckets[bucketId].entities) then
      Siku.bucket.destroy(bucketId)
    end
  end

  playerBuckets[sessionId] = nil
end

AddEventHandler('playerDropped', function()
  onPlayerDropped(source)
end)
