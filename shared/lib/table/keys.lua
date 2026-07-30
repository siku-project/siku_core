--- Get all keys of a table as an array.
---@param tbl table The table to get keys from.
---@return table keys A list of keys.
function Siku.table.keys(tbl)
  local result <const> = {}
  for k in pairs(tbl) do
    result[#result + 1] = k
  end
  return result
end
