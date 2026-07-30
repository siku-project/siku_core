--- Create a deep copy of a table (recursively clones nested tables).
---@param tbl any The value to clone.
---@return any clone The deep copy.
function Siku.table.deepClone(tbl)
  if type(tbl) ~= 'table' then return tbl end

  local result <const> = {}
  for k, v in pairs(tbl) do
    result[k] = Siku.table.deepClone(v)
  end

  return result
end
