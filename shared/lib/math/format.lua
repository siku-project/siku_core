--- Insert a separator every 3 digits in the integer part of a number string.
---@param intPart string The integer part as a string.
---@param sep string The separator to insert.
---@return string formatted The formatted integer string.
local function insertThousands(intPart, sep)
  local result = intPart
  local pos = #result - 3

  while pos > 0 do
    result = result:sub(1, pos) .. sep .. result:sub(pos + 1)
    pos = pos - 3
  end

  return result
end

--- Format a number with space-separated thousands.
---@param value number The number to format.
---@return string formatted The formatted number string.
function Siku.math.formatNumber(value)
  local sign <const> = value < 0 and '-' or ''
  local intPart <const>, decPart <const> = tostring(math.abs(value)):match('([^%.]+)%.?(.*)')
  local formatted <const> = insertThousands(intPart, ' ')

  if decPart ~= '' then
    return sign .. formatted .. '.' .. decPart
  end

  return sign .. formatted
end

--- Format a number as currency with two decimal places and a symbol.
---@param value number The amount to format.
---@param symbol string The currency symbol (e.g. '$', '€').
---@return string formatted The formatted currency string.
function Siku.math.formatCurrency(value, symbol)
  local sign <const> = value < 0 and '-' or ''
  local fixed <const> = string.format('%.2f', math.abs(value))
  local intPart <const>, decPart <const> = fixed:match('([^%.]+)%.?(.*)')
  local formatted <const> = insertThousands(intPart, ' ')

  return sign .. formatted .. '.' .. decPart .. ' ' .. symbol
end

--- Format a number with a custom thousands separator.
---@param value number The number to format.
---@param separator string The separator character (e.g. ',', '.', ' ').
---@return string formatted The formatted number string.
function Siku.math.formatWithSeparator(value, separator)
  if separator == '.' and math.floor(value) ~= value then
    Siku.print.warn(('formatWithSeparator: using "." as separator on a decimal number (%s) — may be ambiguous'):format(value))
  end

  local sign <const> = value < 0 and '-' or ''
  local intPart <const>, decPart <const> = tostring(math.abs(value)):match('([^%.]+)%.?(.*)')
  local formatted <const> = insertThousands(intPart, separator)

  if decPart ~= '' then
    return sign .. formatted .. '.' .. decPart
  end

  return sign .. formatted
end
