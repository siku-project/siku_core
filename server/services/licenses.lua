Siku.licenses = {}

local STATE_VALID <const> = 'valid'
local STATE_SUSPENDED <const> = 'suspended'
local STATE_REVOKED <const> = 'revoked'
local STATE_EXPIRED <const> = 'expired'
local EVENT_FORMAT <const> = 'siku:licenses:%s'
local CLIENT_EVENT <const> = 'siku:client:licensesUpdated'
local NAME_PATTERN <const> = '^[%l][%l%d_]*$'
local NAME_MAX_LENGTH <const> = 50
local LABEL_MAX_LENGTH <const> = 100
local DATE_FORMAT <const> = '%Y-%m-%d %H:%M:%S'
local DATE_PATTERN <const> = '^(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d):?(%d?%d?)$'
local MILLISECONDS_THRESHOLD <const> = 100000000000
local SECONDS_PER_DAY <const> = 86400
local READY_POLL_MS <const> = 100
local READY_TIMEOUT_MS <const> = 30000

local state <const> = {
  ready = false,
  byName = {},
  byId = {},
  holdings = {},
  sessions = {},
  announced = {},
}

_SikuInternal.licenses = {
  state = state,
  STATE_VALID = STATE_VALID,
  STATE_SUSPENDED = STATE_SUSPENDED,
  STATE_REVOKED = STATE_REVOKED,
  STATE_EXPIRED = STATE_EXPIRED,
  NAME_PATTERN = NAME_PATTERN,
  NAME_MAX_LENGTH = NAME_MAX_LENGTH,
  LABEL_MAX_LENGTH = LABEL_MAX_LENGTH,
  SECONDS_PER_DAY = SECONDS_PER_DAY,
  CLIENT_EVENT = CLIENT_EVENT,
}

local internal <const> = _SikuInternal.licenses

function internal.emit(name, ...)
  TriggerEvent(EVENT_FORMAT:format(name), ...)
end

function internal.waitReady()
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

function internal.now()
  return os.time()
end

function internal.toInteger(value)
  if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end

  return math.tointeger(value)
end

function internal.toTimestamp(value)
  if value == nil then
    return nil, true
  end

  if type(value) == 'number' then
    local seconds <const> = value >= MILLISECONDS_THRESHOLD and value / 1000 or value
    local whole <const> = math.tointeger(math.floor(seconds))

    if not whole or whole <= 0 then
      return nil, false
    end

    return whole, true
  end

  if type(value) == 'string' then
    local year <const>, month <const>, day <const>, hour <const>, minute <const>, second <const> = value:match(DATE_PATTERN)

    if not year then
      return nil, false
    end

    local timestamp <const> = os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(minute),
      sec = tonumber(second) or 0,
    })

    if not timestamp then
      return nil, false
    end

    return timestamp, true
  end

  return nil, false
end

function internal.formatDate(timestamp)
  if type(timestamp) ~= 'number' then
    return nil
  end

  return os.date(DATE_FORMAT, timestamp)
end

function internal.isValidName(name)
  return type(name) == 'string' and #name <= NAME_MAX_LENGTH and name:match(NAME_PATTERN) ~= nil
end

function internal.isValidState(name)
  return name == STATE_VALID or name == STATE_SUSPENDED or name == STATE_REVOKED
end

function internal.getLicense(licenseName)
  if type(licenseName) ~= 'string' then
    return nil
  end

  return state.byName[licenseName]
end

function internal.checkContext(context)
  if context == nil then
    return true
  end

  if type(context) ~= 'table' then
    return false
  end

  if context.performedBy ~= nil and not internal.toInteger(context.performedBy) then
    return false
  end

  if context.reason ~= nil and type(context.reason) ~= 'string' then
    return false
  end

  return true
end

function internal.performerOf(context)
  return type(context) == 'table' and internal.toInteger(context.performedBy) or nil
end

function internal.reasonOf(context)
  return type(context) == 'table' and context.reason or nil
end

function internal.readState(entry)
  local now <const> = internal.now()

  if entry.state == STATE_REVOKED then
    return STATE_REVOKED
  end

  if entry.state == STATE_SUSPENDED and (not entry.suspendedUntil or entry.suspendedUntil > now) then
    return STATE_SUSPENDED
  end

  if entry.expiresAt and entry.expiresAt <= now then
    return STATE_EXPIRED
  end

  return STATE_VALID
end

function internal.pointsOf(license, entry)
  if not license.maxPoints then
    return nil
  end

  local points <const> = internal.toInteger(entry.points) or license.maxPoints

  return math.max(0, math.min(points, license.maxPoints))
end

function internal.publicLicense(license)
  return {
    id = license.id,
    name = license.name,
    label = license.label,
    group = license.group,
    maxPoints = license.maxPoints,
    validity = license.validityDays,
    resource = license.resource,
    active = license.active,
  }
end

function internal.publicHolding(license, entry)
  return {
    license = license.name,
    label = license.label,
    group = license.group,
    state = internal.readState(entry),
    points = internal.pointsOf(license, entry),
    maxPoints = license.maxPoints,
    issuedAt = internal.formatDate(entry.issuedAt),
    expiresAt = internal.formatDate(entry.expiresAt),
    suspendedUntil = entry.state == STATE_SUSPENDED and internal.formatDate(entry.suspendedUntil) or nil,
    issuedBy = entry.issuedBy,
    metadata = Siku.table.deepClone(entry.metadata or {}),
  }
end

function internal.sortHoldings(holdings)
  table.sort(holdings, function(a, b)
    local groupA <const> = a.group or ''
    local groupB <const> = b.group or ''

    if groupA ~= groupB then
      return groupA < groupB
    end

    return a.label < b.label
  end)

  return holdings
end

function internal.audit(action, licenseId, targetCharacterId, performedBy, details)
  if not LicensesConfig.audit then
    return
  end

  MySQL.insert.await(
    'INSERT INTO license_audit_log (action, license_id, target_character_id, performed_by, details) VALUES (?, ?, ?, ?, ?)',
    { action, licenseId, targetCharacterId, performedBy, details or '' }
  )
end

function internal.push(characterId)
  local sessionId <const> = state.sessions[characterId]

  if not sessionId then
    return
  end

  TriggerClientEvent(CLIENT_EVENT, sessionId, Siku.licenses.getHoldings(characterId))
end

function Siku.licenses.exists(licenseName)
  return internal.getLicense(licenseName) ~= nil
end

function Siku.licenses.isActive(licenseName)
  local license <const> = internal.getLicense(licenseName)

  return license ~= nil and license.active
end

function Siku.licenses.getDefinition(licenseName)
  local license <const> = internal.getLicense(licenseName)

  if not license then
    return nil
  end

  return internal.publicLicense(license)
end

function Siku.licenses.getAll(group)
  local definitions <const> = {}

  for _, license in pairs(state.byName) do
    if group == nil or license.group == group then
      definitions[#definitions + 1] = internal.publicLicense(license)
    end
  end

  table.sort(definitions, function(a, b)
    return a.label < b.label
  end)

  return definitions
end

function Siku.licenses.getHoldings(characterId)
  local holdings <const> = {}

  for licenseName, entry in pairs(internal.entriesOf(characterId)) do
    local license <const> = state.byName[licenseName]

    if license then
      holdings[#holdings + 1] = internal.publicHolding(license, entry)
    end
  end

  return internal.sortHoldings(holdings)
end

function Siku.licenses.getHolding(characterId, licenseName)
  local license <const> = internal.getLicense(licenseName)
  local entry <const> = license and internal.entryOf(characterId, license) or nil

  if not entry then
    return nil
  end

  return internal.publicHolding(license, entry)
end

function Siku.licenses.has(characterId, licenseName)
  local license <const> = internal.getLicense(licenseName)

  return license ~= nil and internal.entryOf(characterId, license) ~= nil
end

function Siku.licenses.isValid(characterId, licenseName)
  local license <const> = internal.getLicense(licenseName)
  local entry <const> = license and internal.entryOf(characterId, license) or nil

  return entry ~= nil and internal.readState(entry) == STATE_VALID
end

function Siku.licenses.getPoints(characterId, licenseName)
  local license <const> = internal.getLicense(licenseName)
  local entry <const> = license and internal.entryOf(characterId, license) or nil

  if not entry then
    return nil
  end

  return internal.pointsOf(license, entry)
end
