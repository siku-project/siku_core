--- Round a number with optional decimal precision and rounding mode.
---@param value number The number to round.
---@param decimals? number The number of decimal places (default: 0).
---@param mode? string The rounding mode: 'default', 'ceil', or 'floor' (default: 'default').
---@return number result The rounded number.
function Siku.math.round(value, decimals, mode)
  local factor <const> = 10 ^ (decimals or 0)
  local scaled <const> = value * factor

  if mode == 'ceil' then return math.ceil(scaled) / factor end
  if mode == 'floor' then return math.floor(scaled) / factor end
  return math.floor(scaled + 0.5) / factor
end
