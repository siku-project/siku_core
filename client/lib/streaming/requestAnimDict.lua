--- Request and load an animation dictionary into memory, blocking until it loads.
---@param dict string The animation dictionary name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string dict The loaded animation dictionary name.
function Siku.RequestAnimDict(dict, timeout)
  return _SikuInternal.StreamingRequest(
    function() RequestAnimDict(dict) end,
    function() return HasAnimDictLoaded(dict) end,
    'animDict', dict, timeout
  ) --[[@as string]]
end
