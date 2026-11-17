-- [[ auto spam ]]

local AutoSpam = {}

local utils, gameInfo, clashStatsModule, players, runService, localPlayer, cooldownInfo, dashInfo
local autoParry
local current, generation = nil, 0
local clashStats
local lastActivationReason, lastActivationAt, lastStopReason, lastStopAt
local CONFIG = {
  ACTIVATION = {
    PRESSURE_REFERENCE_CPS = 4.73,
    PRESSURE_MAX_AGE = 0.75,
    RETURN = 0.36,
    SELF_RETURN_MIN_TIME = 0.30,
    SELF_RETURN_MAX_TIME = 0.10,
    SELF_RETURN_DIRECTION_RATIO = 0.12,
    REACTIVATION_DELAY = 0.02,
    CLOSE_TARGET_DISTANCE = 5,
    CLOSE_INSTANT_DISTANCE = 2,
    CLOSE_OPPONENT_DISTANCE = 16,
    MAX_CLASH_DISTANCE = 35,
    RADIUS_FACTOR = 1,
    HAUNTER_RANGE = 11,
    HAUNTER_MATCH_RADIUS = 5,
    HAUNTER_LIFETIME = 0.15,
    DASH_WINDOW_FACTOR = 1,
    DASH_ESCAPE_WINDOW_FACTOR = 0.4,
    DASH_MAX_SNAPSHOT_AGE = 0.15,
    DASH_MIN_ALIGNMENT = 0.6,
    DASH_DETECTION_RANGE = 70,
  },
  DEACTIVATION = {
    PROTECTION_RADIUS = 14,
    MAX_CLASH_DISTANCE = 35,
    DASH_ESCAPE_COOLDOWN = 0.05,
    DASH_ESCAPE_MIN_OUTWARD_SPEED = 15,
    DASH_ESCAPE_MIN_HORIZONTAL_RATIO = 0.35,
    DASH_ESCAPE_MIN_SEPARATION_GAIN = 2,
    CLASH_DISTANCE_TIMEOUT = 0.25,
    TARGET_RETURN_TIMEOUT = 0.18,
    RETURN_PROTECTION_RADIUS = 10,
    RETURN_PROTECTION_MAX_SPEED_RADIUS = 25,
  },
  SHARED = { SNAPSHOT_MAX_AGE = 0.5, RUNTIME_TICK_INTERVAL = 1 / 120 },
}

local function finite(x) return type(x) == "number" and x == x and x > -math.huge and x < math.huge end
local function vector(x) return typeof(x) == "Vector3" and finite(x.X) and finite(x.Y) and finite(x.Z) end
local function validSpeed(x) return finite(x) and x >= 0 and x <= 1000 end
local function userId(x) return finite(x) and x > 0 and x % 1 == 0 and x or nil end
local function now() return utils.now() end
local function snapshotSpeed(s)
  if not s then return nil end
  local speed = s.syncSpeed ~= nil and s.syncSpeed or s.speed; return validSpeed(speed) and speed or nil
end
local function networkLatency()
  local ping = gameInfo.getAveragePing(); return finite(ping) and math.clamp(ping * 0.5, 0, 0.25) or 0
end
local function playerIsAlive(id)
  local player = id and players:GetPlayerByUserId(id); local character = player and player.Character
  local humanoid = character and character.Parent and character:FindFirstChildOfClass("Humanoid"); return humanoid ~= nil and finite(humanoid.Health) and humanoid.Health > 0
end
local function playerPosition(id)
  local position = id and gameInfo.getPlayerMotion(id)
  if vector(position) then return position end
  local player = id and players:GetPlayerByUserId(id); local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  return root and root.Parent and vector(root.Position) and root.Position or nil
end
local function listen(state, signal, callback)
  local connection = signal:Connect(callback); state.connections[#state.connections + 1] = connection
  utils.trackCharacter(connection); return connection
end
local function clearEvidence(state)
  state.outbound, state.pending, state.close, state.haunter, state.closeArm = nil, nil, nil, nil, nil
end
local function resetTargets(state)
  clearEvidence(state); state.target, state.previousOpponent, state.selfReturn = nil, nil, nil
  state.killEntryAt, state.riskTarget, state.risk, state.pressure = nil, nil, nil, nil; state.pressureEpoch = now()
end
local function eventOnce(state, reason, condition, token)
  if not condition then state.stopEvents[reason] = nil; return false end
  local previous = state.stopEvents[reason]
  if previous and previous.token == token then return false end
  state.stopEvents[reason] = { token = token }; return true
end
local function deactivate(state, reason, time)
  if current ~= state or not state.active then return false end
  if type(reason) == "string" and (reason:find("window", 1, true) or reason:find("outside_window", 1, true)) then state.lastGate = "window_ignored"; return false end
  if reason == "deflect_miss" or reason == "miss" or reason == "parry_miss" then state.lastGate = "miss_ignored"; return false end
  if reason ~= "disabled" and reason ~= "hub_inactive" and reason ~= "player_died" and reason ~= "opponent_left_or_died" and reason ~= "cooldown" and reason ~= "target_redirected_far" then
    local opponent = playerPosition(state.partner)
    if state.root and state.root.Parent and opponent and (opponent - state.root.Position).Magnitude <= CONFIG.DEACTIVATION.PROTECTION_RADIUS then
      state.lastGate = "near_opponent_protected"; return false
    end
  end
  time = time or now()
  if reason == "opponent_left_or_died" then clashStatsModule.freeze(state.partner, state) end
  state.sendContinuity = nil
  state.active, state.reason, state.partner, state.lastGate = false, reason, nil, reason; state.reactivateAt = time + CONFIG.ACTIVATION.REACTIVATION_DELAY
  lastStopReason, lastStopAt = reason, time; utils.setAutoSpamActive(false)
  utils.recordTransition("AutoSpam", "active", "idle", reason); return true
end
local function monitorCooldown(state) return cooldownInfo.getDeflectCooldownState(), false end
local function sampleGate(state, s, time)
  if not utils.isActive() then return "hub_inactive" end
  if not state.root.Parent or not state.character.Parent or not playerIsAlive(localPlayer.UserId) then return "player_died" end
  if not s or not gameInfo.isSnapshotValid(s) then return "snapshot_invalid" end
  if s.mode == "training" then return "training" end
  if s.targetUncertain or not userId(s.targetId) then return "target_unknown" end
  if not vector(s.position) or not vector(s.velocity) or not validSpeed(s.speed) or not snapshotSpeed(s) then return "ball_data_invalid" end
  if s.syncAt ~= nil and (not finite(s.syncAt) or time < s.syncAt or time - s.syncAt > CONFIG.SHARED.SNAPSHOT_MAX_AGE) then return "snapshot_stale" end
  if s.teleported or s.resetting or s.ballValid == false or s.valid == false then return "ball_reset" end
  if s.locked or s.ballCanMove == false or gameInfo.getBallFrozen() == true then return "ball_paused" end
  if s.realPosition ~= nil then
    if not vector(s.realPosition) then return "position_invalid" end
    local age = finite(s.syncAt) and math.clamp(time - s.syncAt, 0, 0.5) or 0
    if (s.position - s.realPosition).Magnitude > 8 + snapshotSpeed(s) * (age + networkLatency() + 0.15) then return "position_disagreement" end
  end
  if snapshotSpeed(s) <= 0 then return "ball_not_moving" end
end
local function freshSnapshot(s, time)
  return s
    and gameInfo.isSnapshotValid(s)
    and not s.targetUncertain
    and (s.syncAt == nil or (finite(s.syncAt) and time >= s.syncAt and time - s.syncAt <= CONFIG.SHARED.SNAPSHOT_MAX_AGE))
end
local function compensatedRadius(id, speed)
  local radius = gameInfo.getPlayerRawRadius(id, speed, false); return finite(radius) and radius + (id == localPlayer.UserId and speed * networkLatency() or 0) or nil
end
local function geometry(s, factor)
  local speed = snapshotSpeed(s)
  if not speed or speed <= 0 then return nil end
  local g = gameInfo.getDeflectGeometry(speed, "game", factor or 1, false, networkLatency())
  if not g or not finite(g.fullRadius) or not finite(g.effectiveWindow) or not finite(g.deflectWindow) or not finite(g.noWindowParryRadius) then return nil end
  local low, high = gameInfo.getBallSpeedLimits()
  if finite(low) and finite(high) and high > low then
    local fraction = math.clamp((speed - low) / (high - low), 0, 1); local bonus = 0.65 * 0.20 * fraction
    g.deflectWindow += bonus; g.effectiveWindow += bonus * (factor or 1)
    g.fullRadius += speed * bonus * (factor or 1); g.leadTime += bonus
  end
  return g, speed
end
local function ballWindow(state, s, target)
  local position = target == localPlayer.UserId and state.root.Position or playerPosition(target); local g, speed = geometry(s, 1)
  if not vector(position) or not g then return false end
  local delta = position - s.position; local distance = delta.Magnitude
  local range = target == localPlayer.UserId and g.noWindowParryRadius or gameInfo.getPlayerRawRadius(target, speed, false)
  if not finite(range) then return false end
  local closing = distance > 0 and s.velocity:Dot(delta) / distance or 0; local full = target == localPlayer.UserId and g.fullRadius or range + speed * g.effectiveWindow
  return distance <= range or (closing > 0 and distance <= full + closing * g.effectiveWindow)
end
local function nearPartner(state, id, limit)
  if not id or id == localPlayer.UserId or not playerIsAlive(id) then return nil end
  local other = playerPosition(id); return other and (other - state.root.Position).Magnitude <= limit and id or nil
end
local function nearestPartner(state, limit)
  local best, distance
  for _, player in ipairs(players:GetPlayers()) do
    local id = nearPartner(state, player.UserId, limit); local d = id and (playerPosition(id) - state.root.Position).Magnitude
    if d and (not distance or d < distance) then best, distance = id, d end
  end
  return best
end
local function observeTarget(state, s, time)
  local target, previous = s.targetId, state.target
  if target == previous then return end
  local me = localPlayer.UserId; state.close, state.pending = nil, nil
  local arm = state.closeArm
  if arm then
    if previous == me and target == arm.partner then arm.stage = "outbound"
    elseif previous == arm.partner and target == me and arm.stage == "outbound" then arm.stage = "confirmed"
    elseif target ~= me or previous ~= arm.partner then state.closeArm = nil end
  end
  if state.lastSwitchAt then state.intervalMs = (time - state.lastSwitchAt) * 1000 end
  state.target, state.lastSwitchAt = target, time
  if previous == me and target ~= me then
    state.outbound = { partner = target, at = time }; state.departedAt = time
  elseif target == me then
    local outbound = state.outbound
    if outbound and outbound.partner == previous and time >= outbound.at and time - outbound.at <= CONFIG.ACTIVATION.RETURN + networkLatency() then
      state.pending = { partner = previous, at = time }
    end
    state.outbound, state.departedAt = nil, nil; local partner = previous and previous ~= me and previous or nearestPartner(state, CONFIG.ACTIVATION.CLOSE_OPPONENT_DISTANCE)
    state.close = partner and { partner = partner, at = time } or nil
  else
    state.outbound, state.departedAt = nil, nil
  end
  if target ~= me then state.previousOpponent = target elseif previous and previous ~= me then state.previousOpponent = previous end
end
local function opponentOutside(state, radius, maxRadius, s, time)
  local speed = snapshotSpeed(s) or state.protectionSpeed; local minimum, maximum = gameInfo.getBallSpeedLimits()
  if not speed or not finite(minimum) or not finite(maximum) or maximum <= minimum then return false end
  state.protectionSpeed = speed; local limit = radius + (maxRadius - radius) * math.clamp((speed - minimum) / (maximum - minimum), 0, 1)
  local position = playerPosition(state.partner); return position ~= nil and (position - state.root.Position).Magnitude > limit
end
local function dashEscapeRisk(state, tracker, snapshot, time)
  if not state.root or not state.root.Parent or not tracker or not tracker.partner then return nil end
  if not freshSnapshot(snapshot, time) or snapshot.teleported or snapshot.locked or snapshot.targetId ~= tracker.partner then return nil end
  if not finite(snapshot.syncAt) or snapshot.syncAt <= 0 or time < snapshot.syncAt or time - snapshot.syncAt > CONFIG.ACTIVATION.DASH_MAX_SNAPSHOT_AGE then return nil end
  if not playerIsAlive(tracker.partner) then return nil end
  local own = state.root.Position; local other, otherVelocity = gameInfo.getPlayerMotion(tracker.partner)
  if typeof(own) ~= "Vector3" or typeof(other) ~= "Vector3" or typeof(snapshot.velocity) ~= "Vector3" then return nil end
  local delta = other - own; local horizontal = Vector3.new(delta.X, 0, delta.Z)
  local distance = delta.Magnitude; local flatDistance = horizontal.Magnitude
  if not finite(distance) or not finite(flatDistance) or flatDistance < 1 then return nil end
  local speed = snapshotSpeed(snapshot); local g = geometry(snapshot, CONFIG.ACTIVATION.RADIUS_FACTOR)
  local ownRadius, otherRadius = compensatedRadius(localPlayer.UserId, speed), gameInfo.getPlayerRawRadius(tracker.partner, speed, false)
  if not g or not finite(speed) or speed <= 0 or not finite(ownRadius) or not finite(otherRadius) or not finite(g.deflectWindow) then return nil end
  local towardOther = other - snapshot.position
  if snapshot.velocity:Dot(towardOther) <= 0 then return nil end
  local ownWindow = ownRadius + speed * (g.deflectWindow * CONFIG.ACTIVATION.DASH_ESCAPE_WINDOW_FACTOR + networkLatency())
  if (snapshot.position - own).Magnitude <= ownWindow then return nil end
  local localVelocity = state.root.AssemblyLinearVelocity
  if typeof(localVelocity) ~= "Vector3" then localVelocity = Vector3.zero end
  if typeof(otherVelocity) ~= "Vector3" then otherVelocity = Vector3.zero end
  local function candidate(sample, selfDash)
    if not sample or not sample.signalActive or not sample.normalModel or typeof(sample.velocity) ~= "Vector3" then return nil end
    local velocity, remaining = sample.velocity, sample.normalModel.estimatedRemaining; local magnitude = velocity.Magnitude
    local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    if not finite(magnitude) or magnitude < 70 or magnitude > 140 or not finite(remaining) or remaining <= 0 then return nil end
    if horizontalSpeed < magnitude * CONFIG.DEACTIVATION.DASH_ESCAPE_MIN_HORIZONTAL_RATIO then return nil end
    local away = velocity:Dot(horizontal) / flatDistance * (selfDash and -1 or 1)
    if not finite(away) or away < CONFIG.DEACTIVATION.DASH_ESCAPE_MIN_OUTWARD_SPEED then return nil end
    local drift = selfDash and otherVelocity or localVelocity
    if not finite(drift.Magnitude) or drift.Magnitude > 40 then drift = Vector3.zero end
    local relativeVelocity = selfDash and (drift - velocity) or (velocity - drift); local projectedDistance = (delta + relativeVelocity * remaining).Magnitude
    local threshold = ownRadius + otherRadius + speed * g.deflectWindow * CONFIG.ACTIVATION.DASH_ESCAPE_WINDOW_FACTOR
    if
      not finite(projectedDistance)
      or projectedDistance <= threshold
      or projectedDistance - distance < CONFIG.DEACTIVATION.DASH_ESCAPE_MIN_SEPARATION_GAIN
    then
      return nil
    end
    return {
      reason = selfDash and "self_dash_escape" or "opponent_dash_escape",
      eventToken = sample.observedAt,
      distance = distance,
      projectedDistance = projectedDistance,
      threshold = threshold,
    }
  end
  local result = candidate(dashInfo.getEstimate(tracker.partner), false) or candidate(dashInfo.getEstimate(localPlayer.UserId), true)
  if not result then tracker.dashEscapeSince = nil; return nil end
  local cooldown = cooldownInfo.getDeflectCooldownState()
  if not cooldown or cooldown.blocking ~= true or cooldown.source == "unknown" then tracker.dashEscapeSince = nil; return nil end
  local start = finite(cooldown.blockingSince) and cooldown.blockingSince <= time and cooldown.blockingSince or tracker.dashEscapeSince or time
  tracker.dashEscapeSince = tracker.dashEscapeSince or start
  if time - tracker.dashEscapeSince < CONFIG.DEACTIVATION.DASH_ESCAPE_COOLDOWN then return nil end
  return result
end
local function activate(state, reason, partner, time, s)
  if state.active then return false end
  state.active, state.reason, state.partner, state.activatedAt = true, reason, partner, time; state.lastGate = reason
  if s.targetId == partner then state.departedAt = state.departedAt or time end
  lastActivationReason, lastActivationAt = reason, time; clashStatsModule.begin(partner, time)
  clashStats = clashStatsModule.get(); utils.setAutoSpamActive(true)
  utils.recordTransition("AutoSpam", "idle", "active", reason); return true
end
local function sphereEntry(delta, velocity, radius)
  local c = delta:Dot(delta) - radius * radius
  if c <= 0 then return 0 end
  local a = velocity:Dot(velocity); local b = 2 * delta:Dot(velocity)
  if a <= 0.000001 or b >= 0 then return math.huge end
  local discriminant = b * b - 4 * a * c
  if discriminant < 0 then return math.huge end
  return math.max(0, (-b - math.sqrt(discriminant)) / (2 * a))
end
local function observePressure(state, s, time, defense)
  local h = state.pressure
  if not h then h = {}; state.pressure = h end
  if h.lastAt and time - h.lastAt > CONFIG.ACTIVATION.PRESSURE_MAX_AGE then h = {}; state.pressure = h end
  h.lastAt = time
  if h.cycleAt and time - h.cycleAt > CONFIG.ACTIVATION.PRESSURE_MAX_AGE then h.cycle, h.previousCycle, h.cycleAt = nil, nil, nil end
  local me = localPlayer.UserId
  if h.target ~= s.targetId then
    if h.targetAt and time > h.targetAt then h.lastLeg = time - h.targetAt end
    h.targetAt = time
    if h.target and (h.target == me or s.targetId == me) then h.exchangeAt = time end
    if s.targetId == me then
      if h.inboundAt and h.departedAt then
        local interval = time - h.inboundAt
        if interval > 0 and interval <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE then h.previousCycle, h.cycle, h.cycleAt = h.cycle, interval, time; h.returnLeg = time - h.departedAt end
      end
      h.inboundAt, h.departedAt = time, nil
    elseif h.target == me then
      h.departedAt = time
    end
    h.target = s.targetId
  end
  if h.sampleAt and time - h.sampleAt > CONFIG.ACTIVATION.PRESSURE_MAX_AGE then h.sampleAt, h.headroom, h.previousHeadroom, h.parryDistance, h.idealDistance = nil, nil, nil, nil, nil end
  local sample = defense and defense.lastAcceptedSample
  if sample and finite(sample.distance) and finite(sample.speed) then
    local physics = gameInfo.getDefensePhysics(); local kill = physics and finite(physics.killRadius) and physics.killRadius or 4
    local grace = physics and finite(physics.grace) and physics.grace or 0.02; sample = table.clone(sample)
    sample.headroom = math.max(0, sample.distance - kill) / math.max(1, sample.speed, sample.closingSpeed or 0)
      + grace
      - (defense and finite(defense.ping) and math.max(0, defense.ping) or 0)
  end
  if
    sample
    and sample.ball == s.ball
    and finite(sample.at)
    and finite(sample.headroom)
    and time >= sample.at
    and time - sample.at <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE
    and sample.at >= (state.pressureEpoch or 0)
    and sample.at ~= h.sampleAt
  then
    if h.sampleAt and sample.at - h.sampleAt <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE then h.previousHeadroom = h.headroom else h.previousHeadroom = nil end
    h.sampleAt, h.headroom = sample.at, sample.headroom; h.parryDistance, h.idealDistance = sample.distance, sample.idealDistance
  end
  return h
end
local function deathRisk(state, s, time, cd)
  local physics = gameInfo.getDefensePhysics(); local kill = physics and finite(physics.killRadius) and physics.killRadius or 4
  local grace = physics and finite(physics.grace) and physics.grace or 0.02; local defense = autoParry and autoParry.getPressureDetector()
  local ping = defense and finite(defense.ping) and math.max(0, defense.ping) or 0; local frame = defense and finite(defense.frameTime) and math.max(0, defense.frameTime) or 1 / 60
  local sync = defense and finite(defense.syncInterval) and math.max(0, defense.syncInterval) or 0.05; local runtimeBudget = math.max(1 / 25, frame + sync + ping + 1 / 60)
  local response = math.max(1 / CONFIG.ACTIVATION.PRESSURE_REFERENCE_CPS, runtimeBudget)
  if cd and cd.blocking and finite(cd.remaining) then response += math.max(0, cd.remaining) end
  if defense and finite(defense.retryAt) then response = math.max(response, defense.retryAt - time + ping) end
  local own, ownVelocity = state.root.Position, state.root.AssemblyLinearVelocity
  if not vector(ownVelocity) then ownVelocity = Vector3.zero end
  local speed = snapshotSpeed(s); local me = localPlayer.UserId
  local partner = s.targetId ~= me and s.targetId or state.previousOpponent
  if not partner or not playerIsAlive(partner) then partner = nearestPartner(state, math.huge) end
  local deadline, source = math.huge, "no_intercept"
  if state.riskTarget ~= s.targetId then state.killEntryAt = nil; state.riskTarget = s.targetId end
  if s.targetId == me then
    local entry = sphereEntry(s.position - own, s.velocity - ownVelocity, kill); local earliest = math.max(0, (s.position - own).Magnitude - kill) / math.max(1, speed + ownVelocity.Magnitude)
    entry = math.min(entry, earliest)
    if entry == 0 or s.grace == true then local age = finite(s.syncAt) and math.max(0, time - s.syncAt) or 0; state.killEntryAt = state.killEntryAt or (time - age - networkLatency()) end
    local remainingGrace = math.max(0, grace - (state.killEntryAt and time - state.killEntryAt or 0)); deadline, source = state.killEntryAt and remainingGrace or entry + remainingGrace, "incoming"
  else
    state.killEntryAt = nil; local other, otherVelocity = gameInfo.getPlayerMotion(s.targetId)
    if vector(other) then
      if not vector(otherVelocity) then otherVelocity = Vector3.zero end
      local radius = gameInfo.getPlayerRawRadius(s.targetId, speed, false); local g = geometry(s, 1)
      local reach = (radius or 8.5) + speed * (g and g.effectiveWindow or 0); local intercept = sphereEntry(s.position - other, s.velocity - otherVelocity, reach)
      local earliest = math.max(0, (s.position - other).Magnitude - reach) / math.max(1, speed + otherVelocity.Magnitude); intercept = math.min(intercept, earliest)
      if intercept < math.huge then
        local separation = ((other + otherVelocity * intercept) - (own + ownVelocity * intercept)).Magnitude; local relative = otherVelocity - ownVelocity
        local toward = separation > 0 and -relative:Dot(other - own) / math.max((other - own).Magnitude, 0.001) or 0; local returnSpeed = math.min(600, speed + 12)
        deadline = intercept + math.max(0, separation - kill) / math.max(1, returnSpeed + toward) + grace; source, partner = "possible_return", s.targetId
      end
    end
  end
  local h = observePressure(state, s, time, defense)
  local predictedCycle, nextCycle, nextHeadroom
  local other, otherVelocity = gameInfo.getPlayerMotion(partner)
  if vector(other) then
    if not vector(otherVelocity) then otherVelocity = Vector3.zero end
    local delta = other - own; local separation = delta.Magnitude
    local closing = separation > 0 and -(otherVelocity - ownVelocity):Dot(delta) / separation or 0; local nextSeparation = math.max(0, separation - math.max(0, closing) * response)
    predictedCycle = math.max(1 / 25, 2 * math.max(0, nextSeparation - kill) / math.max(1, math.min(600, speed + 24) + math.max(0, closing)))
  end
  if h.cycleAt and time - h.cycleAt <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE then
    nextCycle = h.cycle
    if h.previousCycle then nextCycle = math.max(1 / 25, h.cycle + math.min(0, h.cycle - h.previousCycle)) end
  end
  if h.sampleAt and time - h.sampleAt <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE then
    nextHeadroom = h.headroom
    if h.previousHeadroom then nextHeadroom = h.headroom + math.min(0, h.headroom - h.previousHeadroom) end
  end
  local soon = deadline <= 2 * response + 1 / 25; local requiredInterval = predictedCycle
  if nextCycle then requiredInterval = math.min(requiredInterval or math.huge, nextCycle) end
  local exchangeEvidence = h.exchangeAt ~= nil and time >= h.exchangeAt and time - h.exchangeAt <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE
  local lateParry = nextHeadroom ~= nil and nextHeadroom <= runtimeBudget + 1 / 25; local fastReturn = nextCycle ~= nil and nextCycle <= response + 1 / 25
  local fastLeg = h.cycleAt ~= nil and time - h.cycleAt <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE and h.returnLeg ~= nil and h.returnLeg <= response
  local recentLeg = h.targetAt ~= nil and time - h.targetAt <= CONFIG.ACTIVATION.PRESSURE_MAX_AGE and h.lastLeg ~= nil and h.lastLeg <= response
  local reason
  if exchangeEvidence and soon then
    if fastReturn then reason = "return_demand_exceeds_ap"
    elseif predictedCycle and predictedCycle <= response and (fastLeg or recentLeg) then reason = "return_demand_exceeds_ap"
    elseif lateParry and predictedCycle and predictedCycle <= response + runtimeBudget then reason = "parry_margin_shrinking" end
  end
  return {
    exchangeEvidence = exchangeEvidence,
    returnLeg = h.returnLeg,
    risky = reason ~= nil,
    reason = reason,
    deadline = deadline,
    response = response,
    margin = deadline - response,
    grace = grace,
    killRadius = kill,
    source = source,
    partner = partner,
    gameMaxCps = 25,
    observedCycle = h.cycle,
    predictedCycle = predictedCycle,
    nextCycle = nextCycle,
    requiredCps = requiredInterval and 1 / math.max(1 / 25, requiredInterval) or nil,
    headroom = h.headroom,
    nextHeadroom = nextHeadroom,
    parryDistance = h.parryDistance,
    idealDistance = h.idealDistance,
  }
end
-- An explicit fresh redirect ends local spam immediately, even while the old
-- opponent remains inside the proximity protection radius.
local function redirectedFar(state, s, time)
  if not freshSnapshot(s, time) or s.ball ~= state.ball or s.teleported or s.resetting or s.locked then return false end
  local target = userId(s.targetId)
  if not target or target == localPlayer.UserId or target == state.partner then return false end
  if finite(s.syncSequence) and finite(state.sequence) then
    local delta = (s.syncSequence - state.sequence) % 65536
    if delta >= 32768 then return false end
  end
  local position = playerPosition(target)
  return position ~= nil and (position - state.root.Position).Magnitude > CONFIG.DEACTIVATION.MAX_CLASH_DISTANCE
end
-- Retain evidence of actual rapid local exchanges independently of soft target
-- uncertainty, which may clear the activation detector's history.
local function rememberSendContinuity(state, s, time)
  local h = state.pressure
  if not state.active or not h or not finite(h.cycle) or h.cycle <= 0 or h.cycle > CONFIG.ACTIVATION.RETURN then return end
  if not finite(h.exchangeAt) or time < h.exchangeAt or time - h.exchangeAt > CONFIG.ACTIVATION.RETURN then return end
  local horizon = math.clamp(h.cycle + networkLatency() + 2 / 60, 0.08, 0.2)
  state.sendContinuity = { ball = s.ball, exchangeAt = h.exchangeAt, expiresAt = h.exchangeAt + horizon }
end
local function canBridgeSend(state, s, time)
  local evidence = state.sendContinuity
  if not evidence or evidence.ball ~= state.ball or not evidence.ball.Parent then return false end
  if time < evidence.exchangeAt or time > evidence.expiresAt then return false end
  if not utils.isActive() or utils.getConfigValue("AutoSpam") ~= true or not playerIsAlive(localPlayer.UserId) then return false end
  if not state.root.Parent or not state.character.Parent or not playerIsAlive(state.partner) then return false end
  local opponent = playerPosition(state.partner)
  if not opponent or (opponent - state.root.Position).Magnitude > CONFIG.DEACTIVATION.PROTECTION_RADIUS then return false end
  if gameInfo.getBallFrozen() == true then return false end
  if s and (s.ball ~= state.ball or s.teleported or s.resetting or s.locked or s.mode == "training"
    or s.ballCanMove == false or s.ballValid == false or s.valid == false) then return false end
  return true
end
local function sendBlocked(state, reason, time)
  if state.lastSendBlockReason ~= reason then state.lastSendBlockReason, state.lastSendBlockAt = reason, time end
  return false
end
local function deactivationReason(state, s, time, cd)
  if not utils.isActive() then return "hub_inactive" end
  if utils.getConfigValue("AutoSpam") ~= true then return "disabled" end
  if not state.character.Parent or not state.root.Parent or not playerIsAlive(localPlayer.UserId) then return "player_died" end
  if redirectedFar(state, s, time) then return "target_redirected_far" end
  if not playerIsAlive(state.partner) then return "opponent_left_or_died" end
  local opponent = playerPosition(state.partner)
  if not opponent then state.distanceSince = nil; return nil end
  local distance = (opponent - state.root.Position).Magnitude
  if distance <= CONFIG.DEACTIVATION.PROTECTION_RADIUS then state.distanceSince = nil; return nil end
  if distance > CONFIG.DEACTIVATION.MAX_CLASH_DISTANCE then
    state.distanceSince = state.distanceSince or time
    if time - state.distanceSince >= CONFIG.DEACTIVATION.CLASH_DISTANCE_TIMEOUT then return "clash_distance" end
  else
    state.distanceSince = nil
  end
end
local function dashPrediction(state, s, time)
  if s.syncAt == nil or time - s.syncAt > CONFIG.ACTIVATION.DASH_MAX_SNAPSHOT_AGE then return nil, "dash_snapshot_stale" end
  local function forPartner(partner)
    if not nearPartner(state, partner, CONFIG.ACTIVATION.DASH_DETECTION_RANGE) then return nil, "dash_no_partner" end
    if s.targetId ~= localPlayer.UserId and s.targetId ~= partner then return nil, "dash_target" end
    if not ballWindow(state, s, s.targetId) then return nil, "dash_ball_outside_window" end
    local own, other = state.root.Position, playerPosition(partner); local g, speed = geometry(s, 1)
    if not g then return nil, "dash_geometry" end
    local ownRadius, otherRadius = compensatedRadius(localPlayer.UserId, speed), gameInfo.getPlayerRawRadius(partner, speed, false)
    if not finite(ownRadius) or not finite(otherRadius) then return nil, "dash_geometry" end
    local function model(sample, relative, reason)
      if
        not sample
        or not sample.signalActive
        or not sample.normalModel
        or not vector(sample.velocity)
        or not finite(sample.observedAt)
        or not vector(sample.position)
      then
        return nil
      end
      local age, magnitude, remaining = time - sample.observedAt, sample.velocity.Magnitude, sample.normalModel.estimatedRemaining; local distance = relative.Magnitude
      if age < 0 or age > 0.2 or magnitude < 70 or magnitude > 140 or not finite(remaining) or remaining <= 0 or distance <= 0.05 then return nil end
      local closing = sample.velocity:Dot(relative) / distance
      if closing / magnitude < CONFIG.ACTIVATION.DASH_MIN_ALIGNMENT then return nil end
      local closestAt = math.clamp(relative:Dot(sample.velocity) / sample.velocity:Dot(sample.velocity), 0, remaining); local predicted = (relative - sample.velocity * closestAt).Magnitude
      local limit = math.min(CONFIG.ACTIVATION.MAX_CLASH_DISTANCE, ownRadius + otherRadius + speed * g.effectiveWindow)
      if predicted > limit then return nil end
      local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
      params.FilterDescendantsInstances = { state.character, players:GetPlayerByUserId(partner).Character, s.ball }; params.RespectCanCollide = true
      local ok, obstacle = pcall(function() return utils.getWorkspace():Raycast(sample.position, sample.velocity * closestAt, params) end)
      if not ok or obstacle then return nil end
      return { reason = reason, partner = partner, at = sample.observedAt, projectedDistance = predicted, windowFactor = 1 }
    end
    local candidate = model(dashInfo.getEstimate(partner), own - other, "dash_incoming")
      or model(dashInfo.getEstimate(localPlayer.UserId), other - own, "dash_self")
    return candidate, candidate and "ready" or "dash_no_intercept"
  end
  if s.targetId ~= localPlayer.UserId then return forPartner(s.targetId) end
  local seen = {}; local lastGate = "dash_no_partner"
  local function tryPartner(id)
    if not id or seen[id] then return nil end
    seen[id] = true; local candidate, gate = forPartner(id)
    if gate ~= "dash_no_partner" or lastGate == "dash_no_partner" then lastGate = gate end
    return candidate
  end
  local candidate = tryPartner(state.previousOpponent)
  if candidate then return candidate, "ready" end
  for _, player in ipairs(players:GetPlayers()) do
    if player ~= localPlayer then
      candidate = tryPartner(player.UserId)
      if candidate then return candidate, "ready" end
    end
  end
  return nil, lastGate
end
local function consistentSelfReturn(state, s, time)
  local me = localPlayer.UserId; local tracker = state.selfReturn
  if s.targetId ~= me or not vector(s.position) or not vector(s.velocity) then state.selfReturn = nil; return nil end
  local speed = snapshotSpeed(s); local low, high = gameInfo.getBallSpeedLimits()
  if not speed or not finite(low) or not finite(high) or high <= low then return nil end
  local delta = state.root.Position - s.position; local distance = delta.Magnitude
  if distance < 0.1 then return nil end
  local radial = s.velocity:Dot(delta) / distance; local direction = radial > speed * CONFIG.ACTIVATION.SELF_RETURN_DIRECTION_RATIO and "incoming"
    or radial < -speed * CONFIG.ACTIVATION.SELF_RETURN_DIRECTION_RATIO and "outgoing"
    or nil
  if not direction then return nil end
  if not tracker or tracker.ball ~= s.ball or time - tracker.lastAt > 0.15 then
    tracker = { ball = s.ball, direction = direction, lastAt = time, switches = 0 }; state.selfReturn = tracker
    return nil
  end
  tracker.lastAt = time
  if direction ~= tracker.direction then
    if tracker.direction == "outgoing" and direction == "incoming" then tracker.returnAt = time; tracker.switches += 1 end
    tracker.direction = direction
  end
  local fraction = math.clamp((speed - low) / (high - low), 0, 1)
  local duration = CONFIG.ACTIVATION.SELF_RETURN_MIN_TIME + (CONFIG.ACTIVATION.SELF_RETURN_MAX_TIME - CONFIG.ACTIVATION.SELF_RETURN_MIN_TIME) * fraction
  if direction ~= "incoming" or tracker.switches < 1 or not tracker.returnAt or time - tracker.returnAt < duration then return nil end
  if not ballWindow(state, s, me) then return nil end
  local partner = nearPartner(state, state.previousOpponent, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE)
    or nearestPartner(state, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE)
  return partner
end
local function chooseActivation(state, s, time)
  local selfReturnPartner = consistentSelfReturn(state, s, time); state.gates.selfReturn = selfReturnPartner and "ready" or "self_return_waiting"
  if selfReturnPartner then return "consistent_self_return", selfReturnPartner end
  local prediction, dashGate = dashPrediction(state, s, time); state.dashPrediction, state.gates.dash = prediction, dashGate
  if prediction then return prediction.reason, prediction.partner, prediction.at end
  local pending = state.pending; state.gates.returnTarget = not pending and "return_no_round_trip" or "return_expired"
  if pending and time - pending.at <= CONFIG.ACTIVATION.RETURN + networkLatency() then
    if not nearPartner(state, pending.partner, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE) then state.gates.returnTarget = "return_opponent_distance"
    elseif s.targetId ~= localPlayer.UserId then state.gates.returnTarget = "return_not_target"
    elseif not ballWindow(state, s, localPlayer.UserId) then state.gates.returnTarget = "return_ball_outside_window"
    else state.gates.returnTarget = "ready"; return "return_target", pending.partner end
  end
  local distance = (s.position - state.root.Position).Magnitude; local closePartner = nearPartner(state, state.previousOpponent, CONFIG.ACTIVATION.CLOSE_OPPONENT_DISTANCE)
    or nearestPartner(state, CONFIG.ACTIVATION.CLOSE_OPPONENT_DISTANCE)
  state.gates.close = "close_not_target"
  if s.targetId == localPlayer.UserId then
    if distance <= CONFIG.ACTIVATION.CLOSE_INSTANT_DISTANCE and closePartner then state.gates.close = "ready"; return "close_target", closePartner end
    local arm = state.closeArm
    if arm and not nearPartner(state, arm.partner, CONFIG.ACTIVATION.CLOSE_OPPONENT_DISTANCE) then state.closeArm = nil; arm = nil end
    if not arm and distance <= CONFIG.ACTIVATION.CLOSE_TARGET_DISTANCE then
      local sender = nearPartner(state, state.previousOpponent, CONFIG.ACTIVATION.CLOSE_OPPONENT_DISTANCE)
      if sender then arm = { partner = sender, stage = "incoming" }; state.closeArm = arm end
    end
    state.gates.close = not arm and "close_no_sender_or_distance" or "close_wait_exchange"
    if arm and arm.stage == "confirmed" then
      if ballWindow(state, s, localPlayer.UserId) then state.gates.close = "ready"; return "close_target", arm.partner end
      state.gates.close = "close_return_outside_window"
    end
  end
  local haunter = state.haunter; state.gates.haunter = not haunter and "haunter_no_event" or "haunter_expired"
  if haunter and time - haunter.at <= CONFIG.ACTIVATION.HAUNTER_LIFETIME then
    if not nearPartner(state, haunter.partner, CONFIG.ACTIVATION.HAUNTER_RANGE) then state.gates.haunter = "haunter_opponent_distance"
    elseif s.targetId ~= localPlayer.UserId and s.targetId ~= haunter.partner then state.gates.haunter = "haunter_target"
    elseif not ballWindow(state, s, s.targetId) then state.gates.haunter = "haunter_ball_outside_window"
    else state.gates.haunter = "ready"; return haunter.reason, haunter.partner end
  end
  local risk = state.risk
  if risk and risk.risky and risk.partner then return risk.reason, risk.partner end
end
local function sequenceOrder(state, incoming)
  if incoming == nil then return "none" end
  if not finite(incoming) or incoming < 0 or incoming >= 65536 or incoming % 1 ~= 0 then return "invalid" end
  if state.sequence == nil then return "new" end
  local delta = (incoming - state.sequence) % 65536; return delta == 0 and "same" or (delta < 32768 and "new" or "old")
end
local function observeStats(state, s, time, packet)
  if not s or not gameInfo.isSnapshotValid(s) then return end
  if clashStats and clashStats.frozen and not state.active then clashStatsModule.waitForNextClash() end
  clashStatsModule.observe(state, s, time, packet == true); clashStats = clashStatsModule.get()
end
local function evaluate(state, s, time, packet)
  if current ~= state then return end
  state.gates = {}; local cd = monitorCooldown(state)
  -- Ability cooldown is not evidence that a clash ended; the client queues presses.
  -- Keep automatic requests subject to the same ability/remote handling as manual spam.
  if not utils.isActive() or utils.getConfigValue("AutoSpam") ~= true then
    local reason = utils.isActive() and "disabled" or "hub_inactive"; deactivate(state, reason, time)
    state.lastGate = reason; resetTargets(state)
    if utils.isActive() and utils.isManualSpamActive() then observeStats(state, s, time, packet) end
    return
  end
  if s and s.ball and s.ball ~= state.ball then
    if state.ball then deactivate(state, "ball_replaced", time) end
    state.sendContinuity = nil
    state.ball, state.sequence = s.ball, nil; resetTargets(state)
  end
  local order = sequenceOrder(state, s and s.syncSequence)
  if order == "old" or order == "invalid" then state.lastGate = "packet_" .. order; return end
  if order == "new" then state.sequence = s.syncSequence end
  local gate = sampleGate(state, s, time)
  if gate then
    state.gates.common, state.lastGate = gate, gate; state.deflectCooldownSince, state.departedAt, state.distanceSince = nil, nil, nil
    state.cooldownResumeAt = time
    if gate == "player_died" or gate == "hub_inactive" then deactivate(state, gate, time) end
    if gate == "ball_reset" or gate == "target_unknown" then resetTargets(state) end
    if gate == "ball_reset" or gate == "ball_paused" or gate == "ball_not_moving" or gate == "training" then
      state.pressure, state.risk, state.pressureEpoch, state.sendContinuity = nil, nil, time, nil
    end
    return
  end
  observeTarget(state, s, time); state.risk = deathRisk(state, s, time, cd)
  rememberSendContinuity(state, s, time)
  state.gates.risk = state.risk.reason or "ap_has_time"; dashInfo.tick(time, false, state.root.Position, CONFIG.ACTIVATION.DASH_DETECTION_RANGE)
  if state.active then
    local stop = deactivationReason(state, s, time, cd)
    if stop then deactivate(state, stop, time); return end
    state.lastGate = "active"; observeStats(state, s, time, packet)
    return
  end
  if state.reactivateAt and time < state.reactivateAt then state.lastGate, state.gates.common = "reactivation_delay", "reactivation_delay"; return end
  state.reactivateAt = nil; local reason, partner = chooseActivation(state, s, time)
  if reason then activate(state, reason, partner, time, s) else state.lastGate = "no_activation_evidence" end
  observeStats(state, s, time, packet)
end
local function nearestPlayer(position, limit, excluded)
  local best, bestDistance
  for _, player in ipairs(players:GetPlayers()) do
    if player ~= excluded and playerIsAlive(player.UserId) then
      local value = gameInfo.getPlayerMotion(player.UserId)
      if typeof(value) == "Vector3" then
        local distance = (value - position).Magnitude
        if distance <= limit and (not bestDistance or distance < bestDistance) then best, bestDistance = player, distance end
      end
    end
  end
  return best
end
local function connectHaunter(state)
  local event = gameInfo.getHaunterEvent()
  if event == state.haunterRemote and state.haunterConnection and state.haunterConnection.Connected ~= false then return end
  if state.haunterConnection then
    utils.untrackCharacter(state.haunterConnection); state.haunterConnection:Disconnect()
    state.haunterConnection, state.haunterRemote = nil, nil
  end
  if not event then return end
  state.haunterRemote = event
  state.haunterConnection = listen(state, event.OnClientEvent, function(from, destination)
    if
      current ~= state
      or state.active
      or not state.root.Parent
      or not utils.isActive()
      or utils.getConfigValue("AutoSpam") ~= true
      or not gameInfo.areAbilitiesEnabled()
      or gameInfo.getBallFrozen() == true
      or typeof(from) ~= "CFrame"
      or typeof(destination) ~= "CFrame"
    then
      return
    end
    local time, ownId = now(), localPlayer.UserId; local target = userId(gameInfo.getTargetId())
    local ownWasAtSource = typeof(state.lastRootPosition) == "Vector3"
      and (state.lastRootPosition - from.Position).Magnitude <= CONFIG.ACTIVATION.HAUNTER_MATCH_RADIUS
    if not ownWasAtSource and state.recentRootPosition and time - state.recentRootAt <= 0.75 then
      ownWasAtSource = (state.recentRootPosition - from.Position).Magnitude <= CONFIG.ACTIVATION.HAUNTER_MATCH_RADIUS
    end
    local other = target ~= ownId and target or (state.target ~= ownId and state.target or nil)
    if ownWasAtSource and target == ownId and not other then local player = nearestPlayer(destination.Position, CONFIG.ACTIVATION.HAUNTER_RANGE, localPlayer); other = player and player.UserId end
    if other and ownWasAtSource and (target == ownId or target == other) then
      local position = gameInfo.getPlayerMotion(other)
      if typeof(position) == "Vector3" and playerIsAlive(other) and (position - destination.Position).Magnitude <= CONFIG.ACTIVATION.HAUNTER_RANGE then
        state.haunter = { partner = other, at = time, reason = "haunter_self" }; evaluate(state, gameInfo.getSnapshotAt(time), time, false)
        return
      end
    end
    if (destination.Position - state.root.Position).Magnitude > CONFIG.ACTIVATION.HAUNTER_RANGE then return end
    local caster, bestDistance
    for _, player in ipairs(players:GetPlayers()) do
      local position = gameInfo.getPlayerMotion(player.UserId)
      if typeof(position) == "Vector3" and playerIsAlive(player.UserId) then
        local distance = math.min((position - from.Position).Magnitude, (position - destination.Position).Magnitude)
        if distance <= CONFIG.ACTIVATION.HAUNTER_MATCH_RADIUS and (not bestDistance or distance < bestDistance) then caster, bestDistance = player, distance end
      end
    end
    if caster and caster ~= localPlayer then state.haunter = { partner = caster.UserId, at = time, reason = "haunter" }; evaluate(state, gameInfo.getSnapshotAt(time), time, false) end
  end)
end
local function detach(reason)
  local state = current
  if not state then return end
  if clashStats and not clashStats.frozen then clashStatsModule.finish(reason, now()) end
  deactivate(state, reason, now()); current = nil
  generation += 1
  for _, connection in ipairs(state.connections) do
    utils.untrackCharacter(connection); connection:Disconnect()
  end
end
function AutoSpam.setup(deps)
  if type(deps) ~= "table" or not deps.Utils or not deps.GameInfo or not deps.ClashStats or not deps.Cooldown or not deps.Dash then return false, "dependências ausentes" end
  if current then detach("setup") end
  utils, gameInfo, clashStatsModule, cooldownInfo, dashInfo = deps.Utils, deps.GameInfo, deps.ClashStats, deps.Cooldown, deps.Dash; autoParry = deps.AutoParry
  players, runService, localPlayer = utils.getPlayers(), utils.getRunService(), utils.getLocalPlayer()
  if not players or not runService or not localPlayer then return false, "serviços indisponíveis" end
  clashStats = clashStatsModule.get(); return true
end
function AutoSpam.bindCharacter(character)
  detach("rebind"); local root = character and character:FindFirstChild("HumanoidRootPart")
  if not root or not root:IsA("BasePart") then return false, "HumanoidRootPart indisponível" end
  local state = {
    character = character,
    root = root,
    connections = {},
    active = false,
    reason = "waiting",
    lastGate = "waiting",
    gates = {},
    stopEvents = {},
    selfReturn = nil,
    lastRootPosition = root.Position,
    lastTickAt = -math.huge,
  }

  current = state; connectHaunter(state)
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if humanoid then
    listen(state, humanoid.Died, function()
      if current == state then clashStatsModule.freeze(localPlayer.UserId, state); deactivate(state, "player_died", now()) end
    end)
  end
  listen(state, players.PlayerRemoving, function(player)
    if current ~= state then return end
    if player.UserId == state.partner then deactivate(state, "opponent_left", now()) end
    if player.UserId == state.previousOpponent then resetTargets(state) end
  end)
  listen(state, runService.Heartbeat, function()
    if current ~= state then return end
    local time = now(); local readyToRearm = not state.active and state.reactivateAt and time >= state.reactivateAt
    if time - state.lastTickAt < CONFIG.SHARED.RUNTIME_TICK_INTERVAL and not readyToRearm then return end
    state.lastTickAt = time
    if time >= (state.nextHaunterCheck or 0) then state.nextHaunterCheck = time + 0.5; connectHaunter(state) end
    if vector(state.lastRootPosition) and (root.Position - state.lastRootPosition).Magnitude > CONFIG.ACTIVATION.HAUNTER_RANGE then
      state.recentRootPosition, state.recentRootAt = state.lastRootPosition, time
    end
    evaluate(state, gameInfo.getSnapshotAt(time), time, false); state.lastRootPosition = root.Position
  end)
  listen(state, character.AncestryChanged, function(_, parent)
    if not parent and current == state then detach("character_removed") end
  end)
  return true
end
function AutoSpam.detachCharacter() detach("detach") end
function AutoSpam.teardown()
  detach("teardown"); clashStats = nil
  autoParry = nil; utils, gameInfo, clashStatsModule, players, runService, localPlayer, cooldownInfo, dashInfo = nil, nil, nil, nil, nil, nil, nil, nil
end
function AutoSpam.onBallSync(data)
  local state = current
  if not state or type(data) ~= "table" then return end
  local time = now(); local s = gameInfo.getSnapshotAt(time)
  if not s then monitorCooldown(state); return end
  if data.Source == "packet" then
    local order = sequenceOrder(state.ball == s.ball and state or {}, data.Sequence or data.TeleportSequence)
    if order == "old" or order == "invalid" or (order == "same" and data.Teleported ~= true) then return end
    s = table.clone(s); s.syncSequence, s.syncAt = data.Sequence or data.TeleportSequence, time
    if data.TargetPlayerID ~= nil then s.targetId, s.targetUncertain = data.TargetPlayerID, false end
    if data.Speed ~= nil then s.syncSpeed = data.Speed end
    if data.RealPosition ~= nil then s.realPosition = data.RealPosition end
    if vector(data.ForcedDirection) and snapshotSpeed(s) then s.velocity = data.ForcedDirection * snapshotSpeed(s) end
    s.teleported = data.Teleported == true
    if type(data.Locked) == "boolean" then s.locked = data.Locked end
    if data.ServerTime ~= nil then s.serverTime = data.ServerTime end
  end
  evaluate(state, s, time, data.Source == "packet")
end
function AutoSpam.isActive() return current ~= nil and current.active end
function AutoSpam.canSendManual()
  local state = current
  if not state or not utils or not utils.isActive() or not utils.isManualSpamActive() then return false end
  return state.root ~= nil and state.root.Parent ~= nil and state.character ~= nil and state.character.Parent ~= nil and playerIsAlive(localPlayer.UserId)
end
function AutoSpam.canSend()
  local state = current
  if not state or not state.active then return false end
  local time = now(); local cd = monitorCooldown(state)
  local s = gameInfo.getSnapshotAt(time); local stop = deactivationReason(state, s, time, cd)
  if stop then deactivate(state, stop, time); return sendBlocked(state, stop, time) end
  local order = sequenceOrder(state, s and s.syncSequence)
  local gate = (order == "old" or order == "invalid") and ("packet_" .. order) or sampleGate(state, s, time)
  if gate == nil then return true end
  local transient = gate == "target_unknown" or gate == "snapshot_invalid" or gate == "snapshot_stale"
    or gate == "position_disagreement" or gate == "position_invalid" or gate == "ball_data_invalid" or gate == "packet_old"
  if transient and canBridgeSend(state, s, time) then state.lastBridgedSendAt = time; return true end
  return sendBlocked(state, gate, time)
end
function AutoSpam.stopSpam(reason)
  if current then deactivate(current, reason or "stop_spam", now()) end
end
function AutoSpam.getActivationContext()
  return { active = current ~= nil and current.active, reason = current and current.reason or "detached", partner = current and current.partner or -1 }
end
function AutoSpam.getTargetSwitch()
  return {
    timestampMs = current and (current.lastSwitchAt or 0) * 1000 or 0,
    partnerId = current and current.partner or -1,
    intervalMs = current and current.intervalMs or 0,
    resetToken = generation,
  }
end
function AutoSpam.getDashData()
  local dashing, speed, duration = gameInfo.getLocalDashState(); return { dashing = dashing == true, speed = speed or 120, duration = duration or 0.2, windowFactor = 1 }
end
local function clashStatus()
  if not clashStats then return nil end
  local currentCps = clashStats.currentCps
  if currentCps and not clashStats.frozen then
    currentCps = math.min(currentCps, 1 / math.max(clashStats.cycleInterval or 0, clashStats.lastCycleAt and now() - clashStats.lastCycleAt or math.huge))
  end
  local duration = clashStats.duration or (clashStats.startedAt and math.max(0, now() - clashStats.startedAt))
  return {
    partnerId = clashStats.partnerId,
    distance = clashStats.distance,
    cps = clashStats.cps,
    currentCps = currentCps,
    startSample = clashStats.startSample and table.clone(clashStats.startSample) or nil,
    endSample = clashStats.endSample and table.clone(clashStats.endSample) or nil,
    endReason = clashStats.endReason,
    speed = clashStats.speed,
    frozen = clashStats.frozen,
    duration = duration,
    travelTarget = clashStats.travelTarget,
    travelStartedAt = not clashStats.frozen and clashStats.travelStartedAt or nil,
    lastTravelTime = clashStats.lastTravelTime,
    lastTravelTarget = clashStats.lastTravelTarget,
    fatalTravelTime = clashStats.fatalTravelTime,
    penultimateTravelTime = clashStats.penultimateTravelTime,
    penultimateTarget = clashStats.penultimateTarget,
    deceasedId = clashStats.deceasedId,
  }
end
function AutoSpam.getStatus()
  local state = current; local time = utils and now() or 0
  local sample = gameInfo and gameInfo.getSnapshotAt(time); local distance = state and sample and vector(sample.position) and (sample.position - state.root.Position).Magnitude or nil
  return {
    schema = utils and utils.apiVersion() or 1,
    phase = state and (state.active and "active" or "idle") or "detached",
    active = state ~= nil and state.active,
    lastGate = state and state.lastGate or "detached",
    reactivationRemaining = state and math.max(0, (state.reactivateAt or 0) - time) or 0,
    ballDistance = distance,
    targetUncertain = sample and sample.targetUncertain == true or false,
    snapshotAge = sample and finite(sample.syncAt) and time - sample.syncAt or nil,
    windowFactor = 1,
    gates = state and table.clone(state.gates) or {},
    risk = state and state.risk or nil,
    dashPrediction = state and state.dashPrediction or nil,
    dashEscape = state and state.dashEscape or nil,
    activationReason = state and state.active and state.reason or nil,
    lastActivationReason = lastActivationReason,
    lastActivationAt = lastActivationAt,
    lastSendBlockReason = state and state.lastSendBlockReason or nil,
    lastSendBlockAt = state and state.lastSendBlockAt or nil,
    lastBridgedSendAt = state and state.lastBridgedSendAt or nil,
    lastStopReason = lastStopReason,
    lastStopAt = lastStopAt,
    targetId = state and state.target or -1,
    clashPartnerId = state and state.partner or -1,
    clashStats = clashStatus(),
  }
end

-- contract
AutoSpam.__contract = {
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    ClashStats = "clashstats",
    Cooldown = "cooldown",
    Dash = "dash",
    AutoParry = "autoparry",
  },
  requiresMethods = {
    Utils = {
      "now",
      "getLocalPlayer",
      "getPlayers",
      "getWorkspace",
      "getRunService",
      "isActive",
      "getConfigValue",
      "isManualSpamActive",
      "setAutoSpamActive",
      "setManualSpamActive",
      "trackCharacter",
      "untrackCharacter",
      "recordTransition",
      "apiVersion",
    },
    GameInfo = {
      "areAbilitiesEnabled",
      "getSnapshotAt",
      "isSnapshotValid",
      "getPlayerMotion",
      "getHaunterEvent",
      "getDeflectGeometry",
      "getLocalDashState",
      "getPlayerRawRadius",
      "getBallFrozen",
      "getAveragePing",
      "getTargetId",
      "getBallSpeedLimits",
      "getDefensePhysics",
    },
    AutoParry = { "getPressureDetector" },
    Cooldown = { "getDeflectCooldownState" },
    Dash = { "tick", "getEstimate" },
    ClashStats = { "begin", "finish", "observe", "freeze", "get", "waitForNextClash" },
  },
  provides = {
    "setup",
    "bindCharacter",
    "detachCharacter",
    "teardown",
    "onBallSync",
    "isActive",
    "canSend",
    "canSendManual",
    "getActivationContext",
    "getStatus",
    "getTargetSwitch",
    "getDashData",
    "stopSpam",
  },
  onBallSync = true,
  bindCharacter = true,
}

return AutoSpam
