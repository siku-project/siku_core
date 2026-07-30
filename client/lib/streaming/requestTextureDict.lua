--- Request and load a texture dictionary into memory, blocking until it loads.
---@param dict string The texture dictionary name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string dict The loaded texture dictionary name.
function Siku.RequestTextureDict(dict, timeout)
  return _SikuInternal.StreamingRequest(
    function() RequestStreamedTextureDict(dict, false) end,
    function() return HasStreamedTextureDictLoaded(dict) end,
    'textureDict', dict, timeout
  ) --[[@as string]]
end
