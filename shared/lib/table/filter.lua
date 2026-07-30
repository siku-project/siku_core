--- Filter elements that match a condition and return a new table.
---@param tbl table The table to filter.
---@param fn function The predicate function (receives value, key). Return true to keep.
---@return table result A new table with only matching elements.
function Siku.table.filter(tbl, fn)
  local result <const> = {}

  if #tbl > 0 then
    local count = 0
    for i = 1, #tbl do
      if fn(tbl[i], i) then
        count = count + 1
        result[count] = tbl[i]
      end
    end
  else
    for k, v in pairs(tbl) do
      if fn(v, k) then
        result[k] = v
      end
    end
  end

  return result
end
