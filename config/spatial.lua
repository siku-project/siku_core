SpatialConfig = {
  --- GTA V map boundaries (world coordinates).
  --- These define the playable area used by the spatial grid.
  mapMinX = -3700,
  mapMaxX = 4500,
  mapMinY = -4400,
  mapMaxY = 8000,

  --- Size of each grid cell in world units (~meters).
  ---
  --- • 100 (default): good balance for GTA V (~82x124 grid = ~10K cells)
  ---
  --- Smaller = more precise but more cells to manage.
  --- Larger = fewer cells but more entries per cell to iterate.
  gridCellSize = 100,

  --- How often (ms) the Points system checks player proximity.
  ---
  --- • 500 (default): a player at max speed covers ~7m per check
  ---
  --- Lower = more responsive enter/exit detection, higher CPU.
  --- Higher = less responsive, lower CPU.
  pointCheckInterval = 500,

  --- How often (ms) the Zones system checks player proximity.
  ---
  --- • 300 (default): slightly faster than points, zone containment is more critical
  ---
  --- Lower = more responsive, higher CPU.
  --- Higher = less responsive, lower CPU.
  zoneCheckInterval = 300,

  --- Default radius (world units) for getNearby queries.
  ---
  --- • 150 (default): entries within this distance are considered "nearby"
  ---
  --- Also controls the coarse check range for Points and Zones.
  defaultNearbyRadius = 150,
}
