WorldConfig = {
  --- Removes the GTA wanted level system entirely (stars, police chases).
  --- Recommended: true for RP servers where police is player-controlled.
  disableWantedLevel = true,

  --- Disables automatic health regeneration over time.
  --- Recommended: true for RP to force players to use medkits/hospitals.
  disableHealthRegeneration = true,

  --- Forces free aim mode (no auto-lock on targets).
  --- Recommended: true for RP for fair gunplay.
  disableAimAssist = true,

  --- Disables all GTA dispatch services (police, ambulance, fire trucks responding to events).
  --- Recommended: true for RP where emergency services are player-controlled.
  disableDispatchServices = true,

  --- Prevents NPCs from dropping weapons when killed.
  --- Recommended: true to avoid free weapon pickups everywhere.
  disableNPCDrops = true,

  --- Prevents automatic seat shuffle (passenger sliding to driver seat).
  --- Recommended: true so passengers stay in their seat.
  disableSeatShuffle = true,

  --- Disables GTA vehicle rewards (bonus for stealing/destroying vehicles).
  --- Must run every frame — only active if set to true.
  disableVehicleRewards = true,

  --- Hides the ammo counter display.
  --- Must run every frame — only active if set to true.
  disableDisplayAmmo = true,

  --- Prevents the idle camera from activating when AFK.
  --- Must run every frame — only active if set to true.
  disableIdleCamera = true,

  --- Turns off vehicle radio when entering a vehicle.
  --- Also disables player radio control.
  disableRadioOnEnter = true,

  --- Enables friendly fire (PvP) — players can damage each other.
  --- Recommended: true for RP.
  enablePvP = true,

  --- Toggle individual HUD components on/off.
  --- Set to true to REMOVE the component from the screen.
  --- Index corresponds to the GTA HUD component ID.
  removeHudComponents = {
    false, -- 1 - WANTED_STARS
    false, -- 2 - WEAPON_ICON
    false, -- 3 - CASH
    false, -- 4 - MP_CASH
    false, -- 5 - MP_MESSAGE
    false, -- 6 - VEHICLE_NAME
    false, -- 7 - AREA_NAME
    false, -- 8 - UNUSED
    false, -- 9 - STREET_NAME
    false, -- 10 - HELP_TEXT
    false, -- 11 - FLOATING_HELP_TEXT_1
    false, -- 12 - FLOATING_HELP_TEXT_2
    false, -- 13 - CASH_CHANGE
    false, -- 14 - RETICLE
    false, -- 15 - SUBTITLE_TEXT
    false, -- 16 - RADIO_STATIONS
    false, -- 17 - SAVING_GAME
    false, -- 18 - GAME_STREAM
    false, -- 19 - WEAPON_WHEEL
    false, -- 20 - WEAPON_WHEEL_STATS
    false, -- 21 - HUD_COMPONENTS
    false, -- 22 - HUD_WEAPONS
  },

  --- Disables NPC vehicle scenarios (police patrols, ambulances, random traffic events).
  --- Reduces ambient AI activity for cleaner RP environment.
  disableScenarios = true,

  --- List of GTA scenario types to disable when disableScenarios is true.
  --- Remove entries from this list to keep specific scenarios active.
  scenarios = {
    'WORLD_VEHICLE_ATTRACTOR',
    'WORLD_VEHICLE_AMBULANCE',
    'WORLD_VEHICLE_BICYCLE_BMX',
    'WORLD_VEHICLE_BICYCLE_BMX_BALLAS',
    'WORLD_VEHICLE_BICYCLE_BMX_FAMILY',
    'WORLD_VEHICLE_BICYCLE_BMX_HARMONY',
    'WORLD_VEHICLE_BICYCLE_BMX_VAGOS',
    'WORLD_VEHICLE_BICYCLE_MOUNTAIN',
    'WORLD_VEHICLE_BICYCLE_ROAD',
    'WORLD_VEHICLE_BIKE_OFF_ROAD_RACE',
    'WORLD_VEHICLE_BIKER',
    'WORLD_VEHICLE_BOAT_IDLE',
    'WORLD_VEHICLE_BOAT_IDLE_ALAMO',
    'WORLD_VEHICLE_BOAT_IDLE_MARQUIS',
    'WORLD_VEHICLE_BROKEN_DOWN',
    'WORLD_VEHICLE_BUSINESSMEN',
    'WORLD_VEHICLE_HELI_LIFEGUARD',
    'WORLD_VEHICLE_CLUCKIN_BELL_TRAILER',
    'WORLD_VEHICLE_CONSTRUCTION_SOLO',
    'WORLD_VEHICLE_CONSTRUCTION_PASSENGERS',
    'WORLD_VEHICLE_DRIVE_PASSENGERS',
    'WORLD_VEHICLE_DRIVE_PASSENGERS_LIMITED',
    'WORLD_VEHICLE_DRIVE_SOLO',
    'WORLD_VEHICLE_FIRE_TRUCK',
    'WORLD_VEHICLE_EMPTY',
    'WORLD_VEHICLE_MARIACHI',
    'WORLD_VEHICLE_MECHANIC',
    'WORLD_VEHICLE_MILITARY_PLANES_BIG',
    'WORLD_VEHICLE_MILITARY_PLANES_SMALL',
    'WORLD_VEHICLE_PARK_PARALLEL',
    'WORLD_VEHICLE_PARK_PERPENDICULAR_NOSE_IN',
    'WORLD_VEHICLE_PASSENGER_EXIT',
    'WORLD_VEHICLE_POLICE_BIKE',
    'WORLD_VEHICLE_POLICE_CAR',
    'WORLD_VEHICLE_POLICE',
    'WORLD_VEHICLE_POLICE_NEXT_TO_CAR',
    'WORLD_VEHICLE_QUARRY',
    'WORLD_VEHICLE_SALTON',
    'WORLD_VEHICLE_SALTON_DIRT_BIKE',
    'WORLD_VEHICLE_SECURITY_CAR',
    'WORLD_VEHICLE_STREETRACE',
    'WORLD_VEHICLE_TOURBUS',
    'WORLD_VEHICLE_TOURIST',
    'WORLD_VEHICLE_TANDL',
    'WORLD_VEHICLE_TRACTOR',
    'WORLD_VEHICLE_TRACTOR_BEACH',
    'WORLD_VEHICLE_TRUCK_LOGS',
    'WORLD_VEHICLE_TRUCKS_TRAILERS',
    'WORLD_VEHICLE_DISTANT_EMPTY_GROUND',
    'WORLD_HUMAN_PAPARAZZI',
  },

  --- World density multipliers — controls how many NPCs and vehicles spawn.
  --- Range: 0.0 (none) to 1.0 (default GTA density).
  --- Lower values = less NPCs/vehicles = better performance + cleaner RP.
  density = {
    --- Pedestrian density (NPCs walking around).
    pedDensity = 0.8,
    --- Scenario ped density inside interiors.
    scenarioPedDensityInterior = 0.5,
    --- Scenario ped density outside.
    scenarioPedDensityExterior = 0.5,
    --- Range at which ambient vehicles spawn.
    ambientVehicleRange = 0.8,
    --- Density of parked vehicles (street parking).
    parkedVehicleDensity = 0.8,
    --- Density of randomly spawned driving vehicles.
    randomVehicleDensity = 0.8,
    --- Overall vehicle density multiplier.
    vehicleDensity = 0.8,
  },

  --- Pattern for AI-generated license plates.
  --- Each '.' generates a random alphanumeric character.
  customAIPlates = '........',

  --- Discord Rich Presence configuration.
  --- Shows server info in the player's Discord status.
  discord = {
    --- Enable or disable Discord Rich Presence.
    enabled = false,
    --- Your Discord Application ID (from https://discord.com/developers/applications).
    appId = '',
    --- Presence text — supports placeholders: {server_name}, {server_players}, {server_maxplayers}, {player_name}, {player_id}, {player_street}.
    presence = 'Playing on {server_name}',
    --- Large image asset name (uploaded in Discord Developer Portal).
    assetName = '',
    --- Hover text for the large image — supports same placeholders.
    assetText = '{server_name}',
    --- Clickable buttons (max 2) — { label = 'text', url = 'https://...' }.
    buttons = {},
    --- How often (ms) to refresh the presence — 60000 = 1 minute.
    refreshInterval = 60000,
  },
}
