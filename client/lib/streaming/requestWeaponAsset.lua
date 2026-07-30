--- Request and load a weapon asset into memory, blocking until it loads.
---@param weapon string|number The weapon name or hash.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return number hash The loaded weapon asset hash.
function Siku.RequestWeaponAsset(weapon, timeout)
  local hash <const> = type(weapon) == 'string' and GetHashKey(weapon) or weapon

  return _SikuInternal.StreamingRequest(
    function() RequestWeaponAsset(hash, 31, 0) end,
    function() return HasWeaponAssetLoaded(hash) end,
    'weaponAsset', hash, timeout
  ) --[[@as number]]
end
