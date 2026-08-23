local FROZEN <const> = 'frozen'

local tableLib <const> = {}

--- Check if a table contains a value or all values from a list.
---@param tbl table The table to search in.
---@param value any A single value or a list of values to check for.
---@return boolean found Whether the value(s) were found.
function tableLib.contains(tbl, value)
  local values <const> = {}

  for _, v in pairs(tbl) do
    values[v] = true
  end

  if type(value) == 'table' then
    for i = 1, #value do
      if not values[value[i]] then
        return false
      end
    end

    return true
  end

  return values[value] == true
end

--- Create a deep copy of a table (recursively clones nested tables).
---@param tbl any The value to clone.
---@return any clone The deep copy.
function tableLib.deepClone(tbl)
  if type(tbl) ~= 'table' then
    return tbl
  end

  local result <const> = {}

  for k, v in pairs(tbl) do
    result[k] = tableLib.deepClone(v)
  end

  return result
end

--- Filter elements that match a condition and return a new table.
---@param tbl table The table to filter.
---@param fn function The predicate function (receives value, key). Return true to keep.
---@return table result A new table with only matching elements.
function tableLib.filter(tbl, fn)
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

--- Find the first element that matches a condition.
---@param tbl table The table to search.
---@param fn function The predicate function (receives value, key). Return true to match.
---@return any|nil result The first matching value or nil.
function tableLib.find(tbl, fn)
  if #tbl > 0 then
    for i = 1, #tbl do
      if fn(tbl[i], i) then
        return tbl[i]
      end
    end
  else
    for k, v in pairs(tbl) do
      if fn(v, k) then
        return v
      end
    end
  end

  return nil
end

--- Freeze a table (make it read-only). Any attempt to modify will throw an error.
---@param tbl table The table to freeze.
---@return table frozen The frozen table.
function tableLib.freeze(tbl)
  return setmetatable({}, {
    __index = tbl,
    __newindex = function()
      Siku.print.throw('Cannot modify a frozen table')
    end,
    __len = function()
      return #tbl
    end,
    __pairs = function()
      return pairs(tbl)
    end,
    __ipairs = function()
      return ipairs(tbl)
    end,
    __metatable = FROZEN,
  })
end

--- Check if a table is frozen.
---@param tbl table The table to check.
---@return boolean frozen Whether the table is frozen.
function tableLib.isFrozen(tbl)
  return getmetatable(tbl) == FROZEN
end

--- Get all keys of a table as an array.
---@param tbl table The table to get keys from.
---@return table keys A list of keys.
function tableLib.keys(tbl)
  local result <const> = {}

  for k in pairs(tbl) do
    result[#result + 1] = k
  end

  return result
end

--- Apply a function to each element and return a new table with the results.
---@param tbl table The table to map over.
---@param fn function The function to apply (receives value, key).
---@return table result A new table with mapped values.
function tableLib.map(tbl, fn)
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

--- Deep equality comparison between two values (supports nested tables).
---@param a any The first value.
---@param b any The second value.
---@return boolean equal Whether the two values are deeply equal.
function tableLib.matches(a, b)
  if a == b then
    return true
  end

  if type(a) ~= type(b) or type(a) ~= 'table' then
    return false
  end

  local aCount = 0

  for k, v in pairs(a) do
    aCount = aCount + 1

    if not tableLib.matches(v, b[k]) then
      return false
    end
  end

  local bCount = 0

  for _ in pairs(b) do
    bCount = bCount + 1
  end

  return aCount == bCount
end

--- Deep merge source into target (mutates target). Numbers are added together by default.
---@param target table The target table to merge into.
---@param source table The source table to merge from.
---@param addNumbers? boolean Add numbers instead of replacing (default: true).
---@return table target The merged target table.
function tableLib.merge(target, source, addNumbers)
  if addNumbers == nil then
    addNumbers = true
  end

  for k, sourceVal in pairs(source) do
    local targetVal <const> = target[k]

    if type(targetVal) == 'table' and type(sourceVal) == 'table' then
      tableLib.merge(targetVal, sourceVal, addNumbers)
    elseif addNumbers and type(targetVal) == 'number' and type(sourceVal) == 'number' then
      target[k] = targetVal + sourceVal
    else
      target[k] = sourceVal
    end
  end

  return target
end

--- Get the total number of entries in a table (works for both arrays and dictionaries).
---@param tbl table The table to count.
---@return number count The number of entries.
function tableLib.size(tbl)
  local count = 0

  for _ in pairs(tbl) do
    count = count + 1
  end

  return count
end

--- Get all values of a table as an array.
---@param tbl table The table to get values from.
---@return table values A list of values.
function tableLib.values(tbl)
  local result <const> = {}

  for _, v in pairs(tbl) do
    result[#result + 1] = v
  end

  return result
end

return tableLib
