--- Split a permission string into its dot-separated segments.
---@param permission string The permission string.
---@return table segments The ordered list of segments.
local function splitSegments(permission)
  local segments <const> = {}
  for segment in (permission .. '.'):gmatch('(.-)%.') do
    segments[#segments + 1] = segment
  end
  return segments
end

--- Check whether a granted pattern covers a required permission, segment by segment.
--- A lone '*' matches everything. A non-final '*' matches exactly one segment.
--- A trailing '*' matches one or more remaining segments (any depth).
---@param pattern string The granted permission pattern (may contain '*').
---@param required string The concrete permission being checked.
---@return boolean matches Whether the pattern covers the permission.
local function patternMatches(pattern, required)
  if pattern == '*' then return true end

  local patSegs <const> = splitSegments(pattern)
  local reqSegs <const> = splitSegments(required)

  for i = 1, #patSegs do
    if patSegs[i] == '*' and i == #patSegs then
      return #reqSegs >= i
    end

    if i > #reqSegs then return false end
    if patSegs[i] ~= '*' and patSegs[i] ~= reqSegs[i] then return false end
  end

  return #reqSegs == #patSegs
end

--- Check if a required permission is granted by a set of permissions (multi-level wildcards and negation).
--- Negation ('-perm', wildcards allowed) always wins; otherwise any matching grant allows.
---@param granted table A set of granted permissions { ['perm.name'] = true }.
---@param required string The permission to check.
---@return boolean allowed Whether the permission is granted.
function _SikuInternal.MatchPermission(granted, required)
  local allowed = false

  for pattern in pairs(granted) do
    if pattern:sub(1, 1) == '-' then
      if patternMatches(pattern:sub(2), required) then return false end
    elseif patternMatches(pattern, required) then
      allowed = true
    end
  end

  return allowed
end

--- Validate that a permission string has a valid format.
--- Accepts '*' (superadmin), an optional '-' negation prefix, and otherwise
--- dot-separated segments where each segment is an identifier or a lone '*'.
---@param permission string The permission string to validate.
---@return boolean valid Whether the permission is valid.
function _SikuInternal.IsValidPermission(permission)
  if permission == '*' then return true end

  local clean <const> = permission:sub(1, 1) == '-' and permission:sub(2) or permission
  local segments = 0

  for segment in (clean .. '.'):gmatch('(.-)%.') do
    segments = segments + 1
    if segment ~= '*' and not segment:match('^[%w_]+$') then
      return false
    end
  end

  return segments >= 2
end
