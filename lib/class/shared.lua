--- Creates a class supporting metatable-based single inheritance.
--- Instances are created with `Class.new(...)`, which runs the optional
--- `constructor` method. A subclass reaches its parent through `Class.super`.
---@param name string The class name, used for debugging and instance checks.
---@param parent? table An optional parent class to inherit from.
---@return table class The new class table.
local function createClass(name, parent)
  local class <const> = {}

  class.__index = class
  class.__name = name
  class.__tostring = function()
    return name
  end
  class.super = parent

  if parent then
    setmetatable(class, { __index = parent })
  end

  --- Builds a new instance and runs its constructor when one is defined.
  ---@return table instance The new instance.
  class.new = function(...)
    local instance <const> = setmetatable({}, class)
    local constructor <const> = instance.constructor

    if constructor then
      constructor(instance, ...)
    end

    return instance
  end

  return class
end

--- Checks whether an object is an instance of a class or one of its ancestors.
---@param object any The object to test.
---@param class table The class to check against.
---@return boolean result Whether the object derives from the class.
local function isInstance(object, class)
  if type(object) ~= 'table' or type(class) ~= 'table' then
    return false
  end

  local current = getmetatable(object)

  while current do
    if current == class then
      return true
    end

    current = current.super
  end

  return false
end

return setmetatable({
  isInstance = isInstance,
}, {
  __call = function(_, name, parent)
    return createClass(name, parent)
  end,
})
