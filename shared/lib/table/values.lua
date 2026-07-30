--- Get all values of a table as an array.
---@param tbl table The table to get values from.
---@return table values A list of values.
function Siku.table.values(tbl)
  local result <const> = {}
  for _, v in pairs(tbl) do
    result[#result + 1] = v
  end
  return result
end
