local INIT_STATE_KEY <const> = 'siku:state:initVehicle'
local PROPERTIES_STATE_KEY <const> = 'siku:state:setVehicleProperties'
local ENTITY_RESOLVE_TIMEOUT <const> = 10000
local COLLISION_TIMEOUT <const> = 5000
local REAPPLY_DELAY <const> = 200
local DRIFT_TYRES_BUILD <const> = 2372
local BURST_TYRE_DAMAGE <const> = 1000.0
local FRONT_TIRES_MOD <const> = 23
local REAR_TIRES_MOD <const> = 24
local MAX_EXTRAS <const> = 15
local MAX_WINDOW_INDEX <const> = 7
local MAX_DOOR_INDEX <const> = 5
local MAX_TYRE_INDEX <const> = 7
local MAX_NEON_INDEX <const> = 3

local MOD_INDICES <const> = {
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
  23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
  39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
}

local TOGGLE_MOD_INDICES <const> = { 18, 19, 20, 21, 22 }

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

---@class InitVehicleOptions
---@field placeOnGround? boolean Place the vehicle on the ground properly (default: true).
---@field freezePosition? boolean Freeze the vehicle position after init.
---@field props? VehicleProperties Vehicle properties to apply after init.
---@field fixVehicle? boolean Fix the vehicle after applying props.

--- Get all properties of a vehicle as a serializable table.
---@param vehicle number The vehicle entity handle.
---@return VehicleProperties|nil properties The vehicle properties or nil if entity does not exist.
local function getVehicleProperties(vehicle)
  if not DoesEntityExist(vehicle) then return nil end

  local colorPrimary <const>, colorSecondary <const> = GetVehicleColours(vehicle)
  local pearlescentColor <const>, wheelColor <const> = GetVehicleExtraColours(vehicle)

  local color1 = colorPrimary
  local color2 = colorSecondary

  if GetIsVehiclePrimaryColourCustom(vehicle) then
    local r <const>, g <const>, b <const> = GetVehicleCustomPrimaryColour(vehicle)
    color1 = { r, g, b }
  end

  if GetIsVehicleSecondaryColourCustom(vehicle) then
    local r <const>, g <const>, b <const> = GetVehicleCustomSecondaryColour(vehicle)
    color2 = { r, g, b }
  end

  local extras <const> = {}
  for i = 1, MAX_EXTRAS do
    if DoesExtraExist(vehicle, i) then
      extras[i] = IsVehicleExtraTurnedOn(vehicle, i)
    end
  end

  local neonEnabled <const> = {}
  for i = 0, MAX_NEON_INDEX do
    neonEnabled[i + 1] = IsVehicleNeonLightEnabled(vehicle, i)
  end

  local neonR <const>, neonG <const>, neonB <const> = GetVehicleNeonLightsColour(vehicle)
  local smokeR <const>, smokeG <const>, smokeB <const> = GetVehicleTyreSmokeColor(vehicle)

  local mods <const> = {}
  for i = 1, #MOD_INDICES do
    local idx <const> = MOD_INDICES[i]
    local value <const> = GetVehicleMod(vehicle, idx)
    if value ~= -1 then mods[idx] = value end
  end

  local toggleMods <const> = {}
  for i = 1, #TOGGLE_MOD_INDICES do
    local idx <const> = TOGGLE_MOD_INDICES[i]
    toggleMods[idx] = IsToggleModOn(vehicle, idx)
  end

  local windows <const> = {}
  for i = 0, MAX_WINDOW_INDEX do
    RollUpWindow(vehicle, i)
    if not IsVehicleWindowIntact(vehicle, i) then
      windows[#windows + 1] = i
    end
  end

  local doors <const> = {}
  for i = 0, MAX_DOOR_INDEX do
    if IsVehicleDoorDamaged(vehicle, i) then
      doors[#doors + 1] = i
    end
  end

  local tyres <const> = {}
  for i = 0, MAX_TYRE_INDEX do
    if IsVehicleTyreBurst(vehicle, i, false) then
      tyres[i] = IsVehicleTyreBurst(vehicle, i, true) and 2 or 1
    end
  end

  return {
    model = GetEntityModel(vehicle),
    plate = GetVehicleNumberPlateText(vehicle),
    plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
    lockState = GetVehicleDoorLockStatus(vehicle),
    bodyHealth = math.floor(GetVehicleBodyHealth(vehicle) + 0.5),
    engineHealth = math.floor(GetVehicleEngineHealth(vehicle) + 0.5),
    tankHealth = math.floor(GetVehiclePetrolTankHealth(vehicle) + 0.5),
    fuelLevel = math.floor(GetVehicleFuelLevel(vehicle) + 0.5),
    oilLevel = math.floor(GetVehicleOilLevel(vehicle) + 0.5),
    dirtLevel = math.floor(GetVehicleDirtLevel(vehicle) + 0.5),
    paintType1 = GetVehicleModColor_1(vehicle),
    paintType2 = GetVehicleModColor_2(vehicle),
    color1 = color1,
    color2 = color2,
    pearlescentColor = pearlescentColor,
    interiorColor = GetVehicleInteriorColor(vehicle),
    dashboardColor = GetVehicleDashboardColour(vehicle),
    wheelColor = wheelColor,
    wheelWidth = GetVehicleWheelWidth(vehicle),
    wheelSize = GetVehicleWheelSize(vehicle),
    wheels = GetVehicleWheelType(vehicle),
    windowTint = GetVehicleWindowTint(vehicle),
    xenonColor = GetVehicleXenonLightsColor(vehicle),
    neonEnabled = neonEnabled,
    neonColor = { neonR, neonG, neonB },
    extras = extras,
    tyreSmokeColor = { smokeR, smokeG, smokeB },
    livery = GetVehicleLivery(vehicle),
    roofLivery = GetVehicleRoofLivery(vehicle),
    bulletProofTyres = GetVehicleTyresCanBurst(vehicle),
    driftTyres = GetGameBuildNumber() >= DRIFT_TYRES_BUILD and GetDriftTyresEnabled(vehicle) or false,
    mods = mods,
    toggleMods = toggleMods,
    customTiresF = GetVehicleModVariation(vehicle, FRONT_TIRES_MOD),
    customTiresR = GetVehicleModVariation(vehicle, REAR_TIRES_MOD),
    windows = windows,
    doors = doors,
    tyres = tyres,
  }
end

--- Apply the primary and secondary colours of a vehicle, custom or indexed.
---@param vehicle number The vehicle entity handle.
---@param props VehicleProperties The properties carrying the colours.
local function applyColours(vehicle, props)
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
end

--- Apply the mods, extras and damage of a vehicle.
---@param vehicle number The vehicle entity handle.
---@param props VehicleProperties The properties carrying the mods and damage.
local function applyModsAndDamage(vehicle, props)
  if props.extras ~= nil then
    for id, enabled in pairs(props.extras) do
      SetVehicleExtra(vehicle, id, not enabled)
    end
  end

  if props.mods ~= nil then
    for idx, value in pairs(props.mods) do
      local customTires = false
      if idx == FRONT_TIRES_MOD then
        customTires = props.customTiresF or false
      elseif idx == REAR_TIRES_MOD then
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
      SetVehicleTyreBurst(vehicle, idx, state == 2, BURST_TYRE_DAMAGE)
    end
  end
end

--- Apply properties to a vehicle from a properties table.
---
--- Usage: `Siku.vehicle.setProperties(vehicle, { plate = 'SIKU', color1 = { 255, 0, 0 } }, true)`
---@param vehicle number The vehicle entity handle.
---@param props VehicleProperties The properties table `{}` to apply (partial, only set fields are applied).
---@param fixVehicle? boolean Fix the vehicle after props have been set (recommended when applying extras).
---@return boolean success Whether the properties were applied and the client is the network owner.
local function setVehicleProperties(vehicle, props, fixVehicle)
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

  applyColours(vehicle, props)

  if props.interiorColor ~= nil then SetVehicleInteriorColor(vehicle, props.interiorColor) end
  if props.dashboardColor ~= nil then SetVehicleDashboardColor(vehicle, props.dashboardColor) end
  if props.wheels ~= nil then SetVehicleWheelType(vehicle, props.wheels) end
  if props.wheelSize ~= nil then SetVehicleWheelSize(vehicle, props.wheelSize) end
  if props.wheelWidth ~= nil then SetVehicleWheelWidth(vehicle, props.wheelWidth) end
  if props.windowTint ~= nil then SetVehicleWindowTint(vehicle, props.windowTint) end

  if props.neonEnabled ~= nil then
    for i = 0, MAX_NEON_INDEX do
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

  applyModsAndDamage(vehicle, props)

  if props.livery ~= nil then SetVehicleLivery(vehicle, props.livery) end
  if props.roofLivery ~= nil then SetVehicleRoofLivery(vehicle, props.roofLivery) end
  if props.bulletProofTyres ~= nil then SetVehicleTyresCanBurst(vehicle, props.bulletProofTyres) end

  if props.driftTyres and GetGameBuildNumber() >= DRIFT_TYRES_BUILD then
    SetDriftTyresEnabled(vehicle, true)
  end

  if fixVehicle then
    SetVehicleFixed(vehicle)
  end

  return not NetworkGetEntityIsNetworked(vehicle) or NetworkGetEntityOwner(vehicle) == PlayerId()
end

--- Resolve the vehicle entity a state bag belongs to, waiting for it to stream in.
---@param bagName string The state bag name.
---@return number? vehicle The vehicle entity handle.
local function resolveBagVehicle(bagName)
  return Siku.waitFor(function()
    local entity <const> = GetEntityFromStateBagName(bagName)
    if entity and entity > 0 then return entity end
  end, ("Failed to resolve entity from StateBag '%s'"):format(bagName), ENTITY_RESOLVE_TIMEOUT)
end

AddStateBagChangeHandler(INIT_STATE_KEY, '', function(bagName, _, value)
  if not value then return end

  while NetworkIsInTutorialSession() do Wait(0) end

  local vehicle <const> = resolveBagVehicle(bagName)

  if not vehicle then return end

  Siku.waitFor(function()
    if not IsEntityWaitingForWorldCollision(vehicle) then return true end
  end, nil, COLLISION_TIMEOUT)

  if NetworkGetEntityIsNetworked(vehicle) and NetworkGetEntityOwner(vehicle) ~= PlayerId() then return end

  if value.placeOnGround ~= false then
    SetVehicleOnGroundProperly(vehicle)
  end

  if value.freezePosition then
    FreezeEntityPosition(vehicle, true)
  end

  if value.props then
    setVehicleProperties(vehicle, value.props, value.fixVehicle)
  end

  Wait(REAPPLY_DELAY)
  Entity(vehicle).state:set(INIT_STATE_KEY, nil, true)
end)

AddStateBagChangeHandler(PROPERTIES_STATE_KEY, '', function(bagName, _, value)
  if not value then return end

  local vehicle <const> = resolveBagVehicle(bagName)

  if not vehicle then return end

  setVehicleProperties(vehicle, value.props, value.fixVehicle)

  Wait(REAPPLY_DELAY)

  if DoesEntityExist(vehicle) and NetworkGetEntityOwner(vehicle) == PlayerId() then
    setVehicleProperties(vehicle, value.props, value.fixVehicle)
  end

  Entity(vehicle).state:set(PROPERTIES_STATE_KEY, nil, true)
end)

return {
  getProperties = getVehicleProperties,
  setProperties = setVehicleProperties,
}
