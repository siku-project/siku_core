--- Deep equality comparison between two values (supports nested tables).
---@param a any The first value.
---@param b any The second value.
---@return boolean equal Whether the two values are deeply equal.
function Siku.table.matches(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return false end

  local aCount = 0
  for k, v in pairs(a) do
    aCount = aCount + 1
    if not Siku.table.matches(v, b[k]) then return false end
  end

  local bCount = 0
  for _ in pairs(b) do
    bCount = bCount + 1
  end

  return aCount == bCount
end
