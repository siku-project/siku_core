--- Request and load a scaleform movie into memory, blocking until it loads.
---@param name string The scaleform movie name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return number handle The loaded scaleform movie handle.
function Siku.RequestScaleformMovie(name, timeout)
  local handle <const> = RequestScaleformMovie(name)

  return _SikuInternal.StreamingRequest(
    function() RequestScaleformMovie(name) end,
    function() return HasScaleformMovieLoaded(handle) end,
    'scaleformMovie', handle, timeout
  ) --[[@as number]]
end
