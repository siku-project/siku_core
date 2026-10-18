local KEY_MAX <const> = 128
local ENTITY_FIELDS <const> = 8
local ENTITY_FIELD_KEY <const> = 32
local ENTITY_TYPE <const> = 32
local ENTITY_ID <const> = 64
local ENTITY_ROLE <const> = 32
local ENTITY_LABEL <const> = 128
local ENTITY_RESERVED <const> = { type = true, id = true, session = true, role = true, label = true }
local VECTORS <const> = { vector2 = true, vector3 = true, vector4 = true }

local settings <const> = internal.settings

local function clamp(value, max)
  if #value > max then
    return value:sub(1, max)
  end

  return value
end

local function isSequence(value)
  local n <const> = #value

  if n == 0 then
    return next(value) == nil
  end

  return next(value, n) == nil
end

local function scalar(value)
  local kind <const> = type(value)

  if kind == 'string' then
    return clamp(value, settings.string)
  end

  if kind == 'number' or kind == 'boolean' then
    return value
  end

  if value == nil then
    return nil
  end

  return clamp(tostring(value), settings.string)
end

local sanitize

local function sanitizeList(value, depth)
  local out <const> = {}
  local n <const> = math.min(#value, settings.list)

  for i = 1, n do
    out[i] = sanitize(value[i], depth + 1)
  end

  if #value > settings.list then
    out[n + 1] = ('… %d more'):format(#value - settings.list)
  end

  return out
end

local function sanitizeMap(value, depth)
  local out <const> = {}
  local count = 0

  for key, entry in pairs(value) do
    count = count + 1

    if count > settings.keys then
      out['…'] = 'truncated'
      break
    end

    out[clamp(tostring(key), KEY_MAX)] = sanitize(entry, depth + 1)
  end

  return out
end

sanitize = function(value, depth)
  local kind <const> = type(value)

  if kind == 'string' then
    return clamp(value, settings.string)
  end

  if kind == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then
      return tostring(value)
    end

    return value
  end

  if kind == 'boolean' or value == nil then
    return value
  end

  if VECTORS[kind] then
    return { x = value.x, y = value.y, z = value.z, w = value.w }
  end

  if kind ~= 'table' then
    return tostring(value)
  end

  if depth >= settings.depth then
    return '[…]'
  end

  local meta <const> = getmetatable(value)

  if meta and meta.__tostring then
    return tostring(value)
  end

  if isSequence(value) then
    return sanitizeList(value, depth)
  end

  return sanitizeMap(value, depth)
end

local function sanitizeEntity(entity)
  if type(entity) ~= 'table' or type(entity.type) ~= 'string' or entity.type == '' then
    return nil
  end

  local id <const> = entity.id == nil and entity.session or entity.id

  if type(id) ~= 'string' and type(id) ~= 'number' then
    return nil
  end

  local out <const> = {
    type = clamp(entity.type:lower(), ENTITY_TYPE),
    id = type(id) == 'number' and id or clamp(id, ENTITY_ID),
    role = type(entity.role) == 'string' and clamp(entity.role, ENTITY_ROLE) or nil,
    label = type(entity.label) == 'string' and clamp(entity.label, ENTITY_LABEL) or nil,
  }
  local count = 0

  for key, value in pairs(entity) do
    if not ENTITY_RESERVED[key] and (type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean') then
      count = count + 1

      if count > ENTITY_FIELDS then
        break
      end

      out[clamp(tostring(key), ENTITY_FIELD_KEY)] = scalar(value)
    end
  end

  return out
end

local function sanitizeEntities(entities)
  if type(entities) ~= 'table' then
    return nil
  end

  local out <const> = {}

  for i = 1, math.min(#entities, settings.entities) do
    out[#out + 1] = sanitizeEntity(entities[i])
  end

  if #out == 0 then
    return nil
  end

  return out
end

local function sanitizeAttributes(attributes)
  if type(attributes) ~= 'table' then
    return nil
  end

  local out <const> = {}
  local count = 0

  for key, value in pairs(attributes) do
    count = count + 1

    if count > settings.maxAttributes then
      break
    end

    out[clamp(tostring(key), KEY_MAX)] = scalar(value)
  end

  return out
end

internal.clamp = clamp
internal.sanitize = sanitize
internal.sanitizeEntities = sanitizeEntities
internal.sanitizeAttributes = sanitizeAttributes

return {}
