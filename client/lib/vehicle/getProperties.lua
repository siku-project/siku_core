local MOD_INDICES <const> = {
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
  23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
  39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
}

local TOGGLE_MOD_INDICES <const> = { 18, 19, 20, 21, 22 }

--- Get all properties of a vehicle as a serializable table.
---@param vehicle number The vehicle entity handle.
---@return VehicleProperties|nil properties The vehicle properties or nil if entity does not exist.
function Siku.GetVehicleProperties(vehicle)
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
  for i = 1, 15 do
    if DoesExtraExist(vehicle, i) then
      extras[i] = IsVehicleExtraTurnedOn(vehicle, i)
    end
  end

  local neonEnabled <const> = {
    IsVehicleNeonLightEnabled(vehicle, 0),
    IsVehicleNeonLightEnabled(vehicle, 1),
    IsVehicleNeonLightEnabled(vehicle, 2),
    IsVehicleNeonLightEnabled(vehicle, 3),
  }

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
  for i = 0, 7 do
    RollUpWindow(vehicle, i)
    if not IsVehicleWindowIntact(vehicle, i) then
      windows[#windows + 1] = i
    end
  end

  local doors <const> = {}
  for i = 0, 5 do
    if IsVehicleDoorDamaged(vehicle, i) then
      doors[#doors + 1] = i
    end
  end

  local tyres <const> = {}
  for i = 0, 7 do
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
    driftTyres = GetGameBuildNumber() >= 2372 and GetDriftTyresEnabled(vehicle) or false,
    mods = mods,
    toggleMods = toggleMods,
    customTiresF = GetVehicleModVariation(vehicle, 23),
    customTiresR = GetVehicleModVariation(vehicle, 24),
    windows = windows,
    doors = doors,
    tyres = tyres,
  }
end
