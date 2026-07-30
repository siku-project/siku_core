--- Find the first element that matches a condition.
---@param tbl table The table to search.
---@param fn function The predicate function (receives value, key). Return true to match.
---@return any|nil result The first matching value or nil.
function Siku.table.find(tbl, fn)
  if #tbl > 0 then
    for i = 1, #tbl do
      if fn(tbl[i], i) then return tbl[i] end
    end
  else
    for k, v in pairs(tbl) do
      if fn(v, k) then return v end
    end
  end

  return nil
end
