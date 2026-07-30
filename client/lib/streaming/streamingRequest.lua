local DEFAULT_TIMEOUT <const> = 10000

--- Request a streaming asset and block until it loads or the wait times out.
---@param request function Starts loading the asset.
---@param hasLoaded function Returns whether the asset is loaded.
---@param assetType string The asset type, used in the timeout message.
---@param asset string|number The asset identifier returned once loaded.
---@param timeout? number Maximum time in ms to wait (default 10000).
---@return string|number asset The loaded asset identifier.
function _SikuInternal.StreamingRequest(request, hasLoaded, assetType, asset, timeout)
  if hasLoaded() then
    return asset
  end

  request()

  return Siku.WaitFor(
    function()
      if hasLoaded() then
        return asset
      end
    end,
    ("Failed to load %s '%s'"):format(assetType, tostring(asset)),
    timeout or DEFAULT_TIMEOUT
  )
end
