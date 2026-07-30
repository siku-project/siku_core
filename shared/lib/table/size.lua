--- Get the total number of entries in a table (works for both arrays and dictionaries).
---@param tbl table The table to count.
---@return number count The number of entries.
function Siku.table.size(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end
