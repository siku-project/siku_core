--- Create a new spatial grid for efficient proximity queries.
---@param options? table Grid options { cellSize?, minX?, maxX?, minY?, maxY? }.
---@return table grid The spatial grid instance with add, remove, update, getNearby, getClosest, getCell, getCellKey, has, count, clear methods.
function Siku.CreateSpatialGrid(options)
  local cellSize <const> = (options and options.cellSize) or SpatialConfig.gridCellSize
  local minX <const> = (options and options.minX) or SpatialConfig.mapMinX
  local maxX <const> = (options and options.maxX) or SpatialConfig.mapMaxX
  local minY <const> = (options and options.minY) or SpatialConfig.mapMinY
  local maxY <const> = (options and options.maxY) or SpatialConfig.mapMaxY

  local cells = {}
  local entries = {}
  local entryCount = 0
  local nextId = 1
  local generation = 0

  --- Convert world coordinates to cell indices.
  ---@param x number World X coordinate.
  ---@param y number World Y coordinate.
  ---@return number cx The cell X index.
  ---@return number cy The cell Y index.
  local function coordToCell(x, y)
    local cx <const> = math.floor((math.max(minX, math.min(maxX, x)) - minX) / cellSize)
    local cy <const> = math.floor((math.max(minY, math.min(maxY, y)) - minY) / cellSize)
    return cx, cy
  end

  --- Pack two cell indices into a single unique key.
  ---@param cx number Cell X index.
  ---@param cy number Cell Y index.
  ---@return number key The packed cell key.
  local function packKey(cx, cy)
    return (cx << 16) | (cy & 0xFFFF)
  end

  --- Get the cell range that covers a radius around coordinates.
  ---@param coords vector3 The center coordinates.
  ---@param radius number The search radius.
  ---@return number x1 Min cell X.
  ---@return number x2 Max cell X.
  ---@return number y1 Min cell Y.
  ---@return number y2 Max cell Y.
  local function getCellRange(coords, radius)
    local x1, y1 = coordToCell(coords.x - radius, coords.y - radius)
    local x2, y2 = coordToCell(coords.x + radius, coords.y + radius)
    return x1, x2, y1, y2
  end

  --- Insert an entry into all grid cells it overlaps.
  ---@param entry table The grid entry.
  local function insertIntoCells(entry)
    local x1, x2, y1, y2 = getCellRange(entry.coords, entry.radius)
    local cellKeys <const> = {}

    for cy = y1, y2 do
      for cx = x1, x2 do
        local key <const> = packKey(cx, cy)
        if not cells[key] then
          cells[key] = {}
        end
        cells[key][entry.id] = true
        cellKeys[#cellKeys + 1] = key
      end
    end

    entry.cells = cellKeys
  end

  --- Remove an entry from all grid cells it occupies.
  ---@param entry table The grid entry.
  local function removeFromCells(entry)
    for i = 1, #entry.cells do
      local key <const> = entry.cells[i]
      local cell <const> = cells[key]
      if cell then
        cell[entry.id] = nil
        if not next(cell) then
          cells[key] = nil
        end
      end
    end
    entry.cells = {}
  end

  --- Check if an entry matches the given tag filters.
  ---@param entry table The grid entry.
  ---@param tags? table A list of tag strings to match.
  ---@param matchAll? boolean Whether all tags must match (default: any).
  ---@return boolean matches Whether the entry matches.
  local function matchesTags(entry, tags, matchAll)
    if not tags or #tags == 0 then return true end

    if matchAll then
      for i = 1, #tags do
        if not entry.tags[tags[i]] then return false end
      end
      return true
    end

    for i = 1, #tags do
      if entry.tags[tags[i]] then return true end
    end
    return false
  end

  --- Calculate squared distance between two points.
  ---@param a vector3 First point.
  ---@param b vector3 Second point.
  ---@return number distSq The squared distance.
  local function distanceSq(a, b)
    local dx <const> = a.x - b.x
    local dy <const> = a.y - b.y
    local dz <const> = a.z - b.z
    return dx * dx + dy * dy + dz * dz
  end

  --- Append an entry to the results when it passes every query filter.
  ---@param entry table The candidate grid entry.
  ---@param coords vector3 The query center.
  ---@param radius number The query radius.
  ---@param options? table The query options.
  ---@param results table The result list to append to.
  local function collectNearby(entry, coords, radius, options, results)
    if not matchesTags(entry, options and options.tags, options and options.matchAllTags) then return end
    if options and options.minZ and entry.coords.z < options.minZ then return end
    if options and options.maxZ and entry.coords.z > options.maxZ then return end

    local dSq <const> = distanceSq(coords, entry.coords)
    local totalRadius <const> = radius + entry.radius
    if dSq > totalRadius * totalRadius then return end

    results[#results + 1] = {
      id = entry.id,
      coords = entry.coords,
      distance = math.sqrt(dSq),
      data = entry.data,
      tags = entry.tags,
    }
  end

  local grid <const> = {}

  --- Add an entry to the spatial grid.
  ---@param coords vector3 The position of the entry.
  ---@param radius number The radius of the entry.
  ---@param data any The data associated with the entry.
  ---@param tags? table A list of tag strings.
  ---@return number id The unique ID of the entry.
  function grid.add(coords, radius, data, tags)
    local id <const> = nextId
    nextId = nextId + 1

    local tagSet <const> = {}
    if tags then
      for i = 1, #tags do
        tagSet[tags[i]] = true
      end
    end

    local entry <const> = {
      id = id,
      coords = coords,
      radius = math.max(radius, 0),
      tags = tagSet,
      data = data,
      cells = {},
      removed = false,
    }

    entries[id] = entry
    entryCount = entryCount + 1
    insertIntoCells(entry)
    generation = generation + 1
    return id
  end

  --- Remove an entry from the spatial grid.
  ---@param id number The ID of the entry to remove.
  ---@return boolean removed Whether the entry was found and removed.
  function grid.remove(id)
    local entry <const> = entries[id]
    if not entry then return false end
    entry.removed = true
    removeFromCells(entry)
    entries[id] = nil
    entryCount = entryCount - 1
    generation = generation + 1
    return true
  end

  --- Update the position of an entry in the grid.
  ---@param id number The ID of the entry to update.
  ---@param coords vector3 The new coordinates.
  function grid.update(id, coords)
    local entry <const> = entries[id]
    if not entry then return end
    removeFromCells(entry)
    entry.coords = coords
    insertIntoCells(entry)
    generation = generation + 1
  end

  --- Get all entries near a position within a radius.
  ---@param coords vector3 The center position.
  ---@param options? table Query options { radius?, tags?, matchAllTags?, maxResults?, minZ?, maxZ? }.
  ---@return table results A sorted list of { id, coords, distance, data, tags }.
  function grid.getNearby(coords, options)
    local radius <const> = (options and options.radius) or SpatialConfig.defaultNearbyRadius
    local x1, x2, y1, y2 = getCellRange(coords, radius)
    local seen <const> = {}
    local results <const> = {}

    for cy2 = y1, y2 do
      for cx2 = x1, x2 do
        local cell <const> = cells[packKey(cx2, cy2)]
        if cell then
          for entryId in pairs(cell) do
            if not seen[entryId] then
              seen[entryId] = true

              local entry <const> = entries[entryId]
              if entry and not entry.removed then
                collectNearby(entry, coords, radius, options, results)
              end
            end
          end
        end
      end
    end

    table.sort(results, function(a, b)
      return a.distance < b.distance
    end)

    if options and options.maxResults and #results > options.maxResults then
      for i = options.maxResults + 1, #results do
        results[i] = nil
      end
    end

    return results
  end

  --- Get the closest entry to a position.
  ---@param coords vector3 The center position.
  ---@param options? table Query options (same as getNearby).
  ---@return table|nil result The closest entry or nil.
  function grid.getClosest(coords, options)
    local opts <const> = options and { radius = options.radius, tags = options.tags, matchAllTags = options.matchAllTags, maxResults = 1, minZ = options.minZ, maxZ = options.maxZ } or { maxResults = 1 }
    local results <const> = grid.getNearby(coords, opts)
    return results[1] or nil
  end

  --- Get all entries in the cell at the given coordinates.
  ---@param coords vector3 The coordinates to check.
  ---@return table entries A list of grid entries in that cell.
  function grid.getCell(coords)
    local cx, cy = coordToCell(coords.x, coords.y)
    local cell <const> = cells[packKey(cx, cy)]
    if not cell then return {} end

    local result <const> = {}
    for id in pairs(cell) do
      local entry <const> = entries[id]
      if entry and not entry.removed then
        result[#result + 1] = entry
      end
    end
    return result
  end

  --- Get the packed cell key for coordinates.
  ---@param coords vector3 The coordinates.
  ---@return number key The packed cell key.
  function grid.getCellKey(coords)
    local cx, cy = coordToCell(coords.x, coords.y)
    return packKey(cx, cy)
  end

  --- Check if an entry exists in the grid.
  ---@param id number The entry ID.
  ---@return boolean exists Whether the entry exists.
  function grid.has(id)
    return entries[id] ~= nil
  end

  --- Get the total number of entries in the grid.
  ---@return number count The entry count.
  --- Get the total number of entries in the grid.
  ---@return number count The entry count.
  function grid.count()
    return entryCount
  end

  --- Remove all entries and cells from the grid.
  function grid.clear()
    cells = {}
    entries = {}
    entryCount = 0
    generation = generation + 1
  end

  return grid
end
