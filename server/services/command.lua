Siku.command = {}

local CONSOLE_SOURCE <const> = 0
local COOLDOWN_KEY_FORMAT <const> = '%d:%s'
local COMMAND_NAME_PATTERN <const> = '^[%w_%-]+$'
local DURATION_PATTERN <const> = '^(%d+)([smhd]?)$'
local CHAT_RESOURCE <const> = 'siku_chat'
local ERROR_NOTIFICATION_DURATION <const> = 5000
local TRACE_COMMANDS <const> = Siku.config.log.enabled ~= false and Siku.config.log.tracing ~= nil and Siku.config.log.tracing.enabled ~= false and Siku.config.log.tracing.commands ~= false

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

      if Siku.isCallable(argument.validate) then
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

---Runs a command handler inside a span when command tracing is enabled.
---@param def table The command definition.
---@param src number The caller.
---@param args table The parsed arguments.
---@param rawArgs table The raw arguments.
---@return any ... Whatever the handler returned.
local function runCommand(def, src, args, rawArgs)
  if not TRACE_COMMANDS then
    return def.callback(src, args, rawArgs)
  end

  return Siku.log.span('command /' .. def.name, def.callback, {
    kind = 'server',
    auto = true,
    attributes = { ['command.name'] = def.name, ['command.resource'] = def.resource, ['command.source'] = src },
  }, src, args, rawArgs)
end

---Runs a command invocation through console, permission, cooldown and argument checks.
---@param def table The command definition.
---@param src number The caller's server id, or 0 for the console.
---@param rawArgs string[] The raw argument strings.
---@return nil
local function executeCommand(def, src, rawArgs)
  if src == CONSOLE_SOURCE and not def.allowConsole then
    Siku.print.warn(('/%s: cannot be executed from the console'):format(def.name))
    Siku.log.warn('command.rejected', ('/%s %s: cannot be executed from the console'):format(def.name, table.concat(rawArgs, ' ')), {
      command = def.name,
      resource = def.resource,
      arguments = rawArgs,
      reason = 'console',
      permission = def.permission,
      console = true,
    }, { outcome = 'denied' })
    return
  end

  if def.permission and src ~= CONSOLE_SOURCE and not hasCommandPermission(src, def.permission) then
    local entities <const> = { { type = 'player', id = src, role = 'actor' } }

    for index = 1, #def.arguments do
      local argument <const> = def.arguments[index]

      if argument.type == 'player' and rawArgs[index] then
        local ok <const>, target <const> = pcall(typeParsers.player, rawArgs[index], argument, src)

        if ok and target and target ~= src then
          entities[#entities + 1] = { type = 'player', id = target, role = 'target' }
        end
      end
    end

    Siku.log.warn('command.rejected', ('Tried /%s %s without permission %s'):format(def.name, table.concat(rawArgs, ' '), def.permission), {
      command = def.name,
      resource = def.resource,
      arguments = rawArgs,
      reason = 'permission',
      permission = def.permission,
      console = false,
    }, { outcome = 'denied', source = src, entities = entities })
    Siku.notification.show(src, {
      type = 'error',
      title = ('/%s'):format(def.name),
      description = 'you are not allowed to use this command',
      duration = ERROR_NOTIFICATION_DURATION,
    })
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
    local entities <const> = {}

    if src ~= CONSOLE_SOURCE then
      entities[#entities + 1] = { type = 'player', id = src, role = 'actor' }
    end

    for index = 1, #def.arguments do
      local argument <const> = def.arguments[index]

      if argument.type == 'player' and rawArgs[index] then
        local ok <const>, target <const> = pcall(typeParsers.player, rawArgs[index], argument, src)

        if ok and target and target ~= src then
          entities[#entities + 1] = { type = 'player', id = target, role = 'target' }
        end
      end
    end

    Siku.log.warn('command.rejected', ('/%s %s: %s'):format(def.name, table.concat(rawArgs, ' '), argError), {
      command = def.name,
      resource = def.resource,
      arguments = rawArgs,
      reason = 'arguments',
      permission = def.permission,
      console = src == CONSOLE_SOURCE,
    }, {
      outcome = 'denied',
      source = src ~= CONSOLE_SOURCE and src or nil,
      entities = #entities > 0 and entities or nil,
    })

    if src == CONSOLE_SOURCE then
      Siku.print.warn(('/%s: %s'):format(def.name, argError))
      return
    end

    Siku.notification.show(src, {
      type = 'error',
      title = ('/%s'):format(def.name),
      description = argError,
      duration = ERROR_NOTIFICATION_DURATION,
    })
    return
  end

  local ok <const>, err = pcall(runCommand, def, src, args, rawArgs)

  if not ok then
    Siku.log.error('command.failed', ('/%s %s threw an error: %s'):format(def.name, table.concat(rawArgs, ' '), tostring(err)), {
      command = def.name,
      resource = def.resource,
      arguments = rawArgs,
      error = tostring(err),
      console = src == CONSOLE_SOURCE,
    }, {
      outcome = 'failure',
      source = src ~= CONSOLE_SOURCE and src or nil,
      entities = src ~= CONSOLE_SOURCE
        and { { type = 'player', id = src, role = 'actor' }, { type = 'resource', id = def.resource, role = 'subject', label = def.resource } }
        or { { type = 'resource', id = def.resource, role = 'subject', label = def.resource } },
    })
  end

  if def.permission then
    Siku.log.audit('command.executed', {
      source = src ~= CONSOLE_SOURCE and src or nil,
      outcome = ok and 'success' or 'failure',
      message = ('/%s %s'):format(def.name, table.concat(rawArgs, ' ')),
      data = { command = def.name, resource = def.resource, arguments = rawArgs, console = src == CONSOLE_SOURCE },
      entities = src ~= CONSOLE_SOURCE and { { type = 'player', id = src, role = 'actor' } } or nil,
    })
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
local function normalizeArguments(primary, arguments, resource)
  if arguments == nil then
    return {}
  end

  if type(arguments) ~= 'table' then
    Siku.log.error('command.definition_invalid', ('command.register %q: arguments must be a table'):format(primary), {
      command = primary,
      resource = resource,
      reason = 'arguments_not_table',
      got = type(arguments),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return nil
  end

  local normalized <const> = {}

  for index = 1, #arguments do
    local argument <const> = arguments[index]

    if type(argument) ~= 'table' or type(argument.name) ~= 'string' or #argument.name == 0 then
      Siku.log.error('command.definition_invalid', ('command.register %q: argument #%d must declare a name'):format(primary, index), {
        command = primary,
        resource = resource,
        reason = 'argument_unnamed',
        index = index,
      }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
      return nil
    end

    local argType <const> = argument.type or 'string'

    if not typeParsers[argType] then
      Siku.log.error('command.definition_invalid', ('command.register %q: unknown argument type %q'):format(primary, tostring(argType)), {
        command = primary,
        resource = resource,
        reason = 'argument_type_unknown',
        index = index,
        argument = argument.name,
        argumentType = tostring(argType),
      }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
      return nil
    end

    if argType == 'merge' and index ~= #arguments then
      Siku.log.error('command.definition_invalid', ('command.register %q: a merge argument must be last'):format(primary), {
        command = primary,
        resource = resource,
        reason = 'merge_not_last',
        index = index,
        argument = argument.name,
      }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
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
      validate = Siku.isCallable(argument.validate) and argument.validate or nil,
    }
  end

  return normalized
end

---Registers a server command with typed arguments, permission, cooldown and chat suggestion.
---The handler is invoked with (source, args, rawArgs) where args is indexed by argument name.
---Argument types: string, number, integer, boolean, player (id or 'me'), duration (30s/15m/2h/7d),
---item, merge (rest of the line, must be last) — extendable via Siku.command.registerType.
---@param name string|string[] The command name, or a list whose first entry is the primary name and the rest aliases.
---@param callback function The command handler.
---@param options? table Options: permission, allowConsole, cooldown (ms), description, arguments.
---@return boolean registered
function Siku.command.register(name, callback, options)
  local names <const> = type(name) == 'string' and { name } or name
  local resource <const> = GetInvokingResource() or GetCurrentResourceName()

  if type(names) ~= 'table' or #names == 0 then
    Siku.log.error('command.definition_invalid', 'command.register: name must be a string or a list of names', {
      resource = resource,
      reason = 'name_not_string',
      got = type(name),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  for index = 1, #names do
    if type(names[index]) ~= 'string' or not names[index]:match(COMMAND_NAME_PATTERN) then
      Siku.log.error('command.definition_invalid', ('command.register: invalid name %q'):format(tostring(names[index])), {
        command = tostring(names[index]),
        resource = resource,
        reason = 'name_invalid',
        index = index,
      }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
      return false
    end
  end

  if not Siku.isCallable(callback) then
    Siku.log.error('command.definition_invalid', ('command.register %q: callback must be a function'):format(names[1]), {
      command = names[1],
      resource = resource,
      reason = 'callback_not_function',
      got = type(callback),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  if options ~= nil and type(options) ~= 'table' then
    Siku.log.error('command.definition_invalid', ('command.register %q: options must be a table'):format(names[1]), {
      command = names[1],
      resource = resource,
      reason = 'options_not_table',
      got = type(options),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  local primary <const> = names[1]
  local opts <const> = options or {}
  local arguments <const> = normalizeArguments(primary, opts.arguments, resource)

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
    resource = resource,
  }

  for index = 2, #names do
    def.aliases[#def.aliases + 1] = names[index]
  end

  for index = 1, #names do
    local existing <const> = commands[names[index]]

    if existing then
      Siku.print.warn(('/%s from %q overrides the definition from %q'):format(names[index], def.resource, existing.resource))
      Siku.log.warn('command.overridden', ('/%s from %q overrides the definition from %q'):format(names[index], def.resource, existing.resource), {
        command = names[index],
        resource = def.resource,
        previous = existing.resource,
        reason = 'command',
      }, { entities = { { type = 'resource', id = def.resource, role = 'subject', label = def.resource } } })
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
function Siku.command.unregister(name)
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
function Siku.command.isRegistered(name)
  return commands[name] ~= nil
end

---Collects the chat suggestions of every command the given player is allowed to use.
---@param src number The player's server id.
---@return table[] suggestions
function Siku.command.getSuggestions(src)
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
function Siku.command.refreshSuggestions(src)
  if type(src) ~= 'number' or not isChatReady() then
    return
  end

  for _, suggestion in ipairs(Siku.command.getSuggestions(src)) do
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
function Siku.command.registerType(typeName, parser)
  local resource <const> = GetInvokingResource() or GetCurrentResourceName()

  if type(typeName) ~= 'string' or #typeName == 0 then
    Siku.log.error('command.definition_invalid', 'command.registerType: typeName must be a non-empty string', {
      resource = resource,
      reason = 'type_name_invalid',
      got = type(typeName),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  if not Siku.isCallable(parser) then
    Siku.log.error('command.definition_invalid', ('command.registerType %q: parser must be a function'):format(typeName), {
      resource = resource,
      reason = 'type_parser_not_function',
      argumentType = typeName,
      got = type(parser),
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
    return false
  end

  if typeParsers[typeName] then
    Siku.print.warn(('Command type %q overridden by %q'):format(typeName, resource))
    Siku.log.warn('command.overridden', ('Command type %q overridden by %q'):format(typeName, resource), {
      argumentType = typeName,
      resource = resource,
      reason = 'type',
    }, { entities = { { type = 'resource', id = resource, role = 'subject', label = resource } } })
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
    Siku.command.unregister(owned[index])
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
