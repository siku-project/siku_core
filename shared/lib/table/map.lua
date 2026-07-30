--- Apply a function to each element and return a new table with the results.
---@param tbl table The table to map over.
---@param fn function The function to apply (receives value, key).
---@return table result A new table with mapped values.
function Siku.table.map(tbl, fn)
  local result <const> = {}

  if #tbl > 0 then
    for i = 1, #tbl do
      result[i] = fn(tbl[i], i)
    end
  else
    for k, v in pairs(tbl) do
      result[k] = fn(v, k)
    end
  end

  return result
end
