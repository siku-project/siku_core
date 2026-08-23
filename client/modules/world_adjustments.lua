local playerId <const> = PlayerId()

--- Remove HUD components based on config.
local function removeHudComponents()
  for i = 1, #WorldConfig.removeHudComponents do
    if WorldConfig.removeHudComponents[i] then
      SetHudComponentSize(i, 0.0, 0.0)
      SetHudComponentPosition(i, 900.0, 900.0)
    end
  end
end

--- Disable aim assist (force free aim).
local function disableAimAssist()
  if WorldConfig.disableAimAssist then
    SetPlayerTargetingMode(3)
  end
end

--- Disable NPC weapon drops on death.
local function disableNPCDrops()
  if WorldConfig.disableNPCDrops then
    local pickups <const> = {
      GetHashKey('PICKUP_WEAPON_CARBINERIFLE'),
      GetHashKey('PICKUP_WEAPON_PISTOL'),
      GetHashKey('PICKUP_WEAPON_PUMPSHOTGUN'),
    }

    for i = 1, #pickups do
      ToggleUsePickupsForPlayer(playerId, pickups[i], false)
    end
  end
end

--- Disable automatic health regeneration.
local function disableHealthRegeneration()
  if WorldConfig.disableHealthRegeneration then
    SetPlayerHealthRechargeMultiplier(playerId, 0.0)
  end
end

--- Enable PvP (friendly fire).
local function enablePvP()
  if WorldConfig.enablePvP then
    SetCanAttackFriendly(PlayerPedId(), true, false)
    NetworkSetFriendlyFireOption(true)
  end
end

--- Disable the wanted level system.
local function disableWantedLevel()
  if WorldConfig.disableWantedLevel then
    ClearPlayerWantedLevel(playerId)
    SetMaxWantedLevel(0)
  end
end

--- Disable all GTA dispatch services.
local function disableDispatchServices()
  if WorldConfig.disableDispatchServices then
    for i = 1, 15 do
      EnableDispatchService(i, false)
    end
    SetAudioFlag('PoliceScannerDisabled', true)
  end
end

--- Disable NPC vehicle scenarios.
local function disableScenarios()
  if WorldConfig.disableScenarios then
    for i = 1, #WorldConfig.scenarios do
      SetScenarioTypeEnabled(WorldConfig.scenarios[i], false)
    end
  end
end

--- Set custom AI license plate pattern.
local function setCustomAIPlates()
  SetDefaultVehicleNumberPlateTextPattern(-1, WorldConfig.customAIPlates)
end

--- Prevent automatic seat shuffling when entering vehicles.
local function startSeatShuffleHandler()
  if not WorldConfig.disableSeatShuffle then return end

  AddEventHandler('gameEventTriggered', function(name)
    if name ~= 'CEventNetworkPlayerEnteredVehicle' then return end

    local ped <const> = PlayerPedId()
    local vehicle <const> = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
      if GetPedInVehicleSeat(vehicle, seat) == ped and seat > -1 then
        SetPedIntoVehicle(ped, vehicle, seat)
        SetPedConfigFlag(ped, 184, true)
        break
      end
    end
  end)
end

--- Disable vehicle radio on enter and prevent player radio control.
local function startRadioDisableHandler()
  if not WorldConfig.disableRadioOnEnter then return end

  AddEventHandler('gameEventTriggered', function(name)
    if name ~= 'CEventNetworkPlayerEnteredVehicle' then return end

    local vehicle <const> = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
      SetVehRadioStation(vehicle, 'OFF')
      SetUserRadioControlEnabled(false)
    end
  end)
end

--- Get the value of a Discord presence placeholder.
---@param key string The placeholder key.
---@return string value The resolved value.
local function getPlaceholderValue(key)
  if key == 'server_name' then
    return GetConvar('sv_projectName', 'Siku')
  elseif key == 'server_players' then
    return tostring(GlobalState.playerCount or 0)
  elseif key == 'server_maxplayers' then
    return tostring(GetConvarInt('sv_maxClients', 48))
  elseif key == 'player_name' then
    return GetPlayerName(playerId) or 'Unknown'
  elseif key == 'player_id' then
    return tostring(GetPlayerServerId(playerId))
  elseif key == 'player_street' then
    local ped <const> = PlayerPedId()
    if not ped then return 'Unknown' end
    local coords <const> = GetEntityCoords(ped, true)
    local streetHash <const> = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    return GetStreetNameFromHashKey(streetHash) or 'Unknown'
  end
  return key
end

--- Replace placeholders in a string with their resolved values.
---@param text string The text containing {placeholder} patterns.
---@return string result The text with placeholders replaced.
local function replacePlaceholders(text)
  return text:gsub('{(%w+)}', function(key)
    return getPlaceholderValue(key)
  end)
end

--- Start the Discord Rich Presence update loop.
local function startDiscordPresence()
  if not WorldConfig.discord.enabled or WorldConfig.discord.appId == '' then return end

  Siku.timers.setInterval(WorldConfig.discord.refreshInterval, function()
    SetDiscordAppId(WorldConfig.discord.appId)
    SetRichPresence(replacePlaceholders(WorldConfig.discord.presence))
    SetDiscordRichPresenceAsset(WorldConfig.discord.assetName)
    SetDiscordRichPresenceAssetText(replacePlaceholders(WorldConfig.discord.assetText))

    for i = 1, #WorldConfig.discord.buttons do
      local button <const> = WorldConfig.discord.buttons[i]
      SetDiscordRichPresenceAction(i - 1, button.label, replacePlaceholders(button.url))
    end
  end)
end

--- Start the per-frame loop for density, ammo, rewards, and idle camera.
local function startFrameLoop()
  local hasAmmo <const> = WorldConfig.disableDisplayAmmo
  local hasRewards <const> = WorldConfig.disableVehicleRewards
  local hasIdle <const> = WorldConfig.disableIdleCamera
  local d <const> = WorldConfig.density
  local hasDensity <const> = d.pedDensity ~= 1.0
    or d.vehicleDensity ~= 1.0
    or d.parkedVehicleDensity ~= 1.0
    or d.randomVehicleDensity ~= 1.0
    or d.ambientVehicleRange ~= 1.0
    or d.scenarioPedDensityInterior ~= 1.0
    or d.scenarioPedDensityExterior ~= 1.0

  if not hasAmmo and not hasRewards and not hasIdle and not hasDensity then return end

  CreateThread(function()
    while true do
      if hasAmmo then DisplayAmmoThisFrame(false) end
      if hasRewards then DisablePlayerVehicleRewards(playerId) end
      if hasIdle then InvalidateIdleCam() end

      if hasDensity then
        SetPedDensityMultiplierThisFrame(d.pedDensity)
        SetScenarioPedDensityMultiplierThisFrame(d.scenarioPedDensityInterior, d.scenarioPedDensityExterior)
        SetAmbientVehicleRangeMultiplierThisFrame(d.ambientVehicleRange)
        SetParkedVehicleDensityMultiplierThisFrame(d.parkedVehicleDensity)
        SetRandomVehicleDensityMultiplierThisFrame(d.randomVehicleDensity)
        SetVehicleDensityMultiplierThisFrame(d.vehicleDensity)
      end

      Wait(0)
    end
  end)
end

removeHudComponents()
disableAimAssist()
disableNPCDrops()
disableHealthRegeneration()
enablePvP()
disableWantedLevel()
disableDispatchServices()
disableScenarios()
setCustomAIPlates()
startSeatShuffleHandler()
startRadioDisableHandler()
startDiscordPresence()
startFrameLoop()
