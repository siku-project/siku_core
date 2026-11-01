local RELEASE_URL <const> = 'https://api.github.com/repos/%s/releases/latest'
local BOOT_DELAY <const> = 2000
local HTTP_OK <const> = 200
local HTTP_NOT_FOUND <const> = 404
local HTTP_FORBIDDEN <const> = 403
local HTTP_TOO_MANY <const> = 429
local ENABLED <const> = Siku.config.version.enabled ~= false

local parseVersion <const> = internal.parseVersion
local compareVersions <const> = internal.compareVersions

--- Report how the installed version compares to the latest release.
---@param resource string The resource that was checked.
---@param currentVersion string The version currently installed.
---@param release table The decoded GitHub release payload.
local function reportRelease(resource, currentVersion, release)
  local latest <const> = parseVersion(release.tag_name)

  if not latest then
    Siku.log.warn('version.check_failed', ("Release '%s' of '%s' is not valid semver"):format(tostring(release.tag_name), resource), {
      resource = resource,
      reason = 'release_tag_invalid',
      tag = tostring(release.tag_name),
      current = currentVersion,
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return
  end

  local order <const> = compareVersions(parseVersion(currentVersion), latest)

  if order > 0 then
    return
  end

  if order < 0 then
    Siku.log.warn('version.outdated', ("A newer version of '%s' is available: %s, you are running %s"):format(resource, release.tag_name, currentVersion), {
      resource = resource,
      current = currentVersion,
      latest = release.tag_name,
      url = tostring(release.html_url),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })

    return
  end

  Siku.log.info('version.current', ("'%s' is up to date (%s)"):format(resource, currentVersion), {
    resource = resource,
    current = currentVersion,
  }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
end

--- Handle the GitHub response, reporting every failure instead of dropping it.
---@param resource string The resource that was checked.
---@param currentVersion string The version currently installed.
---@param repository string The repository that was queried.
---@param status number The HTTP status code returned.
---@param response string The raw response body.
local function handleResponse(resource, currentVersion, repository, status, response)
  if status == HTTP_FORBIDDEN or status == HTTP_TOO_MANY then
    Siku.log.warn('version.check_failed', ("Version check for '%s' hit the GitHub rate limit (HTTP %d)"):format(resource, status), {
      resource = resource,
      reason = 'rate_limited',
      repository = repository,
      status = status,
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return
  end

  if status == HTTP_NOT_FOUND then
    Siku.log.debug('version.check_skipped', ("No published release found for '%s', either none exists yet or the repository is missing or private"):format(repository), {
      resource = resource,
      reason = 'no_release',
      repository = repository,
      status = status,
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return
  end

  if status ~= HTTP_OK then
    Siku.log.warn('version.check_failed', ("Version check for '%s' failed: GitHub returned HTTP %d for '%s'"):format(resource, status, repository), {
      resource = resource,
      reason = 'http_error',
      repository = repository,
      status = status,
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return
  end

  local decoded <const>, release <const> = pcall(json.decode, response)

  if not decoded or type(release) ~= 'table' then
    Siku.log.warn('version.check_failed', ("Version check for '%s' received an unreadable response from GitHub"):format(resource), {
      resource = resource,
      reason = 'response_unreadable',
      repository = repository,
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return
  end

  if release.prerelease then
    Siku.log.debug('version.check_skipped', ("Latest release of '%s' is a prerelease, skipping"):format(resource), {
      resource = resource,
      reason = 'prerelease',
      repository = repository,
      tag = tostring(release.tag_name),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return
  end

  reportRelease(resource, currentVersion, release)
end

--- Compare this resource against its latest GitHub release and log the outcome.
---@param repository string The GitHub repository, such as 'SIKU/siku_core'.
---@return boolean started Whether the check was scheduled.
local function checkRelease(repository)
  local resource <const> = Siku.name

  if not ENABLED then
    Siku.log.debug('version.check_skipped', ("Version check for '%s' is disabled by convar"):format(resource), {
      resource = resource,
      reason = 'disabled',
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  if type(repository) ~= 'string' or not repository:find('/') then
    Siku.log.warn('version.check_failed', ("Version check for '%s' needs a repository shaped as 'owner/name'"):format(resource), {
      resource = resource,
      reason = 'repository_invalid',
      repository = tostring(repository),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  local currentVersion <const> = GetResourceMetadata(resource, 'version', 0)

  if not currentVersion then
    Siku.log.warn('version.check_failed', ("Unable to determine the version of '%s'"):format(resource), {
      resource = resource,
      reason = 'version_missing',
      repository = repository,
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  if not parseVersion(currentVersion) then
    Siku.log.warn('version.check_failed', ("'%s' declares an unreadable version '%s'"):format(resource, currentVersion), {
      resource = resource,
      reason = 'version_invalid',
      repository = repository,
      current = currentVersion,
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  SetTimeout(BOOT_DELAY, function()
    PerformHttpRequest(
      RELEASE_URL:format(repository),
      function(status, response)
        handleResponse(resource, currentVersion, repository, status, response)
      end,
      'GET',
      '',
      { ['Accept'] = 'application/vnd.github+json' }
    )
  end)

  return true
end

return {
  checkRelease = checkRelease,
}
