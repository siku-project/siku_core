local CORE <const> = 'siku_core'
local SERVICES_EXPORT <const> = 'objectExport'
local MODULE_PATH <const> = 'lib/%s/%s.lua'
local CONFIG_PATH <const> = 'config/%s.lua'
local CONFIG_SUFFIX <const> = 'Config'
local CHUNK_NAME <const> = '@@%s/%s'
local SHARED <const> = 'shared'

if not _VERSION:find('5.4') then
  error('Lua 5.4 must be enabled in the resource manifest!', 2)
end

local resource <const> = GetCurrentResourceName()
local context <const> = IsDuplicityVersion() and 'server' or 'client'
local isCore <const> = resource == CORE

if Siku then
  error(("Cannot load siku_core more than once.\n\tRemove any duplicate entries from '@%s/fxmanifest.lua'"):format(resource))
end

if not isCore and GetResourceState(CORE) ~= 'started' then
  error(("^1siku_core must be started before '%s'.^0"):format(resource), 0)
end

local services <const> = (not isCore and context == 'server') and exports[CORE][SERVICES_EXPORT]() or {}
local absent <const> = {}
local loading <const> = {}

--- Compile one file shipped by the core so it runs in this resource's VM.
---@param path string The path relative to the core resource.
---@param env table The environment the chunk runs in.
---@return function? chunk The compiled chunk, or nil when the file does not exist.
local function compile(path, env)
  local source <const> = LoadResourceFile(CORE, path)

  if not source then
    return nil
  end

  local chunk <const>, err <const> = load(source, CHUNK_NAME:format(CORE, path), 't', env)

  if not chunk then
    error(('[%s] %s'):format(CORE, err), 0)
  end

  return chunk
end

--- Copy the keys of a table into a namespace.
---@param namespace table The namespace being assembled.
---@param exports table The exports returned by a module file.
local function merge(namespace, exports)
  for key, value in pairs(exports) do
    namespace[key] = value
  end
end

--- Run one module file and fold its result into the namespace: a plain
--- table is merged, anything else replaces the namespace as the module value.
---@param chunk function The compiled module file.
---@param namespace table The namespace being assembled.
---@return any value The value that replaces the namespace, or nil when the file merged into it.
local function absorb(chunk, namespace)
  local result <const> = chunk()

  if type(result) == 'table' and getmetatable(result) == nil then
    merge(namespace, result)
    return nil
  end

  return result
end

--- Build the environment every file of one module runs in: the globals,
--- an `internal` table the module's files share privately, and `import`,
--- which loads a part of the module from its own folder and merges what
--- it returns into the namespace.
---@param name string The module name, which is its folder under lib/.
---@param namespace table The namespace being assembled.
---@return table env The module environment.
local function createEnvironment(name, namespace)
  local env <const> = setmetatable({ internal = {} }, { __index = _G })

  --- Load one part of the current module and merge its exports into the namespace.
  ---@param part string The part file name, without extension, inside the module folder.
  ---@return any exports What the part returned.
  function env.import(part)
    local chunk <const> = compile(MODULE_PATH:format(name, part), env)

    if not chunk then
      error(("[%s] Module '%s' imports a missing part '%s'"):format(CORE, name, part), 2)
    end

    local result <const> = chunk()

    if type(result) == 'table' and getmetatable(result) == nil then
      merge(namespace, result)
    end

    return result
  end

  return env
end

--- Load a module from lib/<name>/: its shared file, then its context file,
--- when they exist.
---@param name string The module name.
---@return any module The module value, or nil when no file exists for it.
local function loadModule(name)
  local namespace <const> = {}
  local env <const> = createEnvironment(name, namespace)
  local value = nil
  local found = false

  for _, file in ipairs({ SHARED, context }) do
    local chunk <const> = compile(MODULE_PATH:format(name, file), env)

    if chunk then
      found = true
      value = absorb(chunk, namespace) or value
    end
  end

  if not found then
    return nil
  end

  return value or namespace
end

--- Resolve one SDK key on first access: a module of the core, or a service
--- the core exports, cached on the SDK table afterwards.
---@param sdk table The SDK table.
---@param key any The key being accessed.
---@return any value The resolved value, or nil when nothing answers to the key.
local function resolve(sdk, key)
  if type(key) ~= 'string' or absent[key] then
    return nil
  end

  if loading[key] then
    error(("[%s] Siku.%s is accessed while it is still loading, share that state through `internal` instead"):format(CORE, key), 2)
  end

  loading[key] = true

  local ok <const>, loaded <const> = pcall(loadModule, key)

  loading[key] = nil

  if not ok then
    error(loaded, 0)
  end

  local value = loaded

  if value == nil then
    value = services[key]
  end

  if value == nil then
    absent[key] = true
    return nil
  end

  rawset(sdk, key, value)

  return value
end

--- Read one core config file on first access, without defining a global,
--- accepting both a returned table and the conventional <Name>Config one.
---@param configs table The config table.
---@param name string The config name, matching config/<name>.lua.
---@return table config The config table.
local function resolveConfig(configs, name)
  local env <const> = setmetatable({}, { __index = _G })
  local chunk <const> = compile(CONFIG_PATH:format(name), env)

  if not chunk then
    error(("[%s] Unknown config '%s'"):format(CORE, name), 2)
  end

  local value <const> = chunk() or env[name:sub(1, 1):upper() .. name:sub(2) .. CONFIG_SUFFIX]

  if type(value) ~= 'table' then
    error(("[%s] Config '%s' defines no table"):format(CORE, name), 2)
  end

  rawset(configs, name, value)

  return value
end

Siku = setmetatable({
  name = resource,
  context = context,
  config = setmetatable({}, { __index = resolveConfig }),
}, { __index = resolve })

T = Siku.locale.translate
