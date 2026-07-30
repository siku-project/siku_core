--- Check if a table contains a value or all values from a list.
---@param tbl table The table to search in.
---@param value any A single value or a list of values to check for.
---@return boolean found Whether the value(s) were found.
function Siku.table.contains(tbl, value)
  local values <const> = {}
  for _, v in pairs(tbl) do
    values[v] = true
  end

  if type(value) == 'table' then
    for i = 1, #value do
      if not values[value[i]] then return false end
    end
    return true
  end

  return values[value] == true
end
