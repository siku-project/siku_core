--- Check that a value can be called, accepting the callable function
--- references produced when a function crosses a resource export
--- boundary — a consumer resource passing a handler through the SDK
--- sends a table carrying __call, never a raw function.
---@param value any The value to check.
---@return boolean callable Whether the value is callable.
function _SikuInternal.IsCallable(value)
  if type(value) == 'function' then
    return true
  end

  local meta <const> = getmetatable(value)

  return meta ~= nil and meta.__call ~= nil
end
