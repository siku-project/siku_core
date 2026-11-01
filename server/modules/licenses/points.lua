local internal <const> = _SikuInternal.licenses
local state <const> = internal.state

local STATE_VALID <const> = internal.STATE_VALID
local EVENT_POINTS_CHANGED <const> = 'pointsChanged'
local EVENT_POINTS_EXHAUSTED <const> = 'pointsExhausted'

local function resolve(characterId, licenseName, context)
  local license <const> = internal.getLicense(licenseName)

  if not license then
    return nil, nil, 'unknown_license'
  end

  if not internal.checkContext(context) then
    return nil, nil, 'invalid_context'
  end

  if not license.maxPoints then
    return nil, nil, 'no_points'
  end

  if not internal.toInteger(characterId) then
    return nil, nil, 'unknown_character'
  end

  local entry <const> = internal.entryOf(characterId, license)

  if not entry then
    return nil, nil, 'not_held'
  end

  if internal.readState(entry) ~= STATE_VALID then
    return nil, nil, 'not_valid'
  end

  return license, entry, nil
end

local function write(characterId, license, entry, target, context)
  local previous <const> = internal.pointsOf(license, entry)
  local points <const> = math.max(0, math.min(target, license.maxPoints))

  if points == previous then
    return false, 'unchanged'
  end

  MySQL.update.await(
    'UPDATE license_holdings SET points = ? WHERE character_id = ? AND license_id = ?',
    { points, characterId, license.id }
  )

  entry.points = points

  local performedBy <const> = internal.performerOf(context)
  local reason <const> = internal.reasonOf(context)
  local sessionId <const> = state.sessions[characterId]

  internal.push(characterId)

  local entities <const> = {
    { type = 'license', id = license.name, role = 'subject', label = license.label },
    { type = 'character', id = characterId, role = 'target' },
  }

  if performedBy then
    entities[#entities + 1] = { type = 'character', id = performedBy, role = 'actor' }
  end

  Siku.log.audit('licenses.points_changed', {
    message = ('Points of %s moved from %d to %d for character %d'):format(license.name, previous, points, characterId),
    entities = entities,
    data = { license = license.name, from = previous, to = points, delta = points - previous, max = license.maxPoints, reason = reason },
  })
  internal.emit(EVENT_POINTS_CHANGED, characterId, license.name, points, points - previous, reason, performedBy, sessionId)

  if previous > 0 and points == 0 then
    internal.emit(EVENT_POINTS_EXHAUSTED, characterId, license.name, sessionId)
  end

  return true, nil
end

local function positiveAmount(amount)
  local whole <const> = internal.toInteger(amount)

  if not whole or whole <= 0 then
    return nil
  end

  return whole
end

function Siku.licenses.addPoints(characterId, licenseName, amount, context)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName, context)

  if not entry then
    return false, reason
  end

  local whole <const> = positiveAmount(amount)

  if not whole then
    return false, 'invalid_amount'
  end

  return write(characterId, license, entry, internal.pointsOf(license, entry) + whole, context)
end

function Siku.licenses.removePoints(characterId, licenseName, amount, context)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName, context)

  if not entry then
    return false, reason
  end

  local whole <const> = positiveAmount(amount)

  if not whole then
    return false, 'invalid_amount'
  end

  return write(characterId, license, entry, internal.pointsOf(license, entry) - whole, context)
end

function Siku.licenses.setPoints(characterId, licenseName, points, context)
  local license <const>, entry <const>, reason <const> = resolve(characterId, licenseName, context)

  if not entry then
    return false, reason
  end

  local whole <const> = internal.toInteger(points)

  if not whole or whole < 0 then
    return false, 'invalid_amount'
  end

  return write(characterId, license, entry, whole, context)
end
