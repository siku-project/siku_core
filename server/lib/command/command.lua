local CONSOLE_SOURCE <const> = 0
local COOLDOWN_KEY_FORMAT <const> = '%d:%s'
local COMMAND_NAME_PATTERN <const> = '^[%w_%-]+$'
local DURATION_PATTERN <const> = '^(%d+)([smhd]?)$'
local CHAT_RESOURCE <const> = 'siku_chat'
local ERROR_NOTIFICATION_DURATION <const> = 5000

local DURATION_UNITS <const> = {
  [''] = 1,
  s = 1,
  m = 60,
  h = 3600,
  d = 86400,
}

local BOOLEAN_VALUES <const> = {
  ['true'] = true,
  ['1'] = true,
  yes = true,
  on = true,
  ['false'] = false,
  ['0'] = false,
  no = false,
  off = false,
}

local commands = {}
local nativeNames = {}
local cooldowns = {}
local typeParsers = {}

---Checks whether a character grants the given permission to a player.
---@param src number The player's server id.
---@param permission string The permission to check.
---@return boolean allowed
local function hasCommandPermission(src, permission)
  local character <const> = Siku.cache.getCurrentCharacter(src)

  if type(character) ~= 'table' or type(character.id) ~= 'number' then
    return false
  end

  return Siku.permissions.hasPermission(character.id, permission)
end

---Checks whether the chat resource is available for suggestions.
---@return boolean ready
local function isChatReady()
  return GetResourceState(CHAT_RESOURCE) == 'started'
end

---Pushes a command suggestion to the chat, filtered by permission when one is set.
---@param def table The command definition.
---@return nil
local function pushSuggestion(def)
  if not isChatReady() then
    return
  end

  if not def.permission then
    pcall(function()
      exports[CHAT_RESOURCE]:AddSuggestion(-1, def.suggestion)
    end)
    return
  end

  for _, id in ipairs(GetPlayers()) do
    local src <const> = tonumber(id)

    if src and hasCommandPermission(src, def.permission) then
      pcall(function()
        exports[CHAT_RESOURCE]:AddSuggestion(src, def.suggestion)
      end)
    end
  end
end

---Removes a command suggestion from the chat for everyone.
---@param name string The command name.
---@return nil
local function dropSuggestion(name)
  if not isChatReady() then
    return
  end

  pcall(function()
    exports[CHAT_RESOURCE]:RemoveSuggestion(-1, name)
  end)
end

---Reports a command error to the caller — notification for players, console log otherwise.
---@param src number The caller's server id, or 0 for the console.
---@param name string The command name.
---@param description string The error description.
---@return nil
local function reportError(src, name, description)
  if src == CONSOLE_SOURCE then
    Siku.print.warn(('/%s: %s'):format(name, description))
    return
  end

  Siku.Notification(src, {
    type = 'error',
    title = ('/%s'):format(name),
    description = description,
    duration = ERROR_NOTIFICATION_DURATION,
  })
end

---Checks the numeric bounds declared on an argument definition.
---@param value number The parsed value.
---@param def table The argument definition.
---@return string? error
local function checkBounds(value, def)
  if type(def.min) == 'number' and value < def.min then
    return ('\'%s\' must be at least %s'):format(def.name, def.min)
  end

  if type(def.max) == 'number' and value > def.max then
    return ('\'%s\' must be at most %s'):format(def.name, def.max)
  end

  return nil
end

typeParsers.string = function(raw)
  return raw, nil
end

typeParsers.item = function(raw)
  return raw:lower(), nil
end

typeParsers.number = function(raw, def)
  local value <const> = tonumber(raw)

  if not value then
    return nil, ('\'%s\' must be a number'):format(def.name)
  end

  return value, checkBounds(value, def)
end

typeParsers.integer = function(raw, def)
  local value <const> = math.tointeger(tonumber(raw))

  if not value then
    return nil, ('\'%s\' must be a whole number'):format(def.name)
  end

  return value, checkBounds(value, def)
end

typeParsers.boolean = function(raw, def)
  local value <const> = BOOLEAN_VALUES[raw:lower()]

  if value == nil then
    return nil, ('\'%s\' must be true or false'):format(def.name)
  end

  return value, nil
end

typeParsers.player = function(raw, def, src)
  if raw == 'me' then
    if src == CONSOLE_SOURCE then
      return nil, ('\'%s\' cannot be \'me\' from the console'):format(def.name)
    end

    return src, nil
  end

  local id <const> = math.tointeger(tonumber(raw))

  if not id or id <= 0 then
    return nil, ('\'%s\' must be a player id or \'me\''):format(def.name)
  end

  if not GetPlayerName(tostring(id)) then
    return nil, ('player %d is not online'):format(id)
  end

  return id, nil
end

typeParsers.duration = function(raw, def)
  local amount <const>, unit <const> = raw:lower():match(DURATION_PATTERN)

  if not amount then
    return nil, ('\'%s\' must be a duration like 30s, 15m, 2h or 7d'):format(def.name)
  end

  local value <const> = tonumber(amount) * DURATION_UNITS[unit]

  return value, checkBounds(value, def)
end

typeParsers.merge = function(raw, def, src, rawArgs, index)
  local merged <const> = table.concat(rawArgs, ' ', index)

  if merged == '' then
    return nil, ('\'%s\' is required'):format(def.name)
  end

  return merged, nil
end

---Checks a parsed value against the choices declared on an argument definition.
---@param value any The parsed value.
---@param def table The argument definition.
---@return string? error
local function checkChoices(value, def)
  if type(def.choices) ~= 'table' then
    return nil
  end

  for _, choice in ipairs(def.choices) do
    if choice == value then
      return nil
    end
  end

  return ('\'%s\' must be one of: %s'):format(def.name, table.concat(def.choices, ', '))
end

---Parses and validates the raw arguments of a command invocation.
---@param def table The command definition.
---@param src number The caller's server id.
---@param rawArgs string[] The raw argument strings.
---@return table? args The parsed arguments indexed by name, or nil on error.
---@return string? error
local function parseArguments(def, src, rawArgs)
  local parsed <const> = {}

  for index = 1, #def.arguments do
    local argument <const> = def.arguments[index]
    local raw <const> = rawArgs[index]

    if not raw or raw == '' then
      if not argument.optional then
        return nil, ('missing \'%s\' — usage: %s'):format(argument.name, def.usage)
      end

      parsed[argument.name] = argument.default
    else
      local ok <const>, value, parseError = pcall(typeParsers[argument.type], raw, argument, src, rawArgs, index)

      if not ok then
        return nil, ('failed to parse \'%s\''):format(argument.name)
      end

      if parseError then
        return nil, parseError
      end

      local choiceError <const> = checkChoices(value, argument)

      if choiceError then
        return nil, choiceError
      end

      if _SikuInternal.IsCallable(argument.validate) then
        local validOk <const>, valid, validError = pcall(argument.validate, value, src)

        if not validOk or not valid then
          return nil, validError or ('\'%s\' is invalid'):format(argument.name)
        end
      end

      parsed[argument.name] = value
    end

    if argument.type == 'merge' then
      break
    end
  end

  return parsed, nil
end

---Runs a command invocation through console, permission, cooldown and argument checks.
---@param def table The command definition.
---@param src number The caller's server id, or 0 for the console.
---@param rawArgs string[] The raw argument strings.
---@return nil
local function executeCommand(def, src, rawArgs)
  if src == CONSOLE_SOURCE and not def.allowConsole then
    Siku.print.warn(('/%s cannot be executed from the console'):format(def.name))
    return
  end

  if def.permission and src ~= CONSOLE_SOURCE and not hasCommandPermission(src, def.permission) then
    Siku.print.warn(('Player %d attempted /%s without permission %q'):format(src, def.name, def.permission))
    reportError(src, def.name, 'you are not allowed to use this command')
    return
  end

  if def.cooldown > 0 and src ~= CONSOLE_SOURCE then
    local key <const> = COOLDOWN_KEY_FORMAT:format(src, def.name)
    local lastUsed <const> = cooldowns[key]
    local time <const> = GetGameTimer()

    if lastUsed and time - lastUsed < def.cooldown then
      return
    end

    cooldowns[key] = time
  end

  local args <const>, argError = parseArguments(def, src, rawArgs)

  if not args then
    reportError(src, def.name, argError)
    return
  end

  local ok <const>, err = pcall(def.callback, src, args, rawArgs)

  if not ok then
    Siku.print.error(('/%s (from %q) threw an error: %s'):format(def.name, def.resource, tostring(err)))
  end
end

---Binds a name to the native command system once; the handler resolves the
---definition at call time so unregistered names silently stop responding.
---@param name string The command name.
---@return nil
local function bindNative(name)
  if nativeNames[name] then
    return
  end

  nativeNames[name] = true

  RegisterCommand(name, function(src, rawArgs)
    local def <const> = commands[name]

    if def then
      executeCommand(def, src, rawArgs)
    end
  end, false)
end

---Builds the usage string of a command from its argument definitions.
---@param primary string The primary command name.
---@param argumentDefs table[] The argument definitions.
---@return string usage
local function buildUsage(primary, argumentDefs)
  local parts <const> = { ('/%s'):format(primary) }

  for index = 1, #argumentDefs do
    local argument <const> = argumentDefs[index]
    parts[#parts + 1] = argument.optional and ('[%s]'):format(argument.name) or ('<%s>'):format(argument.name)
  end

  return table.concat(parts, ' ')
end

---Builds the chat suggestion of a command from its definition.
---@param primary string The primary command name.
---@param description string The command description.
---@param argumentDefs table[] The argument definitions.
---@return table suggestion
local function buildSuggestion(primary, description, argumentDefs)
  local params <const> = {}

  for index = 1, #argumentDefs do
    local argument <const> = argumentDefs[index]
    params[index] = {
      name = argument.name,
      description = argument.help or '',
      optional = argument.optional == true,
    }
  end

  return {
    name = primary,
    description = description,
    params = params,
  }
end

---Validates and normalizes the argument definitions of a command.
---@param primary string The primary command name.
---@param arguments any The raw argument definitions.
---@return table[]? normalized The normalized definitions, or nil on error.
local function normalizeArguments(primary, arguments)
  if arguments == nil then
    return {}
  end

  if type(arguments) ~= 'table' then
    Siku.print.error(('RegisterCommand %q: arguments must be a table'):format(primary))
    return nil
  end

  local normalized <const> = {}

  for index = 1, #arguments do
    local argument <const> = arguments[index]

    if type(argument) ~= 'table' or type(argument.name) ~= 'string' or #argument.name == 0 then
      Siku.print.error(('RegisterCommand %q: argument #%d must declare a name'):format(primary, index))
      return nil
    end

    local argType <const> = argument.type or 'string'

    if not typeParsers[argType] then
      Siku.print.error(('RegisterCommand %q: unknown argument type %q'):format(primary, tostring(argType)))
      return nil
    end

    if argType == 'merge' and index ~= #arguments then
      Siku.print.error(('RegisterCommand %q: a merge argument must be last'):format(primary))
      return nil
    end

    normalized[index] = {
      name = argument.name,
      type = argType,
      optional = argument.optional == true,
      default = argument.default,
      help = type(argument.help) == 'string' and argument.help or nil,
      min = type(argument.min) == 'number' and argument.min or nil,
      max = type(argument.max) == 'number' and argument.max or nil,
      choices = type(argument.choices) == 'table' and argument.choices or nil,
      validate = _SikuInternal.IsCallable(argument.validate) and argument.validate or nil,
    }
  end

  return normalized
end

---Registers a server command with typed arguments, permission, cooldown and chat suggestion.
---The handler is invoked with (source, args, rawArgs) where args is indexed by argument name.
---Argument types: string, number, integer, boolean, player (id or 'me'), duration (30s/15m/2h/7d),
---item, merge (rest of the line, must be last) — extendable via Siku.RegisterCommandType.
---@param name string|string[] The command name, or a list whose first entry is the primary name and the rest aliases.
---@param callback function The command handler.
---@param options? table Options: permission, allowConsole, cooldown (ms), description, arguments.
---@return boolean registered
function Siku.RegisterCommand(name, callback, options)
  local names <const> = type(name) == 'string' and { name } or name

  if type(names) ~= 'table' or #names == 0 then
    Siku.print.error('RegisterCommand: name must be a string or a list of names')
    return false
  end

  for index = 1, #names do
    if type(names[index]) ~= 'string' or not names[index]:match(COMMAND_NAME_PATTERN) then
      Siku.print.error(('RegisterCommand: invalid name %q'):format(tostring(names[index])))
      return false
    end
  end

  if not _SikuInternal.IsCallable(callback) then
    Siku.print.error(('RegisterCommand %q: callback must be a function'):format(names[1]))
    return false
  end

  if options ~= nil and type(options) ~= 'table' then
    Siku.print.error(('RegisterCommand %q: options must be a table'):format(names[1]))
    return false
  end

  local primary <const> = names[1]
  local opts <const> = options or {}
  local arguments <const> = normalizeArguments(primary, opts.arguments)

  if not arguments then
    return false
  end

  local description <const> = type(opts.description) == 'string' and opts.description or ''

  local def <const> = {
    name = primary,
    aliases = {},
    callback = callback,
    permission = type(opts.permission) == 'string' and opts.permission or nil,
    allowConsole = opts.allowConsole == true,
    cooldown = type(opts.cooldown) == 'number' and opts.cooldown or 0,
    description = description,
    arguments = arguments,
    usage = buildUsage(primary, arguments),
    suggestion = buildSuggestion(primary, description, arguments),
    resource = GetInvokingResource() or GetCurrentResourceName(),
  }

  for index = 2, #names do
    def.aliases[#def.aliases + 1] = names[index]
  end

  for index = 1, #names do
    local existing <const> = commands[names[index]]

    if existing then
      Siku.print.warn(('/%s from %q overrides the definition from %q'):format(names[index], def.resource, existing.resource))
    end

    commands[names[index]] = def
    bindNative(names[index])
  end

  pushSuggestion(def)

  return true
end

---Unregisters a command and its aliases by any of its names.
---@param name string The command name or one of its aliases.
---@return boolean removed Whether a command was found and removed.
function Siku.UnregisterCommand(name)
  local def <const> = commands[name]

  if not def then
    return false
  end

  commands[def.name] = nil

  for index = 1, #def.aliases do
    commands[def.aliases[index]] = nil
  end

  dropSuggestion(def.name)

  return true
end

---Checks whether a command name or alias is registered.
---@param name string The command name.
---@return boolean registered
function Siku.IsCommandRegistered(name)
  return commands[name] ~= nil
end

---Collects the chat suggestions of every command the given player is allowed to use.
---@param src number The player's server id.
---@return table[] suggestions
function Siku.GetCommandSuggestions(src)
  local result <const> = {}
  local seen <const> = {}

  for _, def in pairs(commands) do
    if not seen[def] and (not def.permission or hasCommandPermission(src, def.permission)) then
      seen[def] = true
      result[#result + 1] = def.suggestion
    end
  end

  return result
end

---Pushes to a player every command suggestion they are allowed to use.
---Permission-gated commands are filtered out while no character is active,
---so call this once the character and its roles are loaded, and again
---whenever those roles change.
---@param src number The player's server id.
---@return nil
function Siku.RefreshCommandSuggestions(src)
  if type(src) ~= 'number' or not isChatReady() then
    return
  end

  for _, suggestion in ipairs(Siku.GetCommandSuggestions(src)) do
    pcall(function()
      exports[CHAT_RESOURCE]:AddSuggestion(src, suggestion)
    end)
  end
end

---Registers a custom argument type parser, overriding any existing one.
---The parser is invoked with (raw, argumentDef, src, rawArgs, index) and must
---return the parsed value, or nil and an error message.
---@param typeName string The argument type name.
---@param parser function The parser function.
---@return boolean registered
function Siku.RegisterCommandType(typeName, parser)
  if type(typeName) ~= 'string' or #typeName == 0 then
    Siku.print.error('RegisterCommandType: typeName must be a non-empty string')
    return false
  end

  if not _SikuInternal.IsCallable(parser) then
    Siku.print.error(('RegisterCommandType %q: parser must be a function'):format(typeName))
    return false
  end

  if typeParsers[typeName] then
    Siku.print.warn(('Command type %q overridden'):format(typeName))
  end

  typeParsers[typeName] = parser

  return true
end

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then
    return
  end

  local owned <const> = {}
  local seen <const> = {}

  for _, def in pairs(commands) do
    if not seen[def] and def.resource == resourceName then
      seen[def] = true
      owned[#owned + 1] = def.name
    end
  end

  for index = 1, #owned do
    Siku.UnregisterCommand(owned[index])
  end
end)

AddEventHandler('playerDropped', function()
  local prefix <const> = ('%d:'):format(source)

  for key in pairs(cooldowns) do
    if key:sub(1, #prefix) == prefix then
      cooldowns[key] = nil
    end
  end
end)
