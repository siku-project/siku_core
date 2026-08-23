local DEFAULT_TIMEOUT <const> = 10000
local WEAPON_ASSET_FLAGS <const> = 31

--- Request a streaming asset and block until it loads or the wait times out.
---@param request function Starts loading the asset.
---@param hasLoaded function Returns whether the asset is loaded.
---@param assetType string The asset type, used in the timeout message.
---@param asset string|number The asset identifier returned once loaded.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string|number asset The loaded asset identifier.
local function streamingRequest(request, hasLoaded, assetType, asset, timeout)
  if hasLoaded() then
    return asset
  end

  request()

  return Siku.waitFor(
    function()
      if hasLoaded() then
        return asset
      end
    end,
    ("Failed to load %s '%s'"):format(assetType, tostring(asset)),
    timeout or DEFAULT_TIMEOUT
  )
end

--- Request and load an animation dictionary into memory, blocking until it loads.
---@param dict string The animation dictionary name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string dict The loaded animation dictionary name.
local function requestAnimDict(dict, timeout)
  return streamingRequest(
    function() RequestAnimDict(dict) end,
    function() return HasAnimDictLoaded(dict) end,
    'animDict', dict, timeout
  ) --[[@as string]]
end

--- Request and load an animation set into memory, blocking until it loads.
---@param animSet string The animation set name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string animSet The loaded animation set name.
local function requestAnimSet(animSet, timeout)
  return streamingRequest(
    function() RequestAnimSet(animSet) end,
    function() return HasAnimSetLoaded(animSet) end,
    'animSet', animSet, timeout
  ) --[[@as string]]
end

--- Request and load a model into memory, blocking until it loads.
---@param model string|number The model name or hash.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return number hash The loaded model hash.
local function requestModel(model, timeout)
  local hash <const> = type(model) == 'string' and GetHashKey(model) or model

  if not IsModelValid(hash) and not IsModelInCdimage(hash) then
    Siku.print.throw(("Invalid model '%s'"):format(tostring(model)))
  end

  return streamingRequest(
    function() RequestModel(hash) end,
    function() return HasModelLoaded(hash) end,
    'model', hash, timeout
  ) --[[@as number]]
end

--- Request and load a particle effects asset into memory, blocking until it loads.
---@param fxName string The particle effect asset name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string fxName The loaded particle effect asset name.
local function requestPtfxAsset(fxName, timeout)
  return streamingRequest(
    function() RequestNamedPtfxAsset(fxName) end,
    function() return HasNamedPtfxAssetLoaded(fxName) end,
    'ptfxAsset', fxName, timeout
  ) --[[@as string]]
end

--- Request and load a scaleform movie into memory, blocking until it loads.
---@param name string The scaleform movie name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return number handle The loaded scaleform movie handle.
local function requestScaleformMovie(name, timeout)
  local handle <const> = RequestScaleformMovie(name)

  return streamingRequest(
    function() RequestScaleformMovie(name) end,
    function() return HasScaleformMovieLoaded(handle) end,
    'scaleformMovie', handle, timeout
  ) --[[@as number]]
end

--- Request and load a texture dictionary into memory, blocking until it loads.
---@param dict string The texture dictionary name.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string dict The loaded texture dictionary name.
local function requestTextureDict(dict, timeout)
  return streamingRequest(
    function() RequestStreamedTextureDict(dict, false) end,
    function() return HasStreamedTextureDictLoaded(dict) end,
    'textureDict', dict, timeout
  ) --[[@as string]]
end

--- Request and load a weapon asset into memory, blocking until it loads.
---@param weapon string|number The weapon name or hash.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return number hash The loaded weapon asset hash.
local function requestWeaponAsset(weapon, timeout)
  local hash <const> = type(weapon) == 'string' and GetHashKey(weapon) or weapon

  return streamingRequest(
    function() RequestWeaponAsset(hash, WEAPON_ASSET_FLAGS, 0) end,
    function() return HasWeaponAssetLoaded(hash) end,
    'weaponAsset', hash, timeout
  ) --[[@as number]]
end

internal.request = streamingRequest

return {
  requestAnimDict = requestAnimDict,
  requestAnimSet = requestAnimSet,
  requestModel = requestModel,
  requestPtfxAsset = requestPtfxAsset,
  requestScaleformMovie = requestScaleformMovie,
  requestTextureDict = requestTextureDict,
  requestWeaponAsset = requestWeaponAsset,
}
