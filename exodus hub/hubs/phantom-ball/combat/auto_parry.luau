-- [[ auto parry ]]
--!optimize 2

-- code
local AutoParry = {}
local utils
local gameInfo
local geometry
local cooldown
local remote
local targeting
local state = { generation = 0, cycle = 0, bound = false, connections = {}, phase = "detached", reason = "initial" }
local evaluating = false
local sending = false
local errorAt = -math.huge
local POLICY =
  { SLOW_WINDOW = 0.5, FAST_WINDOW = 0.3, DEFAULT_FACTOR = 0.45, MAX_FACTOR = 0.85, NATIVE_INTERVAL = 0.008, TRAINING_INTERVAL = 0.03, MAX_SAMPLE_AGE = 0.25 }
local calls, firstCall, lastCall = {}, 1, 0
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function vector(v) return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function clock() return os.clock() end
local function phase(reason)
  state.phase, state.reason = state.bound and "waiting" or "detached", reason
end
local function track(c)
  state.connections[#state.connections + 1] = c
  utils.trackCharacter(c)
end
local function resetFlight(reason)
  state.cycle += 1
  state.fired, state.shot, state.target, state.known = false, nil, -1, false
  state.timing, state.lastOwnPress, state.returnInterval, state.returnAt = nil, nil, nil, nil
  state.factor, state.factorAt, state.wasSpamActive, state.lastOwnAt = nil, nil, false, nil
  state.episodeAt, state.consumedParry, state.trackerEpoch = clock(), -math.huge, nil
  if state.tracker then
    state.tracker.reset()
  end
  phase(reason)
end
local function live()
  return state.bound
    and state.character.Parent ~= nil
    and state.root.Parent ~= nil
    and state.humanoid.Health > 0
    and utils.isActive()
    and utils.getConfigValue("AutoParry") ~= false
end
local function rate(now, record)
  while firstCall <= lastCall and calls[firstCall] <= now - 1 + 0.000001 do
    calls[firstCall] = nil
    firstCall += 1
  end
  if firstCall > lastCall then
    firstCall, lastCall = 1, 0
  elseif firstCall > 128 then
    local count = lastCall - firstCall + 1
    table.move(calls, firstCall, lastCall, 1)
    for index = count + 1, lastCall do
      calls[index] = nil
    end
    firstCall, lastCall = 1, count
  end
  if record then
    lastCall += 1
    calls[lastCall] = now
  end
  state.cps = lastCall - firstCall + 1
  if record then
    state.maxCps = math.max(state.maxCps or 0, state.cps)
  end
  return state.cps
end
local function observe(value, now)
  local mode = value.mode == "training" and "training" or "match"
  if state.ball ~= value.ball or state.mode ~= mode or (mode == "training" and state.round ~= value.trainingRound) then
    resetFlight("new_ball")
    state.ball, state.mode, state.round = value.ball, mode, value.trainingRound
  end
  local report = value.targetSignals
  if mode == "training" and not report then
    report = {
      serverNow = utils.getWorkspace():GetServerTimeNow(),
      serverTime = value.serverTime,
      receivedAt = value.syncAt,
      signals = { { name = "sync.TargetPlayerID", available = value.targetId >= 0, targeted = value.targeted } },
    }

  end
  state.tracker.observe(report, now, state.visualFrame or 0, gameInfo.getAveragePing())
  local yes, epoch = state.tracker.resolve(now)
  if yes and epoch ~= state.trackerEpoch then
    state.trackerEpoch, state.fired, state.shot = epoch, false, nil
    state.cycle += 1
    if state.lastOwnAt then
      local interval = now - state.lastOwnAt
      state.returnInterval = interval > 0 and interval <= 1.5 and interval or nil
    end
    state.lastOwnAt, state.returnAt, state.episodeAt = now, now, now
  end
  state.known, state.target = yes, yes and state.player.UserId or value.targetId
  return yes
end
local function adaptiveFactor(tti, closing, speed, base, now, ping)
  local pressure = 0
  local interval = state.returnInterval
  local age = state.returnAt and now - state.returnAt
  if finite(interval) and interval > 0 and age and age >= 0 and age <= math.min(1.5, math.max(0.1, interval) * 2) then
    pressure = 1 - math.clamp((interval - 0.1) / 0.8, 0, 1)
  end
  local budget = ping + 1 / 60
  if finite(tti) then
    pressure = math.max(pressure, math.clamp((budget - tti) / math.max(budget, 0.001), 0, 1))
  end
  pressure = math.max(pressure, math.clamp(closing / math.max(speed, 1) - 1, 0, 1))
  local desired = base + (POLICY.MAX_FACTOR - base) * pressure
  if finite(state.factor) and state.factor > desired then
    desired += (state.factor - desired) * math.exp(-math.max(0, now - (state.factorAt or now)) / 0.25)
  end
  return math.clamp(desired, base, POLICY.MAX_FACTOR)
end
local function timing(value, now, explicitFactor, own)
  if not value or not state.root then
    return nil
  end
  own = own or state.root.Position
  local speed = value.syncSpeed or value.speed
  if not vector(own) or not vector(value.position) or not finite(speed) or speed < 16 or speed > 1000 then
    return nil
  end
  local ping, raw, count = gameInfo.getAveragePing()
  state.ping, state.pingRaw, state.pingSamples = ping, raw, count
  if not finite(ping) or ping < 0 then
    return nil
  end
  local training = value.mode == "training"
  local radius = training and 8.5 or state.player:GetAttribute("DeflectRange")
  radius = finite(radius) and math.clamp(radius, 8.5, 16) or 8.5
  local delta = value.position - own
  local distance = delta.Magnitude
  local ownVelocity = vector(state.root.AssemblyLinearVelocity) and state.root.AssemblyLinearVelocity or Vector3.zero
  local closing = speed
  if vector(value.velocity) then
    closing = distance > 0.001 and -(value.velocity - ownVelocity):Dot(delta) / distance or speed
  end
  if not finite(closing) then
    return nil
  end
  local entry = closing > 0 and math.max(0, distance - radius) / closing or (distance <= radius and 0 or math.huge)
  local configured = tonumber(utils.getConfigValue("AutoParryWindowFactor"))
  local base = finite(explicitFactor) and explicitFactor or (finite(configured) and configured or POLICY.DEFAULT_FACTOR)
  base = math.clamp(base, 0, POLICY.MAX_FACTOR)
  local factor = explicitFactor ~= nil and base or adaptiveFactor(entry, closing, speed, base, now, ping)
  local window
  if training then
    window = gameInfo.getTrainingWindow(speed)
  else
    local low, high = gameInfo.getBallSpeedLimits()
    if not finite(low) or not finite(high) or high <= low then
      return nil
    end
    window = POLICY.SLOW_WINDOW + (POLICY.FAST_WINDOW - POLICY.SLOW_WINDOW) * math.clamp((speed - low) / (high - low), 0, 1)
    if state.clash then
      local native = geometry.getDeflectWindow(speed, false)
      if finite(native) and native > 0 then
        window = math.min(window, native)
      end
    end
  end
  if not finite(window) or window <= 0 then
    return nil
  end
  local lead = window * factor + ping
  local threshold = radius + math.max(0, closing) * lead
  return {
    speed = speed,
    distance = distance,
    closingSpeed = closing,
    noWindowParryRadius = radius,
    fullRadius = threshold,
    triggerDistance = threshold,
    windowFactor = factor,
    deflectWindow = window,
    effectiveWindow = lead,
    timeToRange = entry,
    timeToTrigger = math.max(0, entry - lead),
    ready = distance <= radius or (closing > 0 and distance <= threshold),
    approaching = closing > 0,
    timeToKill = closing > 0 and math.max(0, distance - 4) / closing or math.huge,
  }
end
local function cooldownState(mode) return mode == "training" and cooldown.getTrainingCooldownState() or cooldown.getDeflectCooldownState() end
local function ready(cd, mode, clash)
  if not cd then
    return false
  end
  if mode == "training" then
    return cd.blocking == false
  end
  return (cd.source == "local" or cd.source == "server") and (cd.blocking == false or (clash and cd.source == "local" and cd.miss ~= true))
end
local function usable(value)
  return gameInfo.isSnapshotValid(value)
    and not value.locked
    and value.ballCanMove ~= false
    and not value.frozen
    and (value.mode == "training" or gameInfo.getGameContext().inMatch)
end
local function recover(value, cd, now)
  local shot = state.shot
  if not state.fired or not shot then
    return
  end
  local training = state.mode == "training"
  local confirmed = training and value.trainingParryAt or cd.lastParriedAt
  if training and ready(cd, state.mode, false) and not finite(confirmed) then
    state.fired, state.shot = false, nil
    return
  end
  if cd.miss == true and cd.blocking == false and finite(cd.pressAt) and cd.pressAt >= shot.at - 0.001 then
    state.fired, state.shot = false, nil
    return
  end
  if not finite(confirmed) or confirmed <= state.consumedParry or (training and confirmed == shot.trainingConfirmation) then
    return
  end
  if (not training and confirmed < shot.at) or (training and confirmed < shot.serverTime) then
    return
  end
  if (training and value.targetId ~= state.player.UserId) or (not training and value.exchangeTargetId ~= state.player.UserId) then
    return
  end
  local version = value.syncVersion or value.syncSequence
  if not finite(version) or not finite(shot.version) or version == shot.version then
    return
  end
  local floor = training and confirmed - gameInfo.getAveragePing()
    or utils.getWorkspace():GetServerTimeNow() - math.max(0, now - confirmed) - gameInfo.getAveragePing()
  if not finite(value.serverTime) or value.serverTime <= shot.serverTime or value.serverTime < math.max(shot.serverTime, floor) then
    return
  end
  local predicted = gameInfo.getParrySnapshot(now, true, true, state.tracker.floor)
  if not predicted or predicted.ball ~= state.ball or not vector(predicted.velocity) then
    return
  end
  local delta = predicted.position - state.root.Position
  local incoming = delta:Dot(predicted.velocity - state.root.AssemblyLinearVelocity) < 0
  if not incoming and delta:Dot(delta) <= 8.5 * 8.5 and vector(value.syncDirection) and vector(value.realPosition) then
    incoming = (value.realPosition - state.root.Position):Dot(value.syncDirection) < 0
  end
  if not incoming then
    return
  end
  state.consumedParry = confirmed
  state.tracker.rearm(math.max(shot.serverTime, floor))
  state.fired, state.shot = false, nil
  observe(value, now)
  state.confirmedReturns = (state.confirmedReturns or 0) + 1
  phase("confirmed_return")
end
local function manualStamp(now)
  local stamp = gameInfo.getLastAcceptedDeflectAt()
  return finite(stamp) and stamp > state.episodeAt and stamp <= now and stamp ~= state.lastOwnPress and stamp or nil
end
local function dispatch(value, now)
  local repeatClash = state.mode ~= "training" and state.clash
  if sending or (state.fired and not repeatClash) then
    return false
  end
  local interval = state.mode == "training" and POLICY.TRAINING_INTERVAL or POLICY.NATIVE_INTERVAL
  local accepted = state.mode ~= "training" and gameInfo.getLastAcceptedDeflectAt()
  if now - (state.lastAttemptAt or -math.huge) < interval or (finite(accepted) and now - accepted < interval) then
    return false
  end
  local limit = utils.getWorkspace():GetAttribute("CPS_LIMIT")
  if state.mode == "training" and rate(now) >= (finite(limit) and limit or 16) then
    return false
  end
  local generation, cycle, ball, mode = state.generation, state.cycle, state.ball, state.mode
  local function guard()
    if generation ~= state.generation or cycle ~= state.cycle or not live() then
      return false
    end
    if mode ~= "training" and utils.isSpamActive() then
      return false
    end
    local current = gameInfo.getParrySnapshot(clock(), true, false, state.tracker.floor)
    if not usable(current) or current.ball ~= ball or (current.mode == "training" and "training" or "match") ~= mode then
      return false
    end
    local cd = cooldownState(mode)
    if not ready(cd, mode, mode ~= "training" and gameInfo.isNativeClash()) then
      return false
    end
    if mode ~= "training" and manualStamp(clock()) then
      return false
    end
    local t = timing(current, clock())
    return t ~= nil and t.ready
  end
  sending, state.lastAttemptAt = true, now
  local ok, sent, detail = pcall(remote.fireCheckedParry, guard)
  sending = false
  if not utils or not utils.isActive() then
    return false
  end
  if not ok then
    if now - errorAt >= 1 then
      errorAt = now
      utils.recordError("AutoParry", tostring(sent))
    end
    phase("dispatch_error")
    return false
  end
  if sent ~= true then
    if generation == state.generation and cycle == state.cycle then
      phase(detail or "dispatch_declined")
    end
    return false
  end
  state.acceptedCalls = (state.acceptedCalls or 0) + 1
  if repeatClash then
    state.clashCalls = (state.clashCalls or 0) + 1
  end
  rate(now, true)
  if generation ~= state.generation or cycle ~= state.cycle then
    return true
  end
  local nativeStamp = gameInfo.getLastAcceptedDeflectAt()
  state.fired, state.lastFireAt, state.lastOwnPress = true, now, nativeStamp
  state.shot = {
    at = now,
    serverTime = finite(value.serverTime) and value.serverTime or -math.huge,
    version = value.syncVersion or value.syncSequence,
    trainingConfirmation = value.trainingParryAt,
  }
  state.lastClickAt = now
  if mode == "training" then
    cooldown.recordTrainingDeflectAttempt(now)
  else
    cooldown.recordDeflectAttempt(nativeStamp or now)
  end
  phase("awaiting_return")
  return true
end
local function tick()
  if not live() then
    phase("inactive")
    return false
  end
  local now = clock()
  local value = gameInfo.getSnapshotAt(now)
  if not usable(value) then
    phase("snapshot_unavailable")
    return false
  end
  local targeted = observe(value, now)
  state.clash = state.mode ~= "training" and gameInfo.isNativeClash()
  if state.mode ~= "training" and utils.isSpamActive() then
    state.wasSpamActive = true
    phase("spam_active")
    return false
  end
  if state.wasSpamActive then
    state.lastOwnPress, state.wasSpamActive = gameInfo.getLastAcceptedDeflectAt(), false
  end
  local cd = cooldownState(state.mode)
  if not cd then
    phase("cooldown_unknown")
    return false
  end
  recover(value, cd, now)
  targeted = state.known and state.target == state.player.UserId
  if not targeted then
    phase("not_target")
    return false
  end
  if state.fired and not state.clash then
    phase("awaiting_return")
    return false
  end
  local manual = state.mode ~= "training" and manualStamp(now)
  if manual then
    state.fired, state.lastFireAt, state.lastOwnPress = true, manual, manual
    state.shot = {
      at = manual,
      serverTime = value.serverTime or -math.huge,
      version = value.syncVersion or value.syncSequence,
      trainingConfirmation = value.trainingParryAt,
    }
    cooldown.recordDeflectAttempt(manual)
    if not state.clash then
      phase("manual_deflect")
      return false
    end
  end
  if not ready(cd, state.mode, state.clash) then
    phase("deflect_cooldown")
    return false
  end
  value = gameInfo.getParrySnapshot(now, true, false, state.tracker.floor)
  if not usable(value) then
    phase("snapshot_changed")
    return false
  end
  local t = timing(value, now)
  if not t then
    phase("timing_unavailable")
    return false
  end
  state.timing, state.factor, state.factorAt, state.timingAt = t, t.windowFactor, now, now
  if not t.ready then
    phase("outside_window")
    return false
  end
  return dispatch(value, now)
end
local function evaluate()
  if evaluating or sending then
    return false
  end
  evaluating = true
  local ok, result = pcall(tick)
  evaluating = false
  if not ok then
    local now = clock()
    if utils and now - errorAt >= 1 then
      errorAt = now
      utils.recordError("AutoParry", tostring(result))
    end
    phase("evaluation_error")
    return false
  end
  return result == true
end
function AutoParry.step(dt)
  if finite(dt) and dt > 0 then
    state.frameTime = math.clamp(dt, 1 / 240, 0.12)
    state.visualFrame = (state.visualFrame or 0) + 1
  end
  return evaluate()
end
function AutoParry.isDeadlineDue()
  local t = state.timing
  return live()
    and state.reason == "outside_window"
    and not utils.isSpamActive()
    and t ~= nil
    and finite(t.timeToTrigger)
    and clock() >= (state.timingAt or clock()) + t.timeToTrigger
end
function AutoParry.setup(deps)
  AutoParry.teardown()
  utils, gameInfo, geometry, cooldown, remote, targeting = deps.Utils, deps.GameInfo, deps.DeflectGeometry, deps.Cooldown, deps.Remote, deps.Targeting
  state.tracker = targeting.createParryTracker()
  state.acceptedCalls, state.clashCalls, state.confirmedReturns = 0, 0, 0
  return true
end
function AutoParry.bindCharacter(character)
  AutoParry.detachCharacter()
  local root = character and character:FindFirstChild("HumanoidRootPart")
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  if not root or not humanoid or not character.Parent or humanoid.Health <= 0 then
    return false, "personagem incompleto"
  end
  state.character, state.root, state.humanoid, state.player, state.bound = character, root, humanoid, utils.getLocalPlayer(), true
  state.ball, state.mode, state.round, state.visualFrame = nil, nil, nil, 0
  state.frameTime, state.lastAttemptAt, state.lastSyncAt, state.syncInterval = 1 / 60, -math.huge, nil, nil
  resetFlight("character_bound")
  local generation = state.generation
  track(character.AncestryChanged:Connect(function(_, parent)
    if not parent and generation == state.generation then
      AutoParry.detachCharacter()
    end
  end))
  track(humanoid.Died:Connect(function()
    if generation == state.generation then
      AutoParry.detachCharacter()
    end
  end))
  return true
end
function AutoParry.detachCharacter()
  state.generation += 1
  state.bound = false
  for _, c in ipairs(state.connections) do
    if utils then
      utils.untrackCharacter(c)
    end
    c:Disconnect()
  end
  table.clear(state.connections)
  state.character, state.root, state.humanoid, state.player, state.ball = nil, nil, nil, nil, nil
  resetFlight("detached")
end
function AutoParry.resetState() AutoParry.detachCharacter() end
function AutoParry.teardown()
  AutoParry.detachCharacter()
  state.tracker = nil
  utils, gameInfo, geometry, cooldown, remote, targeting = nil, nil, nil, nil, nil, nil
  table.clear(calls)
  firstCall, lastCall, state.cps, state.maxCps = 1, 0, 0, 0
end
function AutoParry.onBallSync(data)
  if not state.bound or type(data) ~= "table" then
    return true
  end
  if data.Source ~= "target" and data.Source ~= "clash" then
    local now = clock()
    if data.Teleported then
      resetFlight("teleport")
    end
    if state.lastSyncAt and now > state.lastSyncAt then
      state.syncInterval = now - state.lastSyncAt
    end
    state.lastSyncAt = now
  end
  if live() then
    local value = gameInfo.getSnapshotAt(clock())
    if usable(value) then
      observe(value, clock())
    end
  end
  evaluate()
  return true
end
function AutoParry.fire() return evaluate() end
function AutoParry.tryRedirectReturn() return evaluate() end
function AutoParry.beginFierce()
  if not state.bound then
    return nil
  end
  return { generation = state.generation, cycle = state.cycle, startedAt = clock() }
end
function AutoParry.cancelFierce(token) return token ~= nil and token.generation == state.generation end
local function internalTiming(value, time, root, factor)
  if not value then
    return state.timing
  end
  return timing(value, finite(time) and time or clock(), factor, root)
end
function AutoParry.getTargetStatus()
  return {
    armed = not state.fired,
    firedForTarget = state.fired == true,
    lastTargeted = state.target == (state.player and state.player.UserId),
    targeted = state.known == true and state.target == (state.player and state.player.UserId),
    targetId = state.target,
    targetKnown = state.known == true,
    approaching = state.timing and state.timing.approaching or false,
    cooldown = cooldown and cooldownState(state.mode),
  }
end
function AutoParry.getPressureDetector()
  return {
    enabled = utils ~= nil and live() or false,
    ball = state.ball,
    targetId = state.target,
    cycle = state.cycle,
    firedForTarget = state.fired == true,
    attemptAt = state.lastFireAt,
    frameTime = state.frameTime or 1 / 60,
    syncInterval = state.syncInterval,
    ping = state.ping or 0,
    retryAt = 0,
  }
end
function AutoParry.getDefenseState(value)
  local result = AutoParry.getPressureDetector()
  result.armed, result.fired, result.reason, result.lastRequestAt = not state.fired, state.fired == true, state.reason, state.lastFireAt
  local cd = cooldown and cooldownState(state.mode)
  result.blocking, result.lastParriedAt = cd and cd.blocking == true, cd and cd.lastParriedAt
  return result
end
function AutoParry.getPressure() return { latestReturnTime = state.returnInterval, samples = state.lastClickAt and 1 or 0, cps = state.cps or 0 } end
function AutoParry.getStatus()
  rate(clock())
  local t = internalTiming()
  return {
    available = t ~= nil,
    schema = utils and utils.apiVersion(),
    api = {
      name = "AutoParry",
      version = 16,
      endpoints = { "getStatus", "getTargetStatus" },
    },
    lifecycle = {
      phase = state.phase,
      reason = state.reason,
      bound = state.bound,
      alive = state.bound and state.humanoid.Health > 0,
      generation = state.generation,
    },
    target = AutoParry.getTargetStatus(),
    mode = state.mode,
    ping = {
      oneWay = state.ping or 0,
      raw = state.pingRaw,
      samples = state.pingSamples or 0,
    },
    cps = state.cps or 0,
    maxObservedCps = state.maxCps or 0,
    nativeClash = state.clash == true,
    acceptedClientCalls = state.acceptedCalls or 0,
    nativeClashCalls = state.clashCalls or 0,
    confirmedReturns = state.confirmedReturns or 0,
    pressure = AutoParry.getPressure(),
    cycle = {
      fired = state.fired == true,
      armed = not state.fired,
      lastFireAt = state.lastFireAt,
    },
    training = {
      active = state.mode == "training",
    },
    timestamp = clock(),
  }
end
AutoParry.__contract = {
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    DeflectGeometry = "deflectgeometry",
    Cooldown = "cooldown",
    Remote = "remote",
    Targeting = "targeting",
  },
  requiresMethods = {
    Targeting = { "createParryTracker" },
    Utils = {
      "getWorkspace",
      "getLocalPlayer",
      "getRunService",
      "getConfigValue",
      "isActive",
      "isSpamActive",
      "trackCharacter",
      "untrackCharacter",
      "recordError",
      "apiVersion",
    },
    GameInfo = {
      "getSnapshotAt",
      "getParrySnapshot",
      "isSnapshotValid",
      "getGameContext",
      "getTrainingWindow",
      "isNativeClash",
      "getLastAcceptedDeflectAt",
      "isSnapshotAfterDeflect",
      "getAveragePing",
      "getBallSpeedLimits",
      "getRootPosition",
      "getLastDeflectPressAt",
      "observeTraining",
    },
    DeflectGeometry = { "getParryTiming", "getDefensePhysics", "getDeflectWindow" },
    Cooldown = { "getDeflectCooldownState", "getTrainingCooldownState", "recordDeflectAttempt", "recordTrainingDeflectAttempt", "observeDeflect" },
    Remote = { "fireCheckedParry" },
  },
  provides = {
    "step",
    "isDeadlineDue",
    "setup",
    "teardown",
    "bindCharacter",
    "detachCharacter",
    "resetState",
    "onBallSync",
    "fire",
    "tryRedirectReturn",
    "beginFierce",
    "cancelFierce",
    "getTargetStatus",
    "getPressureDetector",
    "getDefenseState",
    "getPressure",
    "getStatus",
  },
  bindCharacter = true,
  version = 16,
}

return AutoParry
