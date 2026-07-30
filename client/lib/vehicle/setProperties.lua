---@class VehicleProperties
---@field model? number The vehicle model hash.
---@field plate? string The license plate text.
---@field plateIndex? number The license plate style index.
---@field lockState? number The door lock state (0 = unlocked, 2 = locked, etc.).
---@field bodyHealth? number The body health (0-1000).
---@field engineHealth? number The engine health (0-1000).
---@field tankHealth? number The petrol tank health (0-1000).
---@field fuelLevel? number The fuel level (0-100).
---@field oilLevel? number The oil level.
---@field dirtLevel? number The dirt level (0-15).
---@field paintType1? number The primary paint type.
---@field paintType2? number The secondary paint type.
---@field color1? number|number[] The primary color (index or {r, g, b} for custom).
---@field color2? number|number[] The secondary color (index or {r, g, b} for custom).
---@field pearlescentColor? number The pearlescent color index.
---@field interiorColor? number The interior color index.
---@field dashboardColor? number The dashboard color index.
---@field wheelColor? number The wheel color index.
---@field wheelWidth? number The wheel width.
---@field wheelSize? number The wheel size.
---@field wheels? number The wheel type index.
---@field windowTint? number The window tint index.
---@field xenonColor? number The xenon headlight color index.
---@field neonEnabled? boolean[] The neon light state for each side { left, right, front, back }.
---@field neonColor? number[] The neon light color { r, g, b }.
---@field extras? table<number, boolean> The vehicle extras { [extraId] = enabled }.
---@field tyreSmokeColor? number[] The tyre smoke color { r, g, b }.
---@field livery? number The livery index.
---@field roofLivery? number The roof livery index.
---@field bulletProofTyres? boolean Whether tyres are bullet proof.
---@field driftTyres? boolean Whether drift tyres are enabled (game build 2372+).
---@field mods? table<number, number> The vehicle mods { [modIndex] = modValue }.
---@field toggleMods? table<number, boolean> The toggle mods { [modIndex] = enabled }.
---@field customTiresF? boolean Whether front tires are custom.
---@field customTiresR? boolean Whether rear tires are custom.
---@field windows? number[] The broken window indices.
---@field doors? number[] The damaged door indices.
---@field tyres? table<number, 1|2> The burst tyre states { [tyreIndex] = 1 (burst) or 2 (completely burst) }.

--- Apply properties to a vehicle from a properties table.
---
--- Usage: `Siku.SetVehicleProperties(vehicle, { plate = 'SIKU', color1 = { 255, 0, 0 } }, true)`
---@param vehicle number The vehicle entity handle.
---@param props VehicleProperties The properties table `{}` to apply (partial, only set fields are applied).
---@param fixVehicle? boolean Fix the vehicle after props have been set (recommended when applying extras).
---@return boolean success Whether the properties were applied and the client is the network owner.
function Siku.SetVehicleProperties(vehicle, props, fixVehicle)
  if not DoesEntityExist(vehicle) then return false end

  SetVehicleModKit(vehicle, 0)

  if props.plate ~= nil then SetVehicleNumberPlateText(vehicle, props.plate) end
  if props.plateIndex ~= nil then SetVehicleNumberPlateTextIndex(vehicle, props.plateIndex) end
  if props.lockState ~= nil then SetVehicleDoorsLocked(vehicle, props.lockState) end
  if props.bodyHealth ~= nil then SetVehicleBodyHealth(vehicle, props.bodyHealth + 0.0) end
  if props.engineHealth ~= nil then SetVehicleEngineHealth(vehicle, props.engineHealth + 0.0) end
  if props.tankHealth ~= nil then SetVehiclePetrolTankHealth(vehicle, props.tankHealth + 0.0) end
  if props.fuelLevel ~= nil then SetVehicleFuelLevel(vehicle, props.fuelLevel + 0.0) end
  if props.oilLevel ~= nil then SetVehicleOilLevel(vehicle, props.oilLevel + 0.0) end
  if props.dirtLevel ~= nil then SetVehicleDirtLevel(vehicle, props.dirtLevel + 0.0) end

  if props.color1 ~= nil then
    if type(props.color1) == 'number' then
      ClearVehicleCustomPrimaryColour(vehicle)
      local _, secondary <const> = GetVehicleColours(vehicle)
      SetVehicleColours(vehicle, props.color1, secondary)
    else
      if props.paintType1 ~= nil then SetVehicleModColor_1(vehicle, props.paintType1, 0, 0) end
      SetVehicleCustomPrimaryColour(vehicle, props.color1[1], props.color1[2], props.color1[3])
    end
  end

  if props.color2 ~= nil then
    if type(props.color2) == 'number' then
      ClearVehicleCustomSecondaryColour(vehicle)
      local primary <const> = GetVehicleColours(vehicle)
      SetVehicleColours(vehicle, primary, props.color2)
    else
      if props.paintType2 ~= nil then SetVehicleModColor_2(vehicle, props.paintType2, 0) end
      SetVehicleCustomSecondaryColour(vehicle, props.color2[1], props.color2[2], props.color2[3])
    end
  end

  if props.pearlescentColor ~= nil or props.wheelColor ~= nil then
    local currentPearl <const>, currentWheel <const> = GetVehicleExtraColours(vehicle)
    SetVehicleExtraColours(vehicle, props.pearlescentColor or currentPearl, props.wheelColor or currentWheel)
  end

  if props.interiorColor ~= nil then SetVehicleInteriorColor(vehicle, props.interiorColor) end
  if props.dashboardColor ~= nil then SetVehicleDashboardColor(vehicle, props.dashboardColor) end
  if props.wheels ~= nil then SetVehicleWheelType(vehicle, props.wheels) end
  if props.wheelSize ~= nil then SetVehicleWheelSize(vehicle, props.wheelSize) end
  if props.wheelWidth ~= nil then SetVehicleWheelWidth(vehicle, props.wheelWidth) end
  if props.windowTint ~= nil then SetVehicleWindowTint(vehicle, props.windowTint) end

  if props.neonEnabled ~= nil then
    for i = 0, 3 do
      SetVehicleNeonLightEnabled(vehicle, i, props.neonEnabled[i + 1])
    end
  end

  if props.neonColor ~= nil then
    SetVehicleNeonLightsColour(vehicle, props.neonColor[1], props.neonColor[2], props.neonColor[3])
  end

  if props.tyreSmokeColor ~= nil then
    SetVehicleTyreSmokeColor(vehicle, props.tyreSmokeColor[1], props.tyreSmokeColor[2], props.tyreSmokeColor[3])
  end

  if props.xenonColor ~= nil then SetVehicleXenonLightsColor(vehicle, props.xenonColor) end

  if props.extras ~= nil then
    for id, enabled in pairs(props.extras) do
      SetVehicleExtra(vehicle, id, not enabled)
    end
  end

  if props.mods ~= nil then
    for idx, value in pairs(props.mods) do
      local customTires = false
      if idx == 23 then
        customTires = props.customTiresF or false
      elseif idx == 24 then
        customTires = props.customTiresR or false
      end
      SetVehicleMod(vehicle, idx, value, customTires)
    end
  end

  if props.toggleMods ~= nil then
    for idx, enabled in pairs(props.toggleMods) do
      ToggleVehicleMod(vehicle, idx, enabled)
    end
  end

  if props.windows ~= nil then
    for i = 1, #props.windows do
      RemoveVehicleWindow(vehicle, props.windows[i])
    end
  end

  if props.doors ~= nil then
    for i = 1, #props.doors do
      SetVehicleDoorBroken(vehicle, props.doors[i], true)
    end
  end

  if props.tyres ~= nil then
    for idx, state in pairs(props.tyres) do
      SetVehicleTyreBurst(vehicle, idx, state == 2, 1000.0)
    end
  end

  if props.livery ~= nil then SetVehicleLivery(vehicle, props.livery) end
  if props.roofLivery ~= nil then SetVehicleRoofLivery(vehicle, props.roofLivery) end
  if props.bulletProofTyres ~= nil then SetVehicleTyresCanBurst(vehicle, props.bulletProofTyres) end

  if props.driftTyres and GetGameBuildNumber() >= 2372 then
    SetDriftTyresEnabled(vehicle, true)
  end

  if fixVehicle then
    SetVehicleFixed(vehicle)
  end

  return not NetworkGetEntityIsNetworked(vehicle) or NetworkGetEntityOwner(vehicle) == PlayerId()
end

local STATE_KEY <const> = 'siku:state:setVehicleProperties'

--- Handle StateBag sync from server for vehicle properties.
AddStateBagChangeHandler(STATE_KEY, '', function(bagName, _, value)
  if not value then return end

  local vehicle <const> = Siku.WaitFor(function()
    local entity <const> = GetEntityFromStateBagName(bagName)
    if entity and entity > 0 then return entity end
  end, ('Failed to resolve entity from StateBag \'%s\''):format(bagName), 10000)

  if not vehicle then return end

  Siku.SetVehicleProperties(vehicle, value.props, value.fixVehicle)

  Wait(200)

  if DoesEntityExist(vehicle) and NetworkGetEntityOwner(vehicle) == PlayerId() then
    Siku.SetVehicleProperties(vehicle, value.props, value.fixVehicle)
  end

  Entity(vehicle).state:set(STATE_KEY, nil, true)
end)
