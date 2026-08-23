local DEFAULT_TICK_INTERVAL <const> = 1000

local timers = {}
local nextId = 1

--- Get the current timestamp in milliseconds.
---@return number now The current time in ms.
local function now()
  return GetGameTimer()
end

--- Get the elapsed time of a timer in milliseconds.
---@param t table The internal timer data.
---@return number elapsed The elapsed time in ms.
local function getElapsed(t)
  if t.finished then
    return t.duration
  end

  if t.pausedAt then
    return t.pausedAt - t.startTime - t.totalPaused
  end

  return now() - t.startTime - t.totalPaused
end

--- Get the remaining time of a timer in milliseconds.
---@param t table The internal timer data.
---@return number remaining The remaining time in ms.
local function getRemaining(t)
  return math.max(0, t.duration - getElapsed(t))
end

--- Build the public state of a timer.
---@param t table The internal timer data.
---@return table state { remaining, elapsed, progress, paused, finished }.
local function buildState(t)
  local elapsed <const> = getElapsed(t)
  local remaining <const> = math.max(0, t.duration - elapsed)

  return {
    remaining = remaining,
    elapsed = math.min(elapsed, t.duration),
    progress = math.min(elapsed / t.duration, 1),
    paused = t.pausedAt ~= nil,
    finished = t.finished,
  }
end

--- Stop the tick interval of a timer.
---@param t table The internal timer data.
local function stopInterval(t)
  if not t.intervalHandle then
    return
  end

  Siku.timers.clearInterval(t.intervalHandle)
  t.intervalHandle = nil
end

--- Check if a timer has ended and trigger callbacks.
---@param t table The internal timer data.
local function checkEnd(t)
  if t.finished or getRemaining(t) > 0 then
    return
  end

  t.finished = true
  stopInterval(t)

  if t.onTick then
    t.onTick(buildState(t))
  end

  if t.onEnd then
    t.onEnd()
  end

  timers[t.id] = nil
end

--- Start the tick interval of a timer.
---@param t table The internal timer data.
local function startInterval(t)
  if t.intervalHandle then
    return
  end

  t.intervalHandle = Siku.timers.setInterval(t.tickInterval, function()
    if t.pausedAt then
      return
    end

    if t.onTick then
      t.onTick(buildState(t))
    end

    checkEnd(t)
  end)
end

--- Build the public timer instance from internal data.
---@param data table The internal timer data.
---@return table timer The public timer instance.
local function buildTimer(data)
  local timer <const> = {
    id = data.id,
    duration = data.duration,
  }

  --- Pause the timer.
  function timer.pause()
    if data.pausedAt or data.finished then
      return
    end

    data.pausedAt = now()
  end

  --- Resume the timer.
  function timer.play()
    if not data.pausedAt or data.finished then
      return
    end

    data.totalPaused = data.totalPaused + (now() - data.pausedAt)
    data.pausedAt = nil

    if not data.intervalHandle then
      startInterval(data)
    end

    checkEnd(data)
  end

  --- Restart the timer from the beginning.
  function timer.restart()
    stopInterval(data)
    data.startTime = now()
    data.pausedAt = nil
    data.totalPaused = 0
    data.finished = false
    timers[data.id] = data
    startInterval(data)
  end

  --- Stop the timer.
  ---@param triggerOnEnd? boolean Whether to fire the onEnd callback (default: false).
  function timer.stop(triggerOnEnd)
    if data.finished then
      return
    end

    data.finished = true
    stopInterval(data)
    timers[data.id] = nil

    if triggerOnEnd and data.onEnd then
      data.onEnd()
    end
  end

  --- Check if the timer is paused.
  ---@return boolean paused Whether the timer is paused.
  function timer.isPaused()
    return data.pausedAt ~= nil
  end

  --- Check if the timer is finished.
  ---@return boolean finished Whether the timer is finished.
  function timer.isFinished()
    return data.finished
  end

  --- Get the current state of the timer.
  ---@return table state { remaining, elapsed, progress, paused, finished }.
  function timer.getState()
    return buildState(data)
  end

  --- Add time to the timer duration.
  ---@param ms number The time to add in ms.
  function timer.addTime(ms)
    if data.finished then
      return
    end

    data.duration = data.duration + ms
  end

  --- Remove time from the timer duration.
  ---@param ms number The time to remove in ms.
  function timer.removeTime(ms)
    if data.finished then
      return
    end

    data.duration = math.max(0, data.duration - ms)
    checkEnd(data)
  end

  return timer
end

--- Create a new timer with pause/play/restart/stop controls and optional callbacks.
---@param options table Timer options { duration, onEnd?, onTick?, tickInterval? (default: 1000), autoStart? (default: true) }.
---@return table timer The timer instance with pause, play, restart, stop, isPaused, isFinished, getState, addTime, removeTime.
local function create(options)
  local id <const> = nextId
  nextId = nextId + 1

  local data <const> = {
    id = id,
    duration = options.duration,
    startTime = now(),
    pausedAt = nil,
    totalPaused = 0,
    finished = false,
    intervalHandle = nil,
    onEnd = options.onEnd,
    onTick = options.onTick,
    tickInterval = options.tickInterval or DEFAULT_TICK_INTERVAL,
  }

  timers[id] = data

  local autoStart <const> = options.autoStart ~= false

  if autoStart then
    startInterval(data)
  else
    data.pausedAt = data.startTime
  end

  return buildTimer(data)
end

--- Get a timer by its ID.
---@param id number The timer ID.
---@return table|nil timer The timer instance or nil if not found.
local function get(id)
  local data <const> = timers[id]

  if not data then
    return nil
  end

  return buildTimer(data)
end

--- Get all active timer IDs.
---@return table ids A list of active timer IDs.
local function getAll()
  local result <const> = {}

  for id in pairs(timers) do
    result[#result + 1] = id
  end

  return result
end

return {
  create = create,
  get = get,
  getAll = getAll,
}
