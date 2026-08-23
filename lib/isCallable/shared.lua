--- Check that a value can be called, accepting the callable function
--- references produced when a function crosses a resource export
--- boundary, which arrive as a table carrying __call.
---@param value any The value to check.
---@return boolean callable Whether the value is callable.
local function isCallable(value)
  if type(value) == 'function' then
    return true
  end

  local meta <const> = getmetatable(value)

  return meta ~= nil and meta.__call ~= nil
end

return isCallable
