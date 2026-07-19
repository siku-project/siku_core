if not _VERSION:find('5.4') then
  error('Lua 5.4 must be enabled in the resource manifest!', 2)
end

local siku_core <const> = 'siku_core'
local resourceName <const> = GetCurrentResourceName()

if resourceName == siku_core then return end

if Siku and Siku.name == siku_core then
  error(("Cannot load siku_core more than once.\n\tRemove any duplicate entries from '@%s/fxmanifest.lua'"):format(resourceName))
end

if GetResourceState(siku_core) ~= 'started' then
  error(('^1siku_core must be started before \'%s\'.^0'):format(resourceName), 0)
end

Siku = exports[siku_core]:objectExport()
