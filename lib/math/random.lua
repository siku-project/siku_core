local CHARS_ALPHANUM <const> = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
local CHARS_ALPHA <const> = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
local CHARS_NUMERIC <const> = '0123456789'
local CHARS_HEX <const> = '0123456789abcdef'
local PI2 <const> = math.pi * 2
local UUID_VARIANT_FIRST <const> = 9
local UUID_VARIANT_LAST <const> = 12
local UPPERCASE_BASE <const> = 65
local LOWERCASE_BASE <const> = 97
local ALPHABET_SIZE <const> = 26

local mathLib <const> = {}

--- Generate a random string from a charset.
---@param charset string The character set to pick from.
---@param length number The desired string length.
---@return string result The random string.
local function randomFromCharset(charset, length)
  local len <const> = #charset
  local result <const> = {}

  for i = 1, length do
    local idx <const> = math.random(1, len)
    result[i] = charset:sub(idx, idx)
  end

  return table.concat(result)
end

--- Create a seeded pseudo-random number generator (mulberry32).
---@param seed number The seed value.
---@return function generator A function that returns a random float between 0 and 1 on each call.
function mathLib.createSeed(seed)
  local s = seed

  return function()
    s = s + 0x6D2B79F5
    local t = s
    t = ((t ~ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
    t = (t ~ (t + ((t ~ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
    return ((t ~ (t >> 14)) & 0xFFFFFFFF) / 4294967296
  end
end

--- Generate a random integer between min and max (inclusive).
---@param min number The minimum value.
---@param max number The maximum value.
---@return number result The random integer.
function mathLib.randomInt(min, max)
  return math.random(min, max)
end

--- Generate a random float between min and max.
---@param min number The minimum value.
---@param max number The maximum value.
---@return number result The random float.
function mathLib.randomFloat(min, max)
  return math.random() * (max - min) + min
end

--- Generate a random boolean.
---@return boolean result True or false with 50% chance each.
function mathLib.randomBool()
  return math.random() < 0.5
end

--- Pick a random element from an array.
---@param array table The array to pick from.
---@return any result A random element.
function mathLib.randomChoice(array)
  return array[math.random(1, #array)]
end

--- Pick multiple random elements from an array.
---@param array table The array to pick from.
---@param count number The number of elements to pick.
---@param withReplacement? boolean Allow picking the same element multiple times (default: false).
---@return table results The selected elements.
function mathLib.randomChoices(array, count, withReplacement)
  if not withReplacement and count > #array then
    Siku.print.throw(('count (%d) exceeds array length (%d)'):format(count, #array))
  end

  local results <const> = {}

  if withReplacement then
    for i = 1, count do
      results[i] = array[math.random(1, #array)]
    end

    return results
  end

  local copy <const> = {}

  for i = 1, #array do
    copy[i] = array[i]
  end

  for i = 1, count do
    local idx <const> = math.random(1, #copy - i + 1)
    results[i] = copy[idx]
    copy[idx] = copy[#copy - i + 1]
  end

  return results
end

--- Pick a random element from a weighted list.
---@param options table A list of { value = any, weight = number }.
---@return any result The selected value.
function mathLib.randomWeighted(options)
  local total = 0

  for i = 1, #options do
    total = total + options[i].weight
  end

  local threshold = math.random() * total

  for i = 1, #options do
    threshold = threshold - options[i].weight

    if threshold <= 0 then
      return options[i].value
    end
  end

  return options[#options].value
end

--- Shuffle an array (Fisher-Yates) and return a new shuffled copy.
---@param array table The array to shuffle.
---@return table result A new shuffled array.
function mathLib.shuffleArray(array)
  local result <const> = {}

  for i = 1, #array do
    result[i] = array[i]
  end

  for i = #result, 2, -1 do
    local j <const> = math.random(1, i)
    result[i], result[j] = result[j], result[i]
  end

  return result
end

--- Generate a random point inside a circle.
---@param center vector2 The center of the circle.
---@param radius number The radius of the circle.
---@return vector2 point A random point inside the circle.
function mathLib.randomPointInCircle(center, radius)
  local angle <const> = math.random() * PI2
  local r <const> = radius * math.sqrt(math.random())

  return vector2(
    center.x + r * math.cos(angle),
    center.y + r * math.sin(angle)
  )
end

--- Generate a random point on the edge of a circle.
---@param center vector2 The center of the circle.
---@param radius number The radius of the circle.
---@return vector2 point A random point on the circle edge.
function mathLib.randomPointOnCircleEdge(center, radius)
  local angle <const> = math.random() * PI2

  return vector2(
    center.x + radius * math.cos(angle),
    center.y + radius * math.sin(angle)
  )
end

--- Generate a random UUID v4.
---@return string uuid The generated UUID.
function mathLib.randomUUIDv4()
  local variant <const> = math.random(UUID_VARIANT_FIRST, UUID_VARIANT_LAST)

  return string.format('%s-%s-4%s-%s%s-%s',
    randomFromCharset(CHARS_HEX, 8),
    randomFromCharset(CHARS_HEX, 4),
    randomFromCharset(CHARS_HEX, 3),
    CHARS_HEX:sub(variant, variant),
    randomFromCharset(CHARS_HEX, 3),
    randomFromCharset(CHARS_HEX, 12)
  )
end

--- Generate a random UUID v7 (timestamp-based).
---@return string uuid The generated UUID.
function mathLib.randomUUIDv7()
  local now <const> = GetGameTimer()
  local msHigh <const> = now // 0x10000
  local msLow <const> = now & 0xFFFF
  local randA <const> = math.random(0, 0xFFF)
  local randBHigh <const> = math.random(0, 0x3FFF) | 0x8000

  return string.format('%08x-%04x-%04x-%04x-%s',
    msHigh,
    msLow,
    0x7000 | randA,
    randBHigh,
    randomFromCharset(CHARS_HEX, 12)
  )
end

--- Generate a random alphanumeric string.
---@param length number The desired string length.
---@return string result The random string.
function mathLib.randomAlphanumeric(length)
  return randomFromCharset(CHARS_ALPHANUM, length)
end

--- Generate a random alphabetic string (letters only).
---@param length number The desired string length.
---@return string result The random string.
function mathLib.randomAlphabetic(length)
  return randomFromCharset(CHARS_ALPHA, length)
end

--- Generate a random numeric string (digits only).
---@param length number The desired string length.
---@return string result The random string.
function mathLib.randomNumeric(length)
  return randomFromCharset(CHARS_NUMERIC, length)
end

--- Generate a random hex string.
---@param length number The desired string length.
---@return string result The random string.
function mathLib.randomHex(length)
  return randomFromCharset(CHARS_HEX, length)
end

--- Generate a random RGB color.
---@return table color { r, g, b } with values 0-255.
function mathLib.randomRGB()
  return {
    r = math.random(0, 255),
    g = math.random(0, 255),
    b = math.random(0, 255),
  }
end

--- Generate a random RGBA color.
---@return table color { r, g, b, a } with RGB 0-255 and alpha 0-1.
function mathLib.randomRGBA()
  return {
    r = math.random(0, 255),
    g = math.random(0, 255),
    b = math.random(0, 255),
    a = math.random(),
  }
end

--- Generate a random percentage (0-100).
---@return number percentage A random float between 0 and 100.
function mathLib.randomPercentage()
  return math.random() * 100
end

--- Generate a random angle in degrees (0-360).
---@return number angle A random float between 0 and 360.
function mathLib.randomAngle()
  return math.random() * 360
end

--- Generate a random angle in radians (0 to 2*PI).
---@return number angle A random float between 0 and 2*PI.
function mathLib.randomRadianAngle()
  return math.random() * PI2
end

--- Generate a random sign (-1 or 1).
---@return number sign Either -1 or 1.
function mathLib.randomSign()
  return math.random() < 0.5 and -1 or 1
end

--- Generate one character for a pattern token.
---@param char string The pattern character.
---@return string? result The generated character, or nil when the character is not a token.
local function patternToken(char)
  if char == '1' then
    return tostring(math.random(0, 9))
  end

  if char == 'A' then
    return string.char(UPPERCASE_BASE + math.random(0, ALPHABET_SIZE - 1))
  end

  if char == 'a' then
    return string.char(LOWERCASE_BASE + math.random(0, ALPHABET_SIZE - 1))
  end

  if char == '.' then
    if math.random() < 0.5 then
      return tostring(math.random(0, 9))
    end

    return string.char(UPPERCASE_BASE + math.random(0, ALPHABET_SIZE - 1))
  end

  return nil
end

--- Generate a string from a pattern where special chars are replaced randomly.
--- Pattern chars: '1' = digit, 'A' = uppercase letter, 'a' = lowercase letter, '.' = digit or uppercase letter.
--- Use '^' to escape the next character (e.g. '^A' outputs literal 'A').
---@param pattern string The pattern string.
---@return string result The generated string.
function mathLib.randomPattern(pattern)
  local result <const> = {}
  local escape = false

  for i = 1, #pattern do
    local char <const> = pattern:sub(i, i)

    if escape then
      result[#result + 1] = char
      escape = false
    elseif char == '^' then
      escape = true
    else
      result[#result + 1] = patternToken(char) or char
    end
  end

  return table.concat(result)
end

return mathLib
