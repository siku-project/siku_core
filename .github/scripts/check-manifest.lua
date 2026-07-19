local BLOCKS <const> = { 'shared_scripts', 'server_scripts', 'client_scripts', 'files' }

local declared = {}
local failures = 0

local function fail(message)
  failures = failures + 1
  io.stderr:write('  FAIL  ' .. message .. '\n')
end

local function collect(block)
  return function(entries)
    if type(entries) ~= 'table' then
      entries = { entries }
    end

    for i = 1, #entries do
      declared[#declared + 1] = { block = block, path = entries[i] }
    end
  end
end

local env = setmetatable({}, {
  __index = function() return function() end end,
  __newindex = function() end,
})

for i = 1, #BLOCKS do
  rawset(env, BLOCKS[i], collect(BLOCKS[i]))
end

local manifest <const> = io.open('fxmanifest.lua', 'r')

if not manifest then
  print('No fxmanifest.lua in this tree yet, nothing to check.')
  os.exit(0)
end

manifest:close()

local chunk <const>, compileError <const> = loadfile('fxmanifest.lua', 't', env)

if not chunk then
  io.stderr:write('fxmanifest.lua does not compile: ' .. tostring(compileError) .. '\n')
  os.exit(1)
end

local ok <const>, runError <const> = pcall(chunk)

if not ok then
  io.stderr:write('fxmanifest.lua does not run: ' .. tostring(runError) .. '\n')
  os.exit(1)
end

local function exists(path)
  local handle <const> = io.open(path, 'r')

  if not handle then
    return false
  end

  handle:close()

  return true
end

local function toPattern(glob)
  local pattern <const> = glob
    :gsub('([%.%+%-%(%)%[%]%$%^])', '%%%1')
    :gsub('%*%*/', '\0')
    :gsub('%*', '[^/]*')
    :gsub('%z', '.-')

  return '^' .. pattern .. '$'
end

local globs <const> = {}
local literals <const> = {}

for i = 1, #declared do
  local entry <const> = declared[i]

  if entry.path:sub(1, 1) == '@' then
    literals[#literals + 1] = entry
  elseif entry.path:find('%*') then
    globs[#globs + 1] = entry
  else
    literals[#literals + 1] = entry

    if not exists(entry.path) then
      fail(("%s declares '%s' which does not exist"):format(entry.block, entry.path))
    end
  end
end

for i = 1, #literals do
  local literal <const> = literals[i]

  for j = 1, #globs do
    local glob <const> = globs[j]

    if glob.block == literal.block and literal.path:match(toPattern(glob.path)) then
      fail(("'%s' is listed explicitly and also matched by '%s' in %s, so it loads twice")
        :format(literal.path, glob.path, literal.block))
    end
  end
end

local tracked <const> = {}
local pipe <const> = io.popen('git ls-files "*.lua"')

if pipe then
  for path in pipe:lines() do
    tracked[#tracked + 1] = path
  end

  pipe:close()
end

for i = 1, #tracked do
  local path <const> = tracked[i]
  local covered = path == 'fxmanifest.lua' or path:find('^%.github/')

  for j = 1, #declared do
    if declared[j].path == path then
      covered = true
      break
    end
  end

  for j = 1, #globs do
    if path:match(toPattern(globs[j].path)) then
      covered = true
      break
    end
  end

  if not covered then
    fail(("'%s' is tracked but no block of fxmanifest.lua loads it"):format(path))
  end
end

if failures > 0 then
  io.stderr:write(('\n%d manifest problem(s) found\n'):format(failures))
  os.exit(1)
end

print(('fxmanifest.lua is coherent: %d declaration(s), %d tracked Lua file(s)'):format(#declared, #tracked))
