local internal <const> = _SikuInternal.licenses
local state <const> = internal.state

local STATE_VALID <const> = internal.STATE_VALID
local STATE_SUSPENDED <const> = internal.STATE_SUSPENDED
local STATE_REVOKED <const> = internal.STATE_REVOKED
local STATE_EXPIRED <const> = internal.STATE_EXPIRED
local EVENT_ISSUED <const> = 'issued'
local EVENT_SUSPENDED <const> = 'suspended'
local EVENT_LIFTED <const> = 'lifted'
local EVENT_REVOKED <const> = 'revoked'
local EVENT_WITHDRAWN <const> = 'withdrawn'
local EVENT_METADATA_CHANGED <const> = 'metadataChanged'
local AUDIT_REISSUED <const> = 'reissued'
local AUDIT_SUSPENSION_ENDED <const> = 'suspension_ended'
local AUDIT_EXPIRY_SET <const> = 'expiry_set'
local AUDIT_METADATA_SET <const> = 'metadata_set'

local SELECT_HOLDINGS <const> = [[
  SELECT license_id, state, points, UNIX_TIMESTAMP(issued_at) AS issued_at,
         UNIX_TIMESTAMP(expires_at) AS expires_at, UNIX_TIMESTAMP(suspended_until) AS suspended_until,
         issued_by, metadata
  FROM license_holdings WHERE character_id = ?
]]

local SELECT_HOLDERS <const> = [[
  SELECT h.character_id, h.state, h.points, UNIX_TIMESTAMP(h.issued_at) AS issued_at,
         UNIX_TIMESTAMP(h.expires_at) AS expires_at, UNIX_TIMESTAMP(h.suspended_until) AS suspended_until,
         h.issued_by, h.metadata, c.first_name, c.last_name
  FROM license_holdings h JOIN characters c ON c.id = h.character_id
  WHERE h.license_id = ?
]]

local function decodeMetadata(raw)
  if type(raw) ~= 'string' or raw == '' then
    return {}
  end

  local ok <const>, decoded <const> = pcall(json.decode, raw)

  return ok and type(decoded) == 'table' and decoded or {}
end

local function entryFromRow(row)
  return {
    licenseId = row.license_id,
    state = internal.isValidState(row.state) and row.state or STATE_VALID,
    points = internal.toInteger(row.points),
    issuedAt = internal.toInteger(row.issued_at),
    expiresAt = internal.toInteger(row.expires_at),
    suspendedUntil = internal.toInteger(row.suspended_until),
    issuedBy = internal.toInteger(row.issued_by),
    metadata = decodeMetadata(row.metadata),
  }
end

local function settleSuspension(characterId, license, entry)
  if entry.state ~= STATE_SUSPENDED or not entry.suspendedUntil or entry.suspendedUntil > internal.now() then
    return false
  end

  MySQL.update.await(
    'UPDATE license_holdings SET state = ?, suspended_until = NULL WHERE character_id = ? AND license_id = ?',
    { STATE_VALID, characterId, license.id }
  )

  entry.state = STATE_VALID
  entry.suspendedUntil = nil

  internal.audit(AUDIT_SUSPENSION_ENDED, license.id, characterId, nil, nil)
  internal.emit(EVENT_LIFTED, characterId, license.name, state.sessions[characterId])

  return true
end

internal.settleSuspension = settleSuspension

local function loadEntries(characterId)
  local rows <const> = MySQL.query.await(SELECT_HOLDINGS, { characterId })
  local entries <const> = {}

  for index = 1, #rows do
    local row <const> = rows[index]
    local license <const> = state.byId[row.license_id]

    if license then
      local entry <const> = entryFromRow(row)

      settleSuspension(characterId, license, entry)
      entries[license.name] = entry
    else
      Siku.print.warn(('Character %d holds unknown license #%d'):format(characterId, row.license_id))
    end
  end

  return entries
end

function internal.entriesOf(characterId)
  if type(characterId) ~= 'number' then
    return {}
  end

  return state.holdings[characterId] or loadEntries(characterId)
end

function internal.entryOf(characterId, license)
  return internal.entriesOf(characterId)[license.name]
end

local function characterExists(characterId)
  if state.holdings[characterId] or Siku.cache.getCharacter(characterId) then
    return true
  end

  return MySQL.scalar.await('SELECT id FROM characters WHERE id = ?', { characterId }) ~= nil
end

local function resolve(characterId, licenseName)
  local license <const> = internal.getLicense(licenseName)

  if not license then
    return nil, nil, 'unknown_license'
  end

  if not internal.toInteger(characterId) then
    return nil, nil, 'unknown_character'
  end

  local entry <const> = internal.entryOf(characterId, license)

  if not entry then
    return license, nil, 'not_held'
  end

  return license, entry, nil
end

local function cacheEntry(characterId, license, entry)
  local cached <const> = state.holdings[characterId]

  if cached then
    cached[license.name] = entry
  end

  if state.announced[characterId] then
    state.announced[characterId][license.name] = nil
  end

  internal.push(characterId)
end

local function forgetAnnounced(characterId, license)
  if state.announced[characterId] then
    state.announced[characterId][license.name] = nil
  end
end

local function expiryFrom(options, license)
  if type(options) ~= 'table' then
    return license.validityDays and internal.now() + license.validityDays * internal.SECONDS_PER_DAY or nil, true
  end

  if options.expiresAt ~= nil then
    local expiresAt <const>, ok <const> = internal.toTimestamp(options.expiresAt)

    if not ok or not expiresAt or expiresAt <= internal.now() then
      return nil, false
    end

    return expiresAt, true
  end

  if options.validity ~= nil then
    local days <const> = internal.toInteger(options.validity)

    if not days or days <= 0 then
      return nil, false
    end

    return internal.now() + days * internal.SECONDS_PER_DAY, true
  end

  return license.validityDays and internal.now() + license.validityDays * internal.SECONDS_PER_DAY or nil, true
end

function Siku.licenses.issue(characterId, licenseName, options)
  local license <const> = internal.getLicense(licenseName)

  if not license then
    return false, 'unknown_license'
  end

  if not internal.waitReady() then
    return false, 'not_ready'
  end

  if options ~= nil and type(options) ~= 'table' then
    return false, 'invalid_options'
  end

  if not internal.checkContext(options) then
    return false, 'invalid_context'
  end

  if type(options) == 'table' and options.metadata ~= nil and type(options.metadata) ~= 'table' then
    return false, 'invalid_metadata'
  end

  if not internal.toInteger(characterId) or not characterExists(characterId) then
    return false, 'unknown_character'
  end

  local existing <const> = internal.entryOf(characterId, license)
  local reissue = false

  if existing then
    local current <const> = internal.readState(existing)

    if current == STATE_VALID or current == STATE_SUSPENDED then
      return false, 'already_held'
    end

    reissue = true
  end

  local expiresAt <const>, dateOk <const> = expiryFrom(options, license)

  if not dateOk then
    return false, 'invalid_date'
  end

  local performedBy <const> = internal.performerOf(options)
  local metadata <const> = type(options) == 'table' and options.metadata and Siku.table.deepClone(options.metadata) or {}
  local encoded <const> = json.encode(metadata)

  MySQL.update.await(
    [[
      INSERT INTO license_holdings (character_id, license_id, state, points, issued_at, expires_at, suspended_until, issued_by, metadata)
      VALUES (?, ?, ?, ?, NOW(), FROM_UNIXTIME(?), NULL, ?, ?)
      ON DUPLICATE KEY UPDATE state = VALUES(state), points = VALUES(points), issued_at = VALUES(issued_at),
        expires_at = VALUES(expires_at), suspended_until = NULL, issued_by = VALUES(issued_by), metadata = VALUES(metadata)
    ]],
    { characterId, license.id, STATE_VALID, license.maxPoints, expiresAt, performedBy, encoded }
  )

  local entry <const> = {
    licenseId = license.id,
    state = STATE_VALID,
    points = license.maxPoints,
    issuedAt = internal.now(),
    expiresAt = expiresAt,
    suspendedUntil = nil,
    issuedBy = performedBy,
    metadata = metadata,
  }

  cacheEntry(characterId, license, entry)

  local details <const> = ('expires=%s reason=%s'):format(internal.formatDate(expiresAt) or 'never', internal.reasonOf(options) or '')

  internal.audit(reissue and AUDIT_REISSUED or EVENT_ISSUED, license.id, characterId, performedBy, details)
  internal.emit(EVENT_ISSUED, characterId, license.name, internal.publicHolding(license, entry), state.sessions[characterId])

  return true, nil
end

function Siku.licenses.suspend(characterId, licenseName, options)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName)

  if not entry then
    return false, reason
  end

  if options ~= nil and type(options) ~= 'table' then
    return false, 'invalid_options'
  end

  if not internal.checkContext(options) then
    return false, 'invalid_context'
  end

  local current <const> = internal.readState(entry)

  if current == STATE_REVOKED then
    return false, 'revoked'
  end

  if current == STATE_EXPIRED then
    return false, 'expired'
  end

  local endsAt <const>, dateOk <const> = internal.toTimestamp(type(options) == 'table' and options.endsAt or nil)

  if not dateOk or (endsAt and endsAt <= internal.now()) then
    return false, 'invalid_date'
  end

  MySQL.update.await(
    'UPDATE license_holdings SET state = ?, suspended_until = FROM_UNIXTIME(?) WHERE character_id = ? AND license_id = ?',
    { STATE_SUSPENDED, endsAt, characterId, license.id }
  )

  entry.state = STATE_SUSPENDED
  entry.suspendedUntil = endsAt

  internal.push(characterId)

  local performedBy <const> = internal.performerOf(options)
  local details <const> = ('until=%s reason=%s'):format(internal.formatDate(endsAt) or 'indefinite', internal.reasonOf(options) or '')

  internal.audit(EVENT_SUSPENDED, license.id, characterId, performedBy, details)
  internal.emit(EVENT_SUSPENDED, characterId, license.name, internal.formatDate(endsAt), state.sessions[characterId])

  return true, nil
end

function Siku.licenses.lift(characterId, licenseName, context)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName)

  if not entry then
    return false, reason
  end

  if not internal.checkContext(context) then
    return false, 'invalid_context'
  end

  if entry.state ~= STATE_SUSPENDED then
    return false, 'not_suspended'
  end

  if settleSuspension(characterId, license, entry) then
    internal.push(characterId)
    return true, nil
  end

  MySQL.update.await(
    'UPDATE license_holdings SET state = ?, suspended_until = NULL WHERE character_id = ? AND license_id = ?',
    { STATE_VALID, characterId, license.id }
  )

  entry.state = STATE_VALID
  entry.suspendedUntil = nil

  internal.push(characterId)
  internal.audit(EVENT_LIFTED, license.id, characterId, internal.performerOf(context), internal.reasonOf(context))
  internal.emit(EVENT_LIFTED, characterId, license.name, state.sessions[characterId])

  return true, nil
end

function Siku.licenses.revoke(characterId, licenseName, context)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName)

  if not entry then
    return false, reason
  end

  if not internal.checkContext(context) then
    return false, 'invalid_context'
  end

  if entry.state == STATE_REVOKED then
    return false, 'revoked'
  end

  MySQL.update.await(
    'UPDATE license_holdings SET state = ?, suspended_until = NULL WHERE character_id = ? AND license_id = ?',
    { STATE_REVOKED, characterId, license.id }
  )

  entry.state = STATE_REVOKED
  entry.suspendedUntil = nil

  forgetAnnounced(characterId, license)
  internal.push(characterId)
  internal.audit(EVENT_REVOKED, license.id, characterId, internal.performerOf(context), internal.reasonOf(context))
  internal.emit(EVENT_REVOKED, characterId, license.name, state.sessions[characterId])

  return true, nil
end

function Siku.licenses.withdraw(characterId, licenseName, context)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName)

  if not entry then
    return false, reason
  end

  if not internal.checkContext(context) then
    return false, 'invalid_context'
  end

  MySQL.update.await('DELETE FROM license_holdings WHERE character_id = ? AND license_id = ?', { characterId, license.id })

  local cached <const> = state.holdings[characterId]

  if cached then
    cached[license.name] = nil
  end

  forgetAnnounced(characterId, license)
  internal.push(characterId)
  internal.audit(EVENT_WITHDRAWN, license.id, characterId, internal.performerOf(context), internal.reasonOf(context))
  internal.emit(EVENT_WITHDRAWN, characterId, license.name, state.sessions[characterId])

  return true, nil
end

function Siku.licenses.setMetadata(characterId, licenseName, metadata)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName)

  if not entry then
    return false, reason
  end

  if type(metadata) ~= 'table' then
    return false, 'invalid_metadata'
  end

  local copy <const> = Siku.table.deepClone(metadata)

  MySQL.update.await(
    'UPDATE license_holdings SET metadata = ? WHERE character_id = ? AND license_id = ?',
    { json.encode(copy), characterId, license.id }
  )

  entry.metadata = copy

  internal.push(characterId)
  internal.audit(AUDIT_METADATA_SET, license.id, characterId, nil, nil)
  internal.emit(EVENT_METADATA_CHANGED, characterId, license.name, Siku.table.deepClone(copy))

  return true, nil
end

function Siku.licenses.setExpiry(characterId, licenseName, expiresAt, context)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName)

  if not entry then
    return false, reason
  end

  if not internal.checkContext(context) then
    return false, 'invalid_context'
  end

  if entry.state == STATE_REVOKED then
    return false, 'revoked'
  end

  local timestamp <const>, dateOk <const> = internal.toTimestamp(expiresAt)

  if not dateOk or (timestamp and timestamp <= internal.now()) then
    return false, 'invalid_date'
  end

  if timestamp == entry.expiresAt then
    return false, 'unchanged'
  end

  MySQL.update.await(
    'UPDATE license_holdings SET expires_at = FROM_UNIXTIME(?) WHERE character_id = ? AND license_id = ?',
    { timestamp, characterId, license.id }
  )

  entry.expiresAt = timestamp

  forgetAnnounced(characterId, license)
  internal.push(characterId)
  internal.audit(
    AUDIT_EXPIRY_SET,
    license.id,
    characterId,
    internal.performerOf(context),
    ('expires=%s reason=%s'):format(internal.formatDate(timestamp) or 'never', internal.reasonOf(context) or '')
  )

  return true, nil
end

function Siku.licenses.getHolders(licenseName)
  local license <const> = internal.getLicense(licenseName)

  if not license then
    return {}
  end

  local rows <const> = MySQL.query.await(SELECT_HOLDERS, { license.id })
  local holders <const> = {}

  for index = 1, #rows do
    local row <const> = rows[index]
    local cached <const> = state.holdings[row.character_id]
    local entry <const> = cached and cached[license.name] or entryFromRow(row)

    holders[#holders + 1] = {
      characterId = row.character_id,
      firstName = row.first_name,
      lastName = row.last_name,
      state = internal.readState(entry),
      points = internal.pointsOf(license, entry),
      issuedAt = internal.formatDate(entry.issuedAt),
      expiresAt = internal.formatDate(entry.expiresAt),
      online = cached ~= nil,
    }
  end

  table.sort(holders, function(a, b)
    if a.lastName ~= b.lastName then
      return a.lastName < b.lastName
    end

    return a.firstName < b.firstName
  end)

  return holders
end

function Siku.licenses.countHolders(licenseName)
  local license <const> = internal.getLicense(licenseName)

  if not license then
    return 0
  end

  local total <const> = MySQL.scalar.await('SELECT COUNT(*) FROM license_holdings WHERE license_id = ?', { license.id })

  return type(total) == 'number' and total or 0
end
