local internal <const> = _SikuInternal.licenses
local state <const> = internal.state

local EVENT_REGISTERED <const> = 'registered'
local EVENT_DEACTIVATED <const> = 'deactivated'

local function createEntry(row)
  return {
    id = row.id,
    name = row.name,
    label = row.label,
    group = row.group_name,
    maxPoints = internal.toInteger(row.max_points),
    validityDays = internal.toInteger(row.validity_days),
    resource = row.resource,
    active = false,
  }
end

function internal.reloadLicense(licenseId)
  local row <const> = MySQL.single.await('SELECT * FROM licenses WHERE id = ?', { licenseId })

  if not row then
    return nil
  end

  local previous <const> = state.byId[licenseId]
  local license <const> = createEntry(row)

  license.active = previous ~= nil and previous.active

  if previous and previous.name ~= license.name then
    state.byName[previous.name] = nil
  end

  state.byName[license.name] = license
  state.byId[license.id] = license

  return license
end

local function loadRegistry()
  state.byName = {}
  state.byId = {}

  local rows <const> = MySQL.query.await('SELECT id FROM licenses')

  for index = 1, #rows do
    internal.reloadLicense(rows[index].id)
  end

  return #rows
end

local function normalizeDefinition(definition)
  if type(definition) ~= 'table' then
    return nil, 'definition must be a table'
  end

  if not internal.isValidName(definition.name) then
    return nil, ('license name %q is invalid: lowercase letters, digits and underscores'):format(tostring(definition.name))
  end

  if type(definition.label) ~= 'string' or definition.label == '' or #definition.label > internal.LABEL_MAX_LENGTH then
    return nil, ('license %q needs a label'):format(definition.name)
  end

  if definition.group ~= nil and not internal.isValidName(definition.group) then
    return nil, ('license %q declares an invalid group %q'):format(definition.name, tostring(definition.group))
  end

  local maxPoints = nil

  if definition.points ~= nil then
    if type(definition.points) ~= 'table' then
      return nil, ('license %q: points must be a table'):format(definition.name)
    end

    maxPoints = internal.toInteger(definition.points.max)

    if not maxPoints or maxPoints <= 0 then
      return nil, ('license %q: points.max must be a whole, positive number'):format(definition.name)
    end
  end

  local validityDays = nil

  if definition.validity ~= nil then
    validityDays = internal.toInteger(definition.validity)

    if not validityDays or validityDays <= 0 then
      return nil, ('license %q: validity must be a whole, positive number of days'):format(definition.name)
    end
  end

  return {
    name = definition.name,
    label = definition.label,
    group = definition.group,
    maxPoints = maxPoints,
    validityDays = validityDays,
  }, nil
end

local function isHeldElsewhere(license, resource)
  if not license.resource or license.resource == resource then
    return false
  end

  return license.active
end

local function writeDefinition(normalized, existing, resource)
  if existing then
    MySQL.update.await(
      'UPDATE licenses SET label = ?, group_name = ?, max_points = ?, validity_days = ?, resource = ? WHERE id = ?',
      { normalized.label, normalized.group, normalized.maxPoints, normalized.validityDays, resource, existing.id }
    )

    return existing.id
  end

  return MySQL.insert.await(
    'INSERT INTO licenses (name, label, group_name, max_points, validity_days, resource) VALUES (?, ?, ?, ?, ?, ?)',
    { normalized.name, normalized.label, normalized.group, normalized.maxPoints, normalized.validityDays, resource }
  )
end

function Siku.licenses.register(definition)
  local resource <const> = GetInvokingResource() or GetCurrentResourceName()
  local normalized <const>, reason <const> = normalizeDefinition(definition)

  if not normalized then
    Siku.print.error(('License registration from %q refused: %s'):format(resource, reason))
    return false, reason
  end

  if not internal.waitReady() then
    Siku.print.error(('License %q could not be registered: the registry never came up'):format(normalized.name))
    return false, 'not_ready'
  end

  local existing <const> = state.byName[normalized.name]

  if existing and isHeldElsewhere(existing, resource) then
    Siku.print.error(('License %q is owned by %q, registration from %q refused'):format(normalized.name, existing.resource, resource))
    return false, 'owned_elsewhere'
  end

  if existing and existing.resource and existing.resource ~= resource then
    Siku.print.warn(('License %q moves from %q to %q'):format(normalized.name, existing.resource, resource))
  end

  local licenseId <const> = writeDefinition(normalized, existing, resource)
  local license <const> = internal.reloadLicense(licenseId)

  if not license then
    return false, 'reload_failed'
  end

  license.active = true

  internal.audit(EVENT_REGISTERED, license.id, nil, nil, ('resource=%s'):format(resource))
  internal.emit(EVENT_REGISTERED, license.name, internal.publicLicense(license))
  Siku.print.info(('License %q registered by %q'):format(license.name, resource))

  return true, nil
end

local function deactivateLicensesOf(resource)
  for _, license in pairs(state.byName) do
    if license.active and license.resource == resource then
      license.active = false

      internal.emit(EVENT_DEACTIVATED, license.name)
      Siku.print.info(('License %q is dormant: %q stopped'):format(license.name, resource))
    end
  end
end

function _SikuInternal.InitLicenses()
  local count <const> = loadRegistry()

  state.ready = true

  Siku.print.success(('Licenses engine initialized with %d license(s)'):format(count))
end

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    return
  end

  deactivateLicensesOf(resource)
end)
