--- Request and load a particle effects asset into memory, blocking until it loads.
---@param fxName string The particle effect asset name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string fxName The loaded particle effect asset name.
function Siku.RequestPtfxAsset(fxName, timeout)
  return _SikuInternal.StreamingRequest(
    function() RequestNamedPtfxAsset(fxName) end,
    function() return HasNamedPtfxAssetLoaded(fxName) end,
    'ptfxAsset', fxName, timeout
  ) --[[@as string]]
end
