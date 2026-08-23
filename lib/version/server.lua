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
    Siku.print.warn(("Release '%s' of '%s' is not valid semver"):format(tostring(release.tag_name), resource))
    return
  end

  local order <const> = compareVersions(parseVersion(currentVersion), latest)

  if order > 0 then
    return
  end

  if order < 0 then
    Siku.print.warn(("A newer version of '%s' is available: %s, you are running %s\n%s"):format(
      resource,
      release.tag_name,
      currentVersion,
      tostring(release.html_url)
    ))

    return
  end

  Siku.print.success(("'%s' is up to date (%s)"):format(resource, currentVersion))
end

--- Handle the GitHub response, reporting every failure instead of dropping it.
---@param resource string The resource that was checked.
---@param currentVersion string The version currently installed.
---@param repository string The repository that was queried.
---@param status number The HTTP status code returned.
---@param response string The raw response body.
local function handleResponse(resource, currentVersion, repository, status, response)
  if status == HTTP_FORBIDDEN or status == HTTP_TOO_MANY then
    Siku.print.warn(("Version check for '%s' hit the GitHub rate limit (HTTP %d)"):format(resource, status))
    return
  end

  if status == HTTP_NOT_FOUND then
    Siku.print.debug(("No published release found for '%s', either none exists yet or the repository is missing or private"):format(repository))
    return
  end

  if status ~= HTTP_OK then
    Siku.print.warn(("Version check for '%s' failed: GitHub returned HTTP %d for '%s'"):format(resource, status, repository))
    return
  end

  local decoded <const>, release <const> = pcall(json.decode, response)

  if not decoded or type(release) ~= 'table' then
    Siku.print.warn(("Version check for '%s' received an unreadable response from GitHub"):format(resource))
    return
  end

  if release.prerelease then
    Siku.print.debug(("Latest release of '%s' is a prerelease, skipping"):format(resource))
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
    Siku.print.debug(("Version check for '%s' is disabled by convar"):format(resource))
    return false
  end

  if type(repository) ~= 'string' or not repository:find('/') then
    Siku.print.warn(("Version check for '%s' needs a repository shaped as 'owner/name'"):format(resource))
    return false
  end

  local currentVersion <const> = GetResourceMetadata(resource, 'version', 0)

  if not currentVersion then
    Siku.print.warn(("Unable to determine the version of '%s'"):format(resource))
    return false
  end

  if not parseVersion(currentVersion) then
    Siku.print.warn(("'%s' declares an unreadable version '%s'"):format(resource, currentVersion))
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
