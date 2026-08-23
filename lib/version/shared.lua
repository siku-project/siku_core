local SEMVER_PATTERN <const> = '^(%d+)%.(%d+)%.(%d+)'
local UNKNOWN_VERSION <const> = 'unknown'

--- Parse a semver string into its numeric parts, tolerating a leading 'v' and a prerelease suffix.
---@param version string The version string, such as '1.2.3', 'v1.2.3' or '1.2.3-beta'.
---@return table? parsed The major, minor and patch numbers, or nil when unparseable.
local function parseVersion(version)
  if type(version) ~= 'string' then
    return nil
  end

  local normalized <const> = version:gsub('^v', '')
  local major <const>, minor <const>, patch <const> = normalized:match(SEMVER_PATTERN)

  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

--- Compare two parsed versions.
---@param current table The version being tested.
---@param other table The version compared against.
---@return number order -1 when current is lower, 0 when equal, 1 when higher.
local function compareVersions(current, other)
  for i = 1, 3 do
    if current[i] < other[i] then
      return -1
    end

    if current[i] > other[i] then
      return 1
    end
  end

  return 0
end

---@class SikuDependencyResult
---@field ok boolean Whether the dependency satisfies the requirement.
---@field resource string The resource that was checked.
---@field state string One of 'ok', 'missing', 'stopped', 'unversioned', 'malformed' or 'outdated'.
---@field requiredVersion string The minimum version asked for.
---@field currentVersion string The version found, or 'unknown'.
---@field message string A human readable explanation, empty when ok.

--- Build a dependency result.
---@param ok boolean Whether the requirement is satisfied.
---@param resource string The resource that was checked.
---@param state string The outcome discriminator.
---@param requiredVersion string The minimum version asked for.
---@param currentVersion string The version found.
---@param message string The explanation, empty when ok.
---@return SikuDependencyResult result The assembled result.
local function buildResult(ok, resource, state, requiredVersion, currentVersion, message)
  return {
    ok = ok,
    resource = resource,
    state = state,
    requiredVersion = requiredVersion,
    currentVersion = currentVersion,
    message = message,
  }
end

--- Check that a resource is started and meets a minimum version. Never logs, never raises.
---@param resource string The resource name to check.
---@param minimumVersion string The minimum version required, in semver form.
---@return SikuDependencyResult result The outcome, carrying a state and a message.
local function checkDependency(resource, minimumVersion)
  local caller <const> = Siku.name

  if type(resource) ~= 'string' or resource == '' then
    return buildResult(false, tostring(resource), 'malformed', tostring(minimumVersion), UNKNOWN_VERSION,
      ("'%s' asked for a dependency without naming it"):format(caller))
  end

  local requested <const> = parseVersion(minimumVersion)

  if not requested then
    return buildResult(false, resource, 'malformed', tostring(minimumVersion), UNKNOWN_VERSION,
      ("'%s' requires '%s' with an invalid version '%s'"):format(caller, resource, tostring(minimumVersion)))
  end

  local state <const> = GetResourceState(resource)

  if state == 'missing' or state == 'unknown' then
    return buildResult(false, resource, 'missing', minimumVersion, UNKNOWN_VERSION,
      ("'%s' requires '%s' which is not installed"):format(caller, resource))
  end

  if state ~= 'started' then
    return buildResult(false, resource, 'stopped', minimumVersion, UNKNOWN_VERSION,
      ("'%s' requires '%s' which is '%s' instead of 'started'"):format(caller, resource, state))
  end

  local rawVersion <const> = GetResourceMetadata(resource, 'version', 0)

  if not rawVersion then
    return buildResult(false, resource, 'unversioned', minimumVersion, UNKNOWN_VERSION,
      ("'%s' requires '%s' >= %s but it declares no version"):format(caller, resource, minimumVersion))
  end

  local current <const> = parseVersion(rawVersion)

  if not current then
    return buildResult(false, resource, 'malformed', minimumVersion, rawVersion,
      ("'%s' declares an unreadable version '%s'"):format(resource, rawVersion))
  end

  if compareVersions(current, requested) < 0 then
    return buildResult(false, resource, 'outdated', minimumVersion, rawVersion,
      ("'%s' requires '%s' >= %s but %s is installed"):format(caller, resource, minimumVersion, rawVersion))
  end

  return buildResult(true, resource, 'ok', minimumVersion, rawVersion, '')
end

internal.parseVersion = parseVersion
internal.compareVersions = compareVersions

return {
  checkDependency = checkDependency,
}
