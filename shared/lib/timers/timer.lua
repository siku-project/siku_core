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
  if t.finished then return t.duration end
  if t.pausedAt then return t.pausedAt - t.startTime - t.totalPaused end
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
  if not t.intervalHandle then return end
  Siku.ClearInterval(t.intervalHandle)
  t.intervalHandle = nil
end

--- Check if a timer has ended and trigger callbacks.
---@param t table The internal timer data.
local function checkEnd(t)
  if t.finished then return end
  if getRemaining(t) > 0 then return end

  t.finished = true
  stopInterval(t)

  if t.onTick then t.onTick(buildState(t)) end
  if t.onEnd then t.onEnd() end

  timers[t.id] = nil
end

--- Start the tick interval of a timer.
---@param t table The internal timer data.
local function startInterval(t)
  if t.intervalHandle then return end

  t.intervalHandle = Siku.SetInterval(t.tickInterval, function()
    if t.pausedAt then return end
    if t.onTick then t.onTick(buildState(t)) end
    checkEnd(t)
  end)
end

--- Build the public timer instance from internal data.
---@param internal table The internal timer data.
---@return table timer The public timer instance.
local function buildTimer(internal)
  local timer <const> = {
    id = internal.id,
    duration = internal.duration,
  }

  --- Pause the timer.
  function timer.pause()
    if internal.pausedAt or internal.finished then return end
    internal.pausedAt = now()
  end

  --- Resume the timer.
  function timer.play()
    if not internal.pausedAt or internal.finished then return end
    internal.totalPaused = internal.totalPaused + (now() - internal.pausedAt)
    internal.pausedAt = nil
    if not internal.intervalHandle then startInterval(internal) end
    checkEnd(internal)
  end

  --- Restart the timer from the beginning.
  function timer.restart()
    stopInterval(internal)
    internal.startTime = now()
    internal.pausedAt = nil
    internal.totalPaused = 0
    internal.finished = false
    timers[internal.id] = internal
    startInterval(internal)
  end

  --- Stop the timer.
  ---@param triggerOnEnd? boolean Whether to fire the onEnd callback (default: false).
  function timer.stop(triggerOnEnd)
    if internal.finished then return end
    internal.finished = true
    stopInterval(internal)
    timers[internal.id] = nil
    if triggerOnEnd and internal.onEnd then internal.onEnd() end
  end

  --- Check if the timer is paused.
  ---@return boolean paused Whether the timer is paused.
  function timer.isPaused()
    return internal.pausedAt ~= nil
  end

  --- Check if the timer is finished.
  ---@return boolean finished Whether the timer is finished.
  function timer.isFinished()
    return internal.finished
  end

  --- Get the current state of the timer.
  ---@return table state { remaining, elapsed, progress, paused, finished }.
  function timer.getState()
    return buildState(internal)
  end

  --- Add time to the timer duration.
  ---@param ms number The time to add in ms.
  function timer.addTime(ms)
    if internal.finished then return end
    internal.duration = internal.duration + ms
  end

  --- Remove time from the timer duration.
  ---@param ms number The time to remove in ms.
  function timer.removeTime(ms)
    if internal.finished then return end
    internal.duration = math.max(0, internal.duration - ms)
    checkEnd(internal)
  end

  return timer
end

--- Create a new timer with pause/play/restart/stop controls and optional callbacks.
---@param options table Timer options { duration, onEnd?, onTick?, tickInterval? (default: 1000), autoStart? (default: true) }.
---@return table timer The timer instance with pause, play, restart, stop, isPaused, isFinished, getState, addTime, removeTime.
function Siku.CreateTimer(options)
  local id <const> = nextId
  nextId = nextId + 1

  local internal <const> = {
    id = id,
    duration = options.duration,
    startTime = now(),
    pausedAt = nil,
    totalPaused = 0,
    finished = false,
    intervalHandle = nil,
    onEnd = options.onEnd,
    onTick = options.onTick,
    tickInterval = options.tickInterval or 1000,
  }

  timers[id] = internal

  local autoStart <const> = options.autoStart ~= false

  if autoStart then
    startInterval(internal)
  else
    internal.pausedAt = internal.startTime
  end

  return buildTimer(internal)
end

--- Get a timer by its ID.
---@param id number The timer ID.
---@return table|nil timer The timer instance or nil if not found.
function Siku.GetTimer(id)
  local internal <const> = timers[id]
  if not internal then return nil end
  return buildTimer(internal)
end

--- Get all active timer IDs.
---@return table ids A list of active timer IDs.
function Siku.GetAllTimers()
  local result <const> = {}
  for id in pairs(timers) do
    result[#result + 1] = id
  end
  return result
end
