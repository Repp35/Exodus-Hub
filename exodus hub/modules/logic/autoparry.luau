-- [[ autoparry ]]

-- code
local AutoParry = {}
local utils, gameInfo, geometry, cooldown, remote, autoSpam
local state = { generation = 0, cycle = 0, bound = false, connections = {}, phase = "detached", reason = "initial" }
local evaluating, sending = false, false
local errorAt = -math.huge
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function clock() return os.clock() end
local function phase(reason)
  state.phase, state.reason = state.bound and "waiting" or "detached", reason
end
local function track(c)
  state.connections[#state.connections + 1] = c; utils.trackCharacter(c)
end
local function resetFlight(reason)
  state.cycle += 1; state.fired, state.shot, state.departed, state.target, state.known = false, nil, false, -1, false
  state.timing, state.lastOwnPress, state.returnInterval, state.returnAt = nil, nil, nil, nil; state.factor, state.factorAt, state.wasSpamActive = nil, nil, false
  state.episodeAt, state.consumedParry = clock(), -math.huge; phase(reason)
end
local function live()
  return state.bound
    and state.character
    and state.character.Parent
    and state.root
    and state.root.Parent
    and state.humanoid
    and state.humanoid.Health > 0
    and utils.isActive()
    and utils.getConfigValue("AutoParry") ~= false
end
local function observe(value, now)
  local mode = value.mode == "training" and "training" or "match"
  if state.ball ~= value.ball or state.mode ~= mode or (mode == "training" and state.round ~= value.trainingRound) then
    resetFlight("new_ball"); state.ball, state.mode, state.round = value.ball, mode, value.trainingRound
  end
  local target = value.targetId
  if value.targetUncertain or not finite(target) or target <= 0 then state.known = false; return end
  local me = state.player.UserId
  if target ~= me then
    if state.target == me then state.departed, state.awayAt = true, now end
  elseif state.departed then
    state.cycle += 1; state.fired, state.shot, state.departed = false, nil, false
    state.returnInterval = state.awayAt and now - state.awayAt or nil; state.returnAt, state.episodeAt = now, now
  end
  state.target, state.known = target, true
end
local POLICY = { SLOW_WINDOW = 0.5, FAST_WINDOW = 0.3, DEFAULT_FACTOR = 0.3, MAX_FACTOR = 0.85 }
local function adaptiveFactor(t, base, now, ping)
  local pressure = 0; local interval = state.returnInterval
  local age = state.returnAt and now - state.returnAt
  if finite(interval) and interval > 0 and finite(age) and age >= 0 and age <= math.min(1.5, math.max(0.1, interval) * 2) then pressure = 1 - math.clamp((interval - 0.1) / 0.8, 0, 1) end
  local budget = ping + (state.frameTime or 1 / 60)
  if finite(t.timeToRange) then pressure = math.max(pressure, math.clamp((budget - t.timeToRange) / math.max(budget, 0.001), 0, 1)) end
  pressure = math.max(pressure, math.clamp(t.closingSpeed / math.max(t.speed, 1) - 1, 0, 1)); local desired = base + (POLICY.MAX_FACTOR - base) * pressure
  if finite(state.factor) and state.factor > desired then desired += (state.factor - desired) * math.exp(-math.max(0, now - (state.factorAt or now)) / 0.25) end
  return math.clamp(desired, base, POLICY.MAX_FACTOR)
end
local function timing(value, now, factor, own)
  local configured = tonumber(utils.getConfigValue("AutoParryWindowFactor")); local base = finite(factor) and factor or (finite(configured) and configured or POLICY.DEFAULT_FACTOR)
  base = math.clamp(base, 0, POLICY.MAX_FACTOR); local ping, raw, samples = gameInfo.getAveragePing()
  state.ping, state.pingRaw, state.pingSamples = ping, raw, samples
  local window
  if value.mode ~= "training" then
    local low, high = gameInfo.getBallSpeedLimits(); local speed = value.syncSpeed or value.speed
    if not finite(low) or not finite(high) or high <= low or not finite(speed) then return nil end
    window = POLICY.SLOW_WINDOW + (POLICY.FAST_WINDOW - POLICY.SLOW_WINDOW) * math.clamp((speed - low) / (high - low), 0, 1)
    if geometry.getDefensePhysics().inClash then window = math.min(window, geometry.getDeflectWindow(speed, false)) end
  end
  local options = {
    factor = base,
    window = window,
    ping = ping,
    frameLead = state.frameTime or 1 / 60,
    rootVelocity = state.root and state.root.AssemblyLinearVelocity,
    maxWindowLead = window and window * 0.95,
  }

  own = own or gameInfo.getRootPosition(state.root); local t = geometry.getParryTiming(value, own, options)
  if not t then return nil end
  if value.mode == "training" then options.maxWindowLead = t.deflectWindow * 0.8 end
  if factor == nil then options.factor = adaptiveFactor(t, base, now, ping) end
  if options.factor ~= base or value.mode == "training" then return geometry.getParryTiming(value, own, options) end
  return t
end
local function cooldownState(mode)
  if mode == "training" then return cooldown.getTrainingCooldownState() end
  return cooldown.getDeflectCooldownState()
end
local function ready(cd, mode) return cd ~= nil and cd.blocking == false and (mode == "training" or cd.source == "local" or cd.source == "server") end
local function recover(value, cd, now)
  local shot = state.shot
  if not state.fired or not shot then return end
  local confirmed = state.mode == "training" and value.trainingParryAt or cd.lastParriedAt
  local acknowledged = finite(confirmed) and confirmed >= (state.mode == "training" and shot.serverTime or shot.at)
  if state.mode == "training" and ready(cd, state.mode) and not acknowledged then
    state.fired, state.shot = false, nil; phase("training_cooldown_finished")
    return
  end
  if ready(cd, state.mode) and cd.miss == true and not acknowledged and finite(cd.pressAt) and cd.pressAt >= shot.at - 0.001 and cd.pressAt <= now then
    state.fired, state.shot = false, nil; phase("cooldown_finished")
    return
  end
  if not acknowledged or confirmed <= state.consumedParry or not finite(value.serverTime) or value.serverTime <= shot.serverTime then return end
  if state.mode ~= "training" and not gameInfo.isSnapshotAfterDeflect(value, confirmed) then return end
  local predicted = gameInfo.getDefenseSnapshot(now)
  if not predicted or predicted.ball ~= state.ball then return end
  local current = timing(predicted, now)
  if not current or not current.approaching then return end
  state.consumedParry, state.fired, state.shot = confirmed, false, nil; state.cycle += 1
  state.episodeAt = now; phase("confirmed_return")
end
local function observeManual(now)
  if state.mode == "training" then return false end
  local stamp = gameInfo.getLastDeflectPressAt(); return finite(stamp) and stamp > state.episodeAt and stamp <= now and stamp ~= state.lastOwnPress and stamp or nil
end
local evaluate
local function dispatch(value, now)
  if sending or state.fired then return false end
  local generation, cycle, ball, mode = state.generation, state.cycle, state.ball, state.mode
  local function guard()
    if generation ~= state.generation or cycle ~= state.cycle or not live() then return false end
    local current = gameInfo.getDefenseSnapshot(clock())
    if not current or current.ball ~= ball or (current.mode == "training" and "training" or "match") ~= mode then return false end
    if current.targetId ~= state.player.UserId then return false end
    if mode ~= "training" then
      autoSpam.onDefenseOpportunity(current)
      if utils.isSpamActive() then return false end
    end
    if not ready(cooldownState(mode), mode) or observeManual(clock()) then return false end
    local t = timing(current, clock()); return t ~= nil and t.ready
  end
  sending = true; local ok, sent, detail = pcall(remote.fireCheckedParry, guard)
  sending = false
  if generation ~= state.generation or cycle ~= state.cycle then return false end
  if not ok then
    if now - errorAt >= 1 then errorAt = now; utils.recordError("AutoParry", tostring(sent)) end
    phase("dispatch_error"); return false
  end
  if sent ~= true then phase(detail or "dispatch_declined"); return false end
  state.fired, state.lastFireAt = true, now; state.shot = { at = now, serverTime = finite(value.serverTime) and value.serverTime or -math.huge }
  state.lastOwnPress = gameInfo.getLastDeflectPressAt(); local previous = state.lastClickAt
  state.lastClickAt = now; state.cps = previous and now > previous and 1 / (now - previous) or 0
  state.maxCps = math.max(state.maxCps or 0, state.cps)
  if mode == "training" then cooldown.recordTrainingDeflectAttempt(now) else cooldown.recordDeflectAttempt(now) end
  phase("awaiting_return"); return true
end
local function tick()
  if not live() then phase("inactive"); return false end
  local now = clock(); local value, reason = gameInfo.getDefenseSnapshot(now, false)
  if not value then phase(reason or "snapshot_unavailable"); return false end
  observe(value, now)
  if state.mode ~= "training" then
    autoSpam.onDefenseOpportunity(value)
    if utils.isSpamActive() then
      state.wasSpamActive = true; phase("spam_active")
      return false
    end
    if state.wasSpamActive then state.lastOwnPress, state.wasSpamActive = gameInfo.getLastDeflectPressAt(), false end
  end
  if not state.known or state.target ~= state.player.UserId then phase("not_target"); return false end
  local cd = cooldownState(state.mode)
  if not cd then phase("cooldown_unknown"); return false end
  recover(value, cd, now)
  if state.fired then phase("awaiting_return"); return false end
  local manual = observeManual(now)
  if manual then
    state.fired, state.lastFireAt, state.lastOwnPress = true, manual, manual; state.shot = { at = manual, serverTime = finite(value.serverTime) and value.serverTime or -math.huge }
    cooldown.recordDeflectAttempt(manual); phase("manual_deflect")
    return false
  end
  if not ready(cd, state.mode) then phase("deflect_cooldown"); return false end
  value = gameInfo.getDefenseSnapshot(now)
  if not value or value.ball ~= state.ball or value.targetId ~= state.player.UserId then phase("snapshot_changed"); return false end
  local t = timing(value, now)
  if not t then phase("timing_unavailable"); return false end
  state.timing, state.factor, state.factorAt = t, t.windowFactor, now
  if not t.ready then phase("outside_window"); return false end
  return dispatch(value, now)
end
function evaluate()
  if evaluating or sending then return false end
  evaluating = true; local ok, result = pcall(tick)
  evaluating = false
  if not ok then
    local now = clock()
    if now - errorAt >= 1 then errorAt = now; utils.recordError("AutoParry", tostring(result)) end
    phase("evaluation_error"); return false
  end
  return result == true
end
function AutoParry.setup(deps)
  if type(deps) ~= "table" then return false, "dependências ausentes" end
  for _, name in ipairs({ "Utils", "GameInfo", "DeflectGeometry", "Cooldown", "Remote", "AutoSpam" }) do
    if type(deps[name]) ~= "table" then return false, "dependência ausente: " .. name end
  end
  AutoParry.teardown(); utils, gameInfo, geometry, cooldown, remote, autoSpam = deps.Utils, deps.GameInfo, deps.DeflectGeometry, deps.Cooldown, deps.Remote, deps.AutoSpam
  return true
end
function AutoParry.bindCharacter(character)
  if not utils then return false, "AP não inicializado" end
  AutoParry.detachCharacter()
  if not character or not character.Parent then return false, "personagem indisponível" end
  local generation = state.generation; local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if generation ~= state.generation or not root or not root.Parent or not humanoid or humanoid.Health <= 0 then return false, "personagem incompleto" end
  local service = utils.getRunService()
  if not service or not service.Heartbeat or not utils.getLocalPlayer() then return false, "RunService ou jogador indisponível" end
  state.character, state.root, state.humanoid, state.player, state.bound = character, root, humanoid, utils.getLocalPlayer(), true
  state.frameTime, state.lastSyncAt, state.syncInterval = 1 / 60, nil, nil; state.ball, state.mode, state.round, state.cps, state.lastClickAt, state.lastFireAt = nil, nil, nil, 0, nil, nil
  resetFlight("character_bound")
  local function pulse(dt)
    if generation ~= state.generation then return end
    if finite(dt) and dt > 0 then state.frameTime = math.clamp(dt, 1 / 240, 0.12) end
    evaluate()
  end
  for _, name in ipairs({ "PreSimulation", "PostSimulation", "Heartbeat" }) do
    if service[name] then track(service[name]:Connect(pulse)) end
  end
  track(gameInfo.observeTraining(pulse)); track(cooldown.observeDeflect(pulse))
  track(character.AncestryChanged:Connect(function(_, parent)
    if generation == state.generation and not parent then AutoParry.detachCharacter() end
  end))
  track(humanoid.Died:Connect(function()
    if generation == state.generation then AutoParry.detachCharacter() end
  end))
  return true
end
function AutoParry.detachCharacter()
  state.generation += 1; state.bound = false
  for _, c in ipairs(state.connections) do
    if utils then utils.untrackCharacter(c) end
    c:Disconnect()
  end
  table.clear(state.connections); state.character, state.root, state.humanoid, state.ball, state.mode, state.round = nil, nil, nil, nil, nil, nil
  resetFlight("detached")
end
function AutoParry.resetState() AutoParry.detachCharacter() end
function AutoParry.teardown()
  AutoParry.detachCharacter(); utils, gameInfo, geometry, cooldown, remote, autoSpam = nil, nil, nil, nil, nil, nil
end
function AutoParry.onBallSync(data)
  if not state.bound or type(data) ~= "table" then return true end
  local now = clock()
  if data.Source ~= "target" and data.Source ~= "clash" then
    if data.Teleported then resetFlight("teleport"); return true end
    if state.lastSyncAt and now > state.lastSyncAt then state.syncInterval = now - state.lastSyncAt end
    state.lastSyncAt = now
  end
  evaluate(); return true
end
function AutoParry.fire() return evaluate() end
function AutoParry.tryRedirectReturn() return evaluate() end
function AutoParry.beginFierce()
  if not state.bound then return nil end
  return { generation = state.generation, cycle = state.cycle, startedAt = clock() }
end
function AutoParry.cancelFierce(token) return token ~= nil and token.generation == state.generation end
function AutoParry.getTiming(value, time, root, factor)
  if not gameInfo or not state.root then return nil end
  time = finite(time) and time or clock(); value = value or gameInfo.getDefenseSnapshot(time)
  return value and timing(value, time, factor, root) or nil
end
function AutoParry.getRadius(mode, factor, speedOverride)
  local t = AutoParry.getTiming(nil, nil, nil, factor)
  if not t then return nil end
  if finite(speedOverride) and speedOverride ~= t.speed then
    local current = gameInfo.getDefenseSnapshot(clock())
    if not current then return nil end
    local value = table.clone(current); value.speed, value.syncSpeed = speedOverride, speedOverride
    t = AutoParry.getTiming(value, nil, nil, factor)
    if not t then return nil end
  end
  t.mode, t.value = mode or "geometry", mode == "tti" and t.tti or t.fullRadius
  if mode == "speed_distance" then t.value = { speed = t.speed, distance = t.distance } end
  return t
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
  local result = AutoParry.getPressureDetector(); local t = AutoParry.getTiming(value)
  result.armed, result.fired, result.reason, result.lastRequestAt = not state.fired, state.fired == true, state.reason, state.lastFireAt
  result.triggerDistance, result.distance, result.closingSpeed = t and t.triggerDistance, t and t.distance, t and t.closingSpeed
  result.timeToKill, result.windowFactor = t and t.timeToKill, t and t.windowFactor
  local cd = cooldown and cooldownState(state.mode); result.blocking, result.lastParriedAt = cd and cd.blocking == true, cd and cd.lastParriedAt
  return result
end
function AutoParry.getPressure()
  return { latestReturnTime = state.returnInterval, currentFactor = state.factor, samples = state.lastClickAt and 1 or 0, cps = state.cps or 0 }
end
function AutoParry.getStatus()
  local t = AutoParry.getRadius("geometry")
  return {
    available = t ~= nil,
    schema = utils and utils.apiVersion(),
    api = {
      name = "AutoParry",
      version = 15,
      endpoints = { "getRadius", "getTiming", "getStatus", "getTargetStatus" },
    },
    lifecycle = {
      phase = state.phase,
      reason = state.reason,
      bound = state.bound,
      alive = state.bound and state.humanoid.Health > 0,
      generation = state.generation,
    },
    radius = t,
    resilience = t and t.resilience,
    timing = t,
    target = AutoParry.getTargetStatus(),
    mode = state.mode,
    ping = {
      oneWay = state.ping or 0,
      raw = state.pingRaw,
      samples = state.pingSamples or 0,
    },
    cps = state.cps or 0,
    maxObservedCps = state.maxCps or 0,
    windowFactor = t and t.windowFactor,
    pressure = AutoParry.getPressure(),
    cycle = {
      fired = state.fired == true,
      armed = not state.fired,
      lastFireAt = state.lastFireAt,
    },
    training = {
      active = state.mode == "training",
      triggerDistance = state.mode == "training" and t and t.triggerDistance,
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
    AutoSpam = "autospam",
  },
  requiresMethods = {
    Utils = {
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
      "getDefenseSnapshot",
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
    AutoSpam = { "onDefenseOpportunity" },
  },
  provides = {
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
    "getTiming",
    "getRadius",
    "getTargetStatus",
    "getPressureDetector",
    "getDefenseState",
    "getPressure",
    "getStatus",
  },
  bindCharacter = true,
  onBallSync = true,
  version = 15,
}

return AutoParry
