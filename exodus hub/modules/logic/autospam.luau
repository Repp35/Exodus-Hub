-- [[ auto spam ]]

local AutoSpam = {}

local utils, gameInfo, clashStatsModule, cooldownInfo, dashInfo, deflectGeometry
local players, runService, localPlayer, current
local generation, matchDeathSerial = 0, 0
local lastActivationReason, lastActivationAt, lastStopReason, lastStopAt
local evaluate
local CONFIG = {
  ACTIVATION = {
    RETURN = 0.36,
    MAX_CLASH_DISTANCE = 35,
    CLOSE_TARGET_DISTANCE = 5,
    CLOSE_OPPONENT_DISTANCE = 16,
    HAUNTER_RANGE = 11,
    HAUNTER_MATCH_RADIUS = 5,
    HAUNTER_LIFETIME = 0.15,
    DASH_MAX_SNAPSHOT_AGE = 0.15,
    DASH_DETECTION_RANGE = 70,
    DASH_MIN_ALIGNMENT = 0.6,
  },
  SIGNAL = {
    BLOCK_LIFETIME = 0.65,
    SUCCESS_LIFETIME = 0.15,
    MERGE_INTERVAL = 0.04,
    SCAN_INTERVAL = 0.05,
    CATALOG_INTERVAL = 0.5,
    STOP_GRACE = 0.05,
  },
  TIMING = {
    SNAPSHOT_MAX_AGE = 0.5,
    PACKET_CACHE_AGE = 0.2,
    HISTORY_MAX_AGE = 0.75,
    REARM_DELAY = 0.02,
    PHYSICAL_EXIT_DELAY = 0.12,
    DISTANCE_EXIT_DELAY = 0.25,
    PREDICTION_MIN_BUDGET = 0.1,
    PREDICTION_MAX_BUDGET = 0.3,
  },
}

local function finite(x) return type(x) == "number" and x == x and x > -math.huge and x < math.huge end
local function vector(x) return typeof(x) == "Vector3" and finite(x.X) and finite(x.Y) and finite(x.Z) end
local function userId(x) return finite(x) and x > 0 and x % 1 == 0 and x or nil end
local function now() return utils.now() end
local function snapshotSpeed(s)
  local speed = s and (s.syncSpeed ~= nil and s.syncSpeed or s.speed); return finite(speed) and speed >= 0 and speed <= 1000 and speed or nil
end
local function networkLatency()
  local ping = gameInfo.getAveragePing(); return finite(ping) and math.clamp(ping * 0.5, 0, 0.25) or 0
end
local function frameLead(state) return math.clamp(state.frameInterval or 1 / 60, 1 / 240, 0.05) end
local function playerIsAlive(id)
  local player = id and players:GetPlayerByUserId(id); local character = player and player.Character
  local humanoid = character and character.Parent and character:FindFirstChildOfClass("Humanoid"); return humanoid ~= nil and finite(humanoid.Health) and humanoid.Health > 0
end
local function playerPosition(id)
  local position = id and gameInfo.getPlayerMotion(id); return vector(position) and position or nil
end
local function nearPartner(state, id, limit)
  if not userId(id) or id == localPlayer.UserId or not playerIsAlive(id) then return nil end
  local player = players:GetPlayerByUserId(id); local lives = player:GetAttribute("Lives")
  if player:GetAttribute("Playing") == false or (finite(lives) and lives <= 0) then return nil end
  local position = playerPosition(id); return position and (position - state.root.Position).Magnitude <= limit and id or nil
end
local function nearestPartner(state, limit)
  local best, distance
  for _, player in ipairs(players:GetPlayers()) do
    local id = nearPartner(state, player.UserId, limit); local position = id and playerPosition(id)
    local gap = position and (position - state.root.Position).Magnitude
    if gap and (not distance or gap < distance) then best, distance = id, gap end
  end
  return best
end
local function listen(state, signal, callback, pool)
  local connection = signal:Connect(callback); state.connections[connection] = true
  if pool then pool[connection] = true end
  utils.trackCharacter(connection); return connection
end
local function disconnectPool(state, pool)
  for connection in pairs(pool) do
    utils.untrackCharacter(connection); connection:Disconnect()
    state.connections[connection] = nil
  end
  table.clear(pool)
end
local function clearEvidence(state)
  state.outbound, state.pending, state.receipt, state.haunter, state.exchange = nil, nil, nil, nil, nil
  state.target, state.previousOpponent, state.confirmedReturns, state.exchangeHistory = nil, nil, nil, nil
  state.lastPairExchangeAt, state.sendContinuity, state.prediction, state.predictionEvidence = nil, nil, nil, nil; state.leg = (state.leg or 0) + 1
  state.activationEvidence, state.wasClose, state.lastCloseLeg, state.lastCloseVisit = nil, nil, nil, nil
  for _, sensor in pairs(state.sensors or {}) do
    sensor.attempt = nil
  end
end
local function deactivate(state, reason, time)
  if not state.active then return false end
  time = time or now(); state.active, state.phase, state.reason, state.lastGate = false, "idle", reason, reason
  state.prediction, state.anticipatingUntil, state.physicalExitSince, state.distanceSince = nil, nil, nil, nil; state.sendContinuity, state.reactivateAt = nil, time + CONFIG.TIMING.REARM_DELAY
  if reason == "opponent_left_or_died" then clashStatsModule.freeze(state.partner, state) end
  state.partner, state.deathSerial = nil, nil; lastStopReason, lastStopAt = reason, time
  if not state.external then utils.setAutoSpamActive(false); utils.recordTransition("AutoSpam", "active", "idle", reason) end
  return true
end
local function sequenceOrder(state, incoming)
  if incoming == nil then return "none" end
  if not finite(incoming) or incoming < 0 or incoming >= 65536 or incoming % 1 ~= 0 then return "invalid" end
  if state.sequence == nil then return "new" end
  local delta = (incoming - state.sequence) % 65536; return delta == 0 and "same" or (delta < 32768 and "new" or "old")
end
local function targetOf(s)
  if not s then return nil end
  if s.exchangeTargetId ~= nil then return userId(s.exchangeTargetId) end
  return userId(s.targetId)
end
local function freshSnapshot(s, time)
  return s
    and gameInfo.isSnapshotValid(s)
    and not s.targetUncertain
    and (s.syncAt == nil or (finite(s.syncAt) and time >= s.syncAt and time - s.syncAt <= CONFIG.TIMING.SNAPSHOT_MAX_AGE))
end
local function lifecycleGate(state, s)
  if not s or not s.ball or not s.ball.Parent then return "snapshot_invalid" end
  if s.ball ~= state.ball or s.teleported or s.resetting or s.ballValid == false or s.valid == false then return "ball_reset" end
  if s.mode == "training" then return "training" end
  if s.locked or s.frozen or s.ballCanMove == false or gameInfo.getBallFrozen() == true then return "ball_paused" end
end
local function sampleGate(state, s, time)
  local gate = lifecycleGate(state, s)
  if gate then return gate end
  local order = sequenceOrder(state, s.syncSequence)
  if order == "old" or order == "invalid" then return "packet_" .. order end
  if s.syncAt ~= nil and (not finite(s.syncAt) or time < s.syncAt or time - s.syncAt > CONFIG.TIMING.SNAPSHOT_MAX_AGE) then return "snapshot_stale" end
  if s.targetUncertain or not targetOf(s) then return "target_unknown" end
end
local function activationTarget(state, s, time)
  local receipt = state.receipt
  if receipt and time >= receipt.at and time - receipt.at <= CONFIG.ACTIVATION.RETURN + networkLatency() then return receipt.target end
  if s and not s.targetUncertain then return targetOf(s) end
end
local function selectSnapshot(state, s, time)
  local cached = state.packetSnapshot
  if not s or not cached or s.ball ~= cached.ball or time < state.packetAt or time - state.packetAt > CONFIG.TIMING.PACKET_CACHE_AGE then return s end
  if s.teleported or s.resetting or s.locked or s.frozen or s.ballValid == false or s.valid == false or s.ballCanMove == false or s.mode == "training" then return s end
  local order = sequenceOrder(state, s.syncSequence)
  if order == "old" then return cached end
  if
    order == "same"
    and s.targetSignals
    and s.targetSignals.known
    and not s.targetUncertain
    and targetOf(s) == localPlayer.UserId
    and targetOf(cached) ~= localPlayer.UserId
    and cached.exchangeTargetId ~= nil
    and s.exchangeTargetId == nil
    and targetOf(s) ~= targetOf(cached)
  then
    local result = table.clone(s); result.exchangeTargetId = cached.exchangeTargetId
    return result
  end
  return s
end
local function geometry(s, factor)
  local speed = snapshotSpeed(s)
  if not speed or speed <= 0 then return nil end
  local g = deflectGeometry.getDeflectGeometry(speed, "game", factor or 1, false, networkLatency())
  if not g or not finite(g.effectiveWindow) or not finite(g.noWindowParryRadius) then return nil end
  local low, high = gameInfo.getBallSpeedLimits(); return deflectGeometry.withSpeedWindowBonus(g, speed, low, high, factor or 1), speed
end
local function compensatedRadius(id, speed)
  local radius = deflectGeometry.getPlayerRawRadius(id, speed, false)
  return finite(radius) and deflectGeometry.addLatencyRadius(radius, speed, id == localPlayer.UserId and networkLatency() or 0) or nil
end
local function flight(state, s, time)
  local speed = snapshotSpeed(s); local position, velocity = s.position, s.velocity
  if vector(s.syncDirection) and s.syncDirection.Magnitude > 0.001 then
    velocity = s.syncDirection / s.syncDirection.Magnitude * speed
    if vector(s.realPosition) and finite(s.syncAt) and time - s.syncAt <= CONFIG.ACTIVATION.DASH_MAX_SNAPSHOT_AGE then
      local elapsed = s.grace and 0 or math.clamp(time - s.syncAt, 0, 0.1); position = s.realPosition + velocity * elapsed
    end
  end
  return position, velocity, speed
end
local function ballDanger(state, s, target, lead)
  local position, motion = gameInfo.getPlayerMotion(target)
  if target == localPlayer.UserId then position, motion = state.root.Position, state.root.AssemblyLinearVelocity end
  if not vector(position) then return nil end
  local ballPosition, velocity, speed = flight(state, s, now()); local radius = deflectGeometry.getPlayerRawRadius(target, speed, false)
  local g = geometry(s, 1)
  if not finite(radius) or not g then return nil end
  return deflectGeometry.getDanger(ballPosition, velocity, position, speed, radius, lead or g.effectiveWindow, motion)
end
local function ballWindow(state, s, target)
  local danger = ballDanger(state, s, target); return danger and danger.ready or false
end
local function observeTarget(state, s, time, packet)
  if not packet and not (s.targetSignals and s.targetSignals.known) then return end
  local target = targetOf(s)
  if not target then return end
  local previous = state.target
  if previous == target then return end
  local me = localPlayer.UserId; state.leg = (state.leg or 0) + 1
  local distance = vector(s.position) and (s.position - state.root.Position).Magnitude or nil
  state.target, state.receipt = target, { target = target, at = time, position = s.position, distance = distance, leg = state.leg }; state.pending, state.exchange = nil, nil
  if state.lastSwitchAt then state.intervalMs = (time - state.lastSwitchAt) * 1000 end
  state.lastSwitchAt = time
  if previous == me and target ~= me then
    state.outbound = { partner = target, at = time }; state.previousOpponent = target
    state.exchange = { partner = target, at = time }
  elseif target == me and previous and previous ~= me then
    local outbound = state.outbound
    if outbound and outbound.partner == previous and time >= outbound.at and time - outbound.at <= CONFIG.ACTIVATION.RETURN + networkLatency() then
      local h = state.confirmedReturns; local count = h and h.partner == previous and time - h.at <= CONFIG.TIMING.HISTORY_MAX_AGE and h.count + 1 or 1
      state.confirmedReturns = { partner = previous, count = count, at = time }; state.pending = { partner = previous, at = time, leg = state.leg }
      state.cooldownSince = time; state.exchange = { partner = previous, at = time }
    end
    state.previousOpponent, state.outbound = previous, nil
  elseif previous then
    state.outbound, state.confirmedReturns = nil, nil
  end
  local h = state.exchangeHistory or {}; state.exchangeHistory = h
  if state.exchange then
    state.lastPairExchangeAt = time
    if target == me then
      if h.partner == previous and h.inboundAt then h.cycle = time - h.inboundAt end
      h.partner, h.inboundAt = previous, time
    end
    h.exchangeAt = time
  elseif previous then
    state.exchangeHistory, state.lastPairExchangeAt = nil, nil
  end
end
local function cooldownExpired(state, s, time)
  local cd = cooldownInfo.getDeflectCooldownState(); state.cooldown = cd
  if not cd or cd.source == "unknown" or cd.blocking ~= true or cd.predictedReset == true then state.cooldownSince, state.cooldownEpisode = nil, nil; return false end
  if finite(cd.lastParriedAt) and cd.lastParriedAt ~= state.cooldownParriedAt then state.cooldownParriedAt, state.cooldownSince = cd.lastParriedAt, time end
  if not state.cooldownSince or (cd.episode ~= nil and state.cooldownEpisode ~= cd.episode) then
    state.cooldownSince = finite(cd.blockingSince) and cd.blockingSince <= time and cd.blockingSince or time; state.cooldownEpisode = cd.episode
  end
  local speed = snapshotSpeed(s) or 0; local low, high = gameInfo.getBallSpeedLimits()
  local progress = finite(low) and finite(high) and high > low and math.clamp((speed - low) / (high - low), 0, 1) or 0; local other = playerPosition(state.partner)
  local distance = other and (other - state.root.Position).Magnitude; local proximity = distance and math.clamp(1 - distance / 20, 0, 1) or 0
  state.cooldownLimit = math.min(0.5, 0.225 - 0.125 * progress + networkLatency() + proximity * 0.12); return time - state.cooldownSince >= state.cooldownLimit
end
local function hardStop(state, s)
  if not utils.isActive() then return "hub_inactive" end
  if not state.external and utils.getConfigValue("AutoSpam") ~= true then return "disabled" end
  if not state.character.Parent or not state.root.Parent or not playerIsAlive(localPlayer.UserId) then return "player_died" end
  if state.deathSerial and state.deathSerial ~= matchDeathSerial then return "match_player_died" end
  if state.partner and not playerIsAlive(state.partner) then return "opponent_left_or_died" end
  if s and (s.teleported or s.resetting or (state.ball and s.ball ~= state.ball)) then return "ball_reset" end
  local target = s and not s.targetUncertain and targetOf(s)
  if state.active and state.partner and target and target ~= localPlayer.UserId and target ~= state.partner then return "target_redirected_far" end
end
local function predictionBudget(state)
  return math.min(CONFIG.TIMING.PREDICTION_MAX_BUDGET, CONFIG.TIMING.PREDICTION_MIN_BUDGET + networkLatency() * 2 + frameLead(state) * 2)
end
local function liveAttempt(state, partner, time)
  local sensor = state.sensors and state.sensors[partner]; local attempt = sensor and sensor.attempt
  if not attempt or attempt.ball ~= state.ball or time < attempt.at or time > attempt.expiresAt then return nil end
  local playing = false
  for track in pairs(attempt.tracks) do
    if track.IsPlaying then playing = true; break end
  end
  if playing then attempt.lastPlayingAt = time end
  if not playing and time - (attempt.lastPlayingAt or attempt.at) > CONFIG.SIGNAL.STOP_GRACE + networkLatency() then return nil end
  return attempt
end
local function solveReturn(state, s, time)
  state.gates.prediction = "waiting_opponent_target"; state.predictionEvidence = nil
  local partner = activationTarget(state, s, time)
  if not partner or partner == localPlayer.UserId then return nil end
  if not nearPartner(state, partner, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE) then state.gates.prediction = "opponent_out_of_range"; return nil end
  local attempt = liveAttempt(state, partner, time); local outbound = state.outbound
  local contactEvidence = outbound and outbound.partner == partner and time - outbound.at <= CONFIG.ACTIVATION.RETURN
  if not attempt and not contactEvidence then state.gates.prediction = "waiting_deflect_evidence"; return nil end
  if attempt and attempt.used then state.gates.prediction = "attempt_consumed"; return nil end
  if state.consumedLeg == state.leg then state.gates.prediction = "leg_consumed"; return nil end
  local aimed, score, margin, source = gameInfo.getDeflectTargetPrediction(partner)
  if aimed ~= localPlayer.UserId then state.gates.prediction = "return_not_aimed_at_self"; return nil end
  local other, motion = gameInfo.getPlayerMotion(partner); local own = state.root.Position
  if not vector(other) then return nil end
  motion = vector(motion) and motion or Vector3.zero; local nominal = snapshotSpeed(s)
  if not nominal or nominal <= 0 or not vector(s.position) or not vector(s.velocity) then return nil end
  local position, velocity, speed = flight(state, s, time); local window = deflectGeometry.getDeflectWindow(speed, false)
  local otherRadius = deflectGeometry.getPlayerRawRadius(partner, speed, false); local ownRadius = deflectGeometry.getPlayerRawRadius(localPlayer.UserId, speed, false)
  if not finite(window) or not finite(otherRadius) or not finite(ownRadius) then return nil end
  local budget = predictionBudget(state); local physicalDanger = deflectGeometry.getDanger(position, velocity, other, speed, otherRadius, budget, motion)
  local arrival = math.max(0, (position - other).Magnitude - otherRadius) / speed
  if attempt and attempt.phase == "parry" then arrival = 0 end
  if physicalDanger and physicalDanger.ready and finite(physicalDanger.entryTime) then arrival = math.min(arrival, math.max(0, physicalDanger.entryTime)) end
  if not attempt and arrival > frameLead(state) then state.gates.prediction = "waiting_deflect_evidence"; return nil end
  local futureOther = other + motion * arrival; local ownMotion = vector(state.root.AssemblyLinearVelocity) and state.root.AssemblyLinearVelocity or Vector3.zero
  local futureOwn = own + ownMotion * arrival; local returnTime = math.max(0, (futureOther - futureOwn).Magnitude - otherRadius - ownRadius) / speed
  if arrival + returnTime > budget then state.gates.prediction = "return_has_reaction_time"; return nil end
  local danger = physicalDanger
  if attempt and attempt.phase ~= "parry" and time + arrival > attempt.expiresAt then state.gates.prediction = "attempt_expires_before_contact"; return nil end
  local evidence = {
    partner = partner,
    leg = state.leg,
    at = time,
    contactIn = arrival,
    returnIn = returnTime,
    deadline = time + math.min(0.45, arrival + returnTime + networkLatency() * 2 + frameLead(state) * 2 + 0.06),
    source = attempt and attempt.source or "outbound_contact",
    animationPhase = attempt and attempt.phase,
    aimSource = source,
    aimScore = score,
    aimMargin = margin,
    danger = danger,
  }

  state.predictionEvidence, state.gates.prediction = evidence, "ready"
  return { reason = attempt and "extreme_return_prediction" or "contact_return_prediction", partner = partner, prediction = evidence, attempt = attempt }
end
local function dashPrediction(state, s, time)
  if s.syncAt == nil or time - s.syncAt > CONFIG.ACTIVATION.DASH_MAX_SNAPSHOT_AGE then return nil, "dash_snapshot_stale" end
  local function forPartner(partner)
    if not nearPartner(state, partner, CONFIG.ACTIVATION.DASH_DETECTION_RANGE) then return nil, "dash_no_partner" end
    if targetOf(s) ~= localPlayer.UserId and targetOf(s) ~= partner then return nil, "dash_target" end
    if not ballWindow(state, s, targetOf(s)) then return nil, "dash_ball_outside_window" end
    local own, other = state.root.Position, playerPosition(partner); local g, speed = geometry(s, 1)
    if not g then return nil, "dash_geometry" end
    local ownRadius, otherRadius = compensatedRadius(localPlayer.UserId, speed), deflectGeometry.getPlayerRawRadius(partner, speed, false)
    if not finite(ownRadius) or not finite(otherRadius) then return nil, "dash_geometry" end
    local function model(sample, relative, reason)
      if
        not sample
        or sample.ability ~= "normal"
        or not sample.signalActive
        or not sample.normalModel
        or not vector(sample.velocity)
        or not finite(sample.observedAt)
        or not vector(sample.position)
      then
        return nil
      end
      local exchange = state.exchange
      if not exchange or exchange.partner ~= partner or exchange.at < sample.observedAt or exchange.at > time or exchange.at - sample.observedAt > 0.2 then return nil end
      local age, magnitude, remaining = time - sample.observedAt, sample.velocity.Magnitude, sample.normalModel.estimatedRemaining; local distance = relative.Magnitude
      if age < 0 or age > 0.2 or magnitude < 70 or magnitude > 140 or not finite(remaining) or remaining <= 0 or distance <= 0.05 then return nil end
      local closing = sample.velocity:Dot(relative) / distance
      if closing / magnitude < CONFIG.ACTIVATION.DASH_MIN_ALIGNMENT then return nil end
      local closestAt = math.clamp(relative:Dot(sample.velocity) / sample.velocity:Dot(sample.velocity), 0, remaining); local predicted = (relative - sample.velocity * closestAt).Magnitude
      local limit = math.min(CONFIG.ACTIVATION.MAX_CLASH_DISTANCE, deflectGeometry.projectRadius(ownRadius, speed, g.effectiveWindow, 1, 0, otherRadius))
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
  if targetOf(s) ~= localPlayer.UserId then return forPartner(targetOf(s)) end
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
local function chooseActivation(state, s, time)
  local target = activationTarget(state, s, time); local receipt = state.receipt
  state.gates.close = "waiting_close_receipt"
  if
    target == localPlayer.UserId
    and receipt
    and receipt.target == localPlayer.UserId
    and receipt.leg == state.leg
    and not receipt.used
    and finite(receipt.distance)
    and receipt.distance <= CONFIG.ACTIVATION.CLOSE_TARGET_DISTANCE
  then
    local partner = nearPartner(state, state.previousOpponent, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE)
      or nearestPartner(state, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE)
    state.gates.close = "ready"; return { reason = "close_target", partner = partner, closeReceipt = receipt }
  end
  if utils.getConfigValue("AutoSpamClashPrediction") ~= false then
    local candidate = solveReturn(state, s, time)
    if candidate then return candidate end
  else
    state.gates.prediction = "disabled"
  end
  local pending = state.pending; state.gates.returnTarget = pending and "return_expired" or "return_no_round_trip"
  if
    pending
    and not pending.used
    and target == localPlayer.UserId
    and time >= pending.at
    and time - pending.at <= CONFIG.ACTIVATION.RETURN + networkLatency()
  then
    state.gates.returnTarget = "ready"; return { reason = "return_target", partner = pending.partner, pending = pending }
  end
  local predictionSample = table.clone(s)
  if target then predictionSample.targetId, predictionSample.exchangeTargetId = target, target end
  dashInfo.tick(time, false, state.root.Position, CONFIG.ACTIVATION.DASH_DETECTION_RANGE); local dash, dashGate = dashPrediction(state, predictionSample, time)
  state.dashPrediction, state.gates.dash = dash, dashGate
  if dash then return dash end
  local event = state.haunter; state.gates.haunter = event and "haunter_expired" or "haunter_no_event"
  if
    event
    and time >= event.at
    and time - event.at <= CONFIG.ACTIVATION.HAUNTER_LIFETIME
    and nearPartner(state, event.partner, CONFIG.ACTIVATION.HAUNTER_RANGE)
    and (target == localPlayer.UserId or target == event.partner)
    and ballWindow(state, s, target)
  then
    state.gates.haunter = "ready"; return event
  end
end
local function activate(state, candidate, s, time)
  state.active, state.phase, state.reason, state.partner = true, candidate.prediction and "anticipating" or "clashing", candidate.reason, candidate.partner
  state.activatedAt, state.deathSerial, state.lastGate = time, matchDeathSerial, candidate.reason; state.distanceSince, state.physicalExitSince, state.reactivateAt = nil, nil, nil
  state.prediction = candidate.prediction; state.anticipatingUntil = candidate.prediction and candidate.prediction.deadline
  if candidate.prediction then state.consumedLeg = state.leg end
  if candidate.attempt then candidate.attempt.used = true end
  if candidate.pending then candidate.pending.used = true end
  if candidate.closeReceipt then candidate.closeReceipt.used = true end
  state.activationEvidence = { at = time, ball = s.ball, partner = candidate.partner, target = activationTarget(state, s, time) }; state.cooldownSince = time
  local cd = cooldownInfo.getDeflectCooldownState(); state.cooldownEpisode = cd and cd.episode
  lastActivationReason, lastActivationAt = candidate.reason, time; clashStatsModule.begin(candidate.partner, time)
  utils.recordTransition("AutoSpam", "idle", "active", candidate.reason); utils.setAutoSpamActive(true)
end
local function activeStop(state, s, time)
  local reason = hardStop(state, s)
  if reason then return reason end
  if cooldownExpired(state, s, time) then return "cooldown" end
  if state.prediction then
    if activationTarget(state, s, time) == localPlayer.UserId then
      state.phase, state.prediction, state.anticipatingUntil = "clashing", nil, nil
    else
      if utils.getConfigValue("AutoSpamClashPrediction") == false then return "prediction_disabled" end
      if time >= state.prediction.deadline then return "anticipation_expired" end
      local aim = gameInfo.getDeflectTargetPrediction(state.partner)
      if aim and aim ~= localPlayer.UserId then return "prediction_redirected" end
    end
  end
  local other = playerPosition(state.partner)
  if not other or (other - state.root.Position).Magnitude > CONFIG.ACTIVATION.MAX_CLASH_DISTANCE then
    state.distanceSince = state.distanceSince or time
    if time - state.distanceSince >= CONFIG.TIMING.DISTANCE_EXIT_DELAY then return "clash_distance" end
  else
    state.distanceSince = nil
  end
  if not other or not s or not vector(s.position) or not vector(s.velocity) then return nil end
  local speed = snapshotSpeed(s)
  if not speed then return nil end
  local g = geometry(s, 1); local range = g and g.fullRadius or 20
  local ownDelta, otherDelta = state.root.Position - s.position, other - s.position
  if ownDelta.Magnitude > range and otherDelta.Magnitude > range and s.velocity:Dot(ownDelta) < 0 and s.velocity:Dot(otherDelta) < 0 then
    state.physicalExitSince = state.physicalExitSince or time
    if time - state.physicalExitSince >= CONFIG.TIMING.PHYSICAL_EXIT_DELAY then return "ball_left_exchange" end
  else
    state.physicalExitSince = nil
  end
end
local function deactivationGate(state, s, time, protectedUntil)
  local reason = activeStop(state, s, time)
  if reason and (reason == "player_died" or reason == "hub_inactive" or reason == "ball_reset" or time >= (protectedUntil or 0)) then return reason end
end
local function rememberContinuity(state, time)
  local h, returns = state.exchangeHistory, state.confirmedReturns
  if
    not h
    or not returns
    or returns.partner ~= state.partner
    or returns.count < 2
    or not finite(h.cycle)
    or h.cycle <= 0
    or h.cycle > CONFIG.ACTIVATION.RETURN
    or not state.lastPairExchangeAt
  then
    return
  end
  state.sendContinuity = {
    ball = state.ball,
    at = state.lastPairExchangeAt,
    expiresAt = state.lastPairExchangeAt + math.clamp(h.cycle + networkLatency() + frameLead(state) * 2, 0.08, 0.2),
  }
end
local function canBridge(state, s, time, gate)
  if gate ~= "target_unknown" and gate ~= "snapshot_stale" and gate ~= "position_disagreement" and gate ~= "snapshot_invalid" then return false end
  local evidence = state.sendContinuity
  if not evidence or evidence.ball ~= state.ball or not state.ball.Parent or time < evidence.at or time > evidence.expiresAt then return false end
  if not nearPartner(state, state.partner, 14) or gameInfo.getBallFrozen() == true then return false end
  if
    s
    and (
      s.ball ~= state.ball
      or s.locked
      or s.resetting
      or s.teleported
      or s.mode == "training"
      or s.ballCanMove == false
      or s.ballValid == false
      or s.valid == false
    )
  then
    return false
  end
  state.lastBridgedSendAt = time; return true
end
local function observeStats(state, s, time, packet)
  if not s or not gameInfo.isSnapshotValid(s) then return end
  local stats = clashStatsModule.get()
  if stats and stats.frozen and not state.active then clashStatsModule.waitForNextClash() end
  clashStatsModule.observe(state, s, time, packet == true)
end
evaluate = function(state, s, time, packet)
  if current ~= state then return end
  state.gates = {}; local stop = hardStop(state, s)
  if stop then
    deactivate(state, stop, time); state.lastGate = stop
    clearEvidence(state)
    if stop ~= "ball_reset" then return end
  end
  if s and s.ball ~= state.ball then state.ball, state.sequence, state.packetSnapshot, state.packetAt = s.ball, nil, nil, nil; clearEvidence(state) end
  local order = sequenceOrder(state, s and s.syncSequence)
  if order == "old" or order == "invalid" then state.lastGate = "packet_" .. order; return end
  if order == "new" then state.sequence = s.syncSequence end
  if packet then state.packetSnapshot, state.packetAt = table.clone(s), time end
  local gate = lifecycleGate(state, s)
  if s and gate ~= "ball_reset" and gate ~= "training" and gate ~= "ball_paused" then observeTarget(state, s, time, packet) end
  if state.active then
    stop = deactivationGate(state, s, time, 0)
    if stop then
      deactivate(state, stop, time)
      if stop == "ball_reset" or stop == "ball_left_exchange" then clearEvidence(state) end
      return
    end
    rememberContinuity(state, time)
    if gate == "ball_paused" or gate == "training" or gate == "ball_not_moving" or gate == "ball_reset" then
      deactivate(state, gate, time); clearEvidence(state)
      return
    end
    state.lastGate, state.gates.common = gate or "active", gate; observeStats(state, s, time, packet)
    return
  end
  state.gates.common = gate
  if gate then
    state.lastGate = gate
    if gate == "ball_reset" or gate == "training" or gate == "ball_paused" then clearEvidence(state) end
    return
  end
  local candidate = chooseActivation(state, s, time)
  if candidate then activate(state, candidate, s, time); rememberContinuity(state, time) else state.lastGate = "no_activation_evidence" end
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
local function animationId(track)
  local animation = track.Animation; local asset = animation and animation.AnimationId
  return type(asset) == "string" and (asset:match("[?&]id=(%d+)") or asset:match("%d+")) or nil
end
local function observeAnimation(state, sensor, track, seeded)
  if current ~= state or sensor.player.Character ~= sensor.character or sensor.player == localPlayer or track.IsPlaying == false then return end
  local id = animationId(track); local phase = id and state.animationCatalog[id]
  if id and not phase and now() >= (state.nextUnknownCatalogAt or 0) then
    state.nextUnknownCatalogAt = now() + 0.05; state.animationCatalog = gameInfo.getDeflectAnimationCatalog()
    phase = state.animationCatalog[id]
  end
  if not phase then return end
  if seeded and sensor.tracks[track] then return end
  local time = now(); local playback = track.TimePosition
  local rate = track.Speed; local age = seeded and finite(playback) and finite(rate) and rate > 0 and math.max(0, playback / rate) or 0
  if phase == "loop" then age = 0 end
  local lifetime = phase == "parry" and CONFIG.SIGNAL.SUCCESS_LIFETIME or CONFIG.SIGNAL.BLOCK_LIFETIME; sensor.tracks[track] = true
  if age >= lifetime then return end
  local attempt = sensor.attempt
  if
    not attempt
    or attempt.ball ~= state.ball
    or time > attempt.expiresAt
    or (phase == "start" and time - attempt.observedAt > CONFIG.SIGNAL.MERGE_INTERVAL)
    or (phase == "parry" and attempt.phase ~= "parry")
  then
    attempt = {
      at = time - age,
      observedAt = time,
      expiresAt = time - age + lifetime,
      ball = state.ball,
      source = seeded and "animation_scan" or "animation_event",
      phase = phase,
      tracks = {},
    }

    sensor.attempt = attempt
  end
  attempt.tracks[track], attempt.lastPlayingAt = true, time
  if phase == "parry" then attempt.phase = "parry" end
  if not seeded then evaluate(state, selectSnapshot(state, gameInfo.getSnapshotAt(time), time), time, false) end
end
local function scanAnimations(state, time)
  if time >= (state.nextCatalogAt or 0) then state.nextCatalogAt = time + CONFIG.SIGNAL.CATALOG_INTERVAL; state.animationCatalog = gameInfo.getDeflectAnimationCatalog() end
  if time < (state.nextScanAt or 0) then return end
  state.nextScanAt = time + CONFIG.SIGNAL.SCAN_INTERVAL
  for id, sensor in pairs(state.sensors) do
    for track in pairs(sensor.tracks) do
      if not track.IsPlaying then sensor.tracks[track] = nil end
    end
    if sensor.attempt and time > sensor.attempt.expiresAt then sensor.attempt = nil end
    local near = id == state.target or id == state.partner or nearPartner(state, id, CONFIG.ACTIVATION.DASH_DETECTION_RANGE)
    if near and sensor.animator and sensor.character == sensor.player.Character then
      for _, track in ipairs(sensor.animator:GetPlayingAnimationTracks()) do
        observeAnimation(state, sensor, track, true)
      end
    end
  end
end
local function watchPlayer(state, player)
  if state.sensors[player.UserId] then return end
  local sensor = { player = player, characterConnections = {}, playerConnections = {}, tracks = {}, lives = player:GetAttribute("Lives") }
  state.sensors[player.UserId] = sensor
  local world = utils.getWorkspace()
  local function death()
    if current ~= state or world:GetAttribute("MatchStatus") ~= 6 or sensor.reported or not sensor.participated then return end
    sensor.reported = true; matchDeathSerial += 1
    deactivate(state, "match_player_died", now())
  end
  local function updateLives()
    local lives = player:GetAttribute("Lives")
    if world:GetAttribute("MatchStatus") == 6 and finite(lives) and lives > 0 and player:GetAttribute("Playing") ~= false then sensor.participated = true end
    if finite(sensor.lives) and sensor.lives > 0 and finite(lives) and lives <= 0 then death() end
    sensor.lives = lives
  end
  local function watchCharacter(character)
    disconnectPool(state, sensor.characterConnections); sensor.character, sensor.animator, sensor.humanoid, sensor.attempt, sensor.reported = character, nil, nil, nil, false
    sensor.animationConnection = nil; table.clear(sensor.tracks)
    local function watchHumanoid(humanoid)
      if current ~= state or player.Character ~= character or not humanoid:IsA("Humanoid") or sensor.humanoid == humanoid then return end
      sensor.humanoid = humanoid; listen(state, humanoid.Died, death, sensor.characterConnections)
      local function watchAnimator(animator)
        if current ~= state or player.Character ~= character or sensor.humanoid ~= humanoid or not animator:IsA("Animator") or sensor.animator == animator then return end
        if sensor.animationConnection then sensor.characterConnections[sensor.animationConnection] = nil; disconnectPool(state, { [sensor.animationConnection] = true }) end
        sensor.animator = animator
        sensor.attempt = nil; table.clear(sensor.tracks)
        sensor.animationConnection = listen(
          state,
          animator.AnimationPlayed,
          function(track) observeAnimation(state, sensor, track, false) end,
          sensor.characterConnections
        )
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
          observeAnimation(state, sensor, track, true)
        end
      end
      local animator = humanoid:FindFirstChildOfClass("Animator")
      if animator then watchAnimator(animator) end
      listen(state, humanoid.ChildAdded, watchAnimator, sensor.characterConnections)
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then watchHumanoid(humanoid) end
    listen(state, character.ChildAdded, watchHumanoid, sensor.characterConnections); updateLives()
  end
  listen(state, player:GetAttributeChangedSignal("Lives"), updateLives, sensor.playerConnections); listen(state, player:GetAttributeChangedSignal("Playing"), updateLives, sensor.playerConnections)
  listen(state, player.CharacterAdded, watchCharacter, sensor.playerConnections)
  if player.Character then watchCharacter(player.Character) else updateLives() end
end
local function detach(reason)
  local state = current
  if not state then return end
  local stats = clashStatsModule.get()
  if stats and not stats.frozen then clashStatsModule.finish(reason, now()) end
  deactivate(state, reason, now()); current = nil
  generation += 1; disconnectPool(state, state.connections)
end
function AutoSpam.setup(deps)
  if type(deps) ~= "table" or not deps.Utils or not deps.GameInfo or not deps.ClashStats or not deps.Cooldown or not deps.Dash or not deps.DeflectGeometry then
    return false, "dependências ausentes"
  end
  if current then detach("setup") end
  utils, gameInfo, clashStatsModule, cooldownInfo, dashInfo, deflectGeometry =
    deps.Utils, deps.GameInfo, deps.ClashStats, deps.Cooldown, deps.Dash, deps.DeflectGeometry
  players, runService, localPlayer = utils.getPlayers(), utils.getRunService(), utils.getLocalPlayer()
  if not players or not runService or not localPlayer then return false, "serviços indisponíveis" end
  return true
end
function AutoSpam.bindCharacter(character)
  detach("rebind"); local root = character and character:FindFirstChild("HumanoidRootPart")
  if not root or not root:IsA("BasePart") then return false, "HumanoidRootPart indisponível" end
  local state = {
    character = character,
    root = root,
    connections = {},
    sensors = {},
    active = false,
    phase = "idle",
    reason = "waiting",
    lastGate = "waiting",
    gates = {},
    leg = 0,
    lastRootPosition = root.Position,
    animationCatalog = gameInfo.getDeflectAnimationCatalog(),
  }

  current = state; local initial = gameInfo.getSnapshotAt(now())
  state.ball = initial and initial.ball; connectHaunter(state)
  for _, player in ipairs(players:GetPlayers()) do
    watchPlayer(state, player)
  end
  listen(state, players.PlayerAdded, function(player)
    if current == state then watchPlayer(state, player) end
  end)
  listen(state, players.PlayerRemoving, function(player)
    local sensor = state.sensors[player.UserId]
    if sensor then
      disconnectPool(state, sensor.characterConnections); disconnectPool(state, sensor.playerConnections)
      state.sensors[player.UserId] = nil
    end
    if state.partner == player.UserId then deactivate(state, "opponent_left_or_died", now()) end
    if state.previousOpponent == player.UserId then clearEvidence(state) end
  end)
  local world = utils.getWorkspace()
  listen(state, world:GetAttributeChangedSignal("MatchStatus"), function()
    clearEvidence(state)
    for _, sensor in pairs(state.sensors) do
      local lives = sensor.player:GetAttribute("Lives"); sensor.lives, sensor.reported = lives, false
      sensor.participated = world:GetAttribute("MatchStatus") == 6 and finite(lives) and lives > 0 and sensor.player:GetAttribute("Playing") ~= false
    end
    if world:GetAttribute("MatchStatus") ~= 6 then deactivate(state, "match_ended", now()) end
  end)
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if humanoid then
    listen(state, humanoid.Died, function()
      if current == state then clashStatsModule.freeze(localPlayer.UserId, state); deactivate(state, "player_died", now()) end
    end)
  end
  listen(state, runService.Heartbeat, function(dt)
    if current ~= state then return end
    local time = now()
    if finite(dt) and dt > 0 then state.frameInterval = dt end
    if time >= (state.nextHaunterCheck or 0) then state.nextHaunterCheck = time + 0.5; connectHaunter(state) end
    if vector(state.lastRootPosition) and (root.Position - state.lastRootPosition).Magnitude > CONFIG.ACTIVATION.HAUNTER_RANGE then
      state.recentRootPosition, state.recentRootAt = state.lastRootPosition, time
    end
    scanAnimations(state, time); evaluate(state, selectSnapshot(state, gameInfo.getSnapshotAt(time), time), time, false)
    if state.active then rememberContinuity(state, time) end
    state.lastRootPosition = root.Position
  end)
  local fastSignals = {}
  for _, signal in pairs({ runService.PreSimulation, runService.PostSimulation, runService.RenderStepped }) do
    if signal and signal ~= runService.Heartbeat and not fastSignals[signal] then
      fastSignals[signal] = true
      listen(state, signal, function()
        if current == state then evaluate(state, selectSnapshot(state, gameInfo.getSnapshotAt(now()), now()), now(), false) end
      end)
    end
  end
  listen(state, character.AncestryChanged, function(_, parent)
    if not parent and current == state then detach("character_removed") end
  end)
  return true
end
function AutoSpam.detachCharacter() detach("detach") end
function AutoSpam.teardown()
  detach("teardown"); utils, gameInfo, clashStatsModule, cooldownInfo, dashInfo, deflectGeometry = nil, nil, nil, nil, nil, nil
  players, runService, localPlayer = nil, nil, nil
end
function AutoSpam.onBallSync(data)
  local state = current
  if not state or type(data) ~= "table" then return end
  local time = now(); local s = gameInfo.getSnapshotAt(time)
  if not s then return end
  local received = data.Source == "packet" or data.Source == "replicator"
  if received then
    local incoming = data.Sequence or data.TeleportSequence; local order = sequenceOrder(state.ball == s.ball and state or {}, incoming)
    if order == "old" or order == "invalid" or (order == "same" and data.Teleported ~= true) then return end
    s = table.clone(s); s.syncSequence, s.syncAt = incoming, time
    if data.TargetPlayerID ~= nil then
      s.exchangeTargetId, s.targetId, s.targetUncertain = data.TargetPlayerID, data.TargetPlayerID, not userId(data.TargetPlayerID); s.targeted = data.TargetPlayerID == localPlayer.UserId
    end
    if data.Speed ~= nil then s.syncSpeed = data.Speed end
    if data.RealPosition ~= nil then s.realPosition = data.RealPosition end
    if vector(data.ForcedDirection) then s.syncDirection = data.ForcedDirection end
    s.teleported = data.Teleported == true
    if type(data.Locked) == "boolean" then s.locked = data.Locked end
    if data.ServerTime ~= nil then s.serverTime = data.ServerTime end
  end
  local targetEvent = data.Source == "target" and userId(data.TargetPlayerID) or nil or nil
  if targetEvent then
    s = table.clone(s); s.syncSequence = state.sequence or s.syncSequence
    s.targetId, s.exchangeTargetId = targetEvent, targetEvent; s.targeted, s.targetUncertain = targetEvent == localPlayer.UserId, false
  end
  evaluate(state, s, time, received or targetEvent ~= nil)
  if received then state.packetSnapshot, state.packetAt = s, time end
  if state.active then rememberContinuity(state, time) end
end
function AutoSpam.onDefenseOpportunity(snapshot)
  local state = current
  if state and snapshot and snapshot.mode ~= "training" then evaluate(state, snapshot, now(), false) end
  return AutoSpam.isActive()
end
function AutoSpam.isActive() return current ~= nil and current.active end
function AutoSpam.canSendManual()
  local state = current; return state ~= nil
    and utils ~= nil
    and utils.isActive()
    and utils.isManualSpamActive()
    and state.root.Parent ~= nil
    and state.character.Parent ~= nil
    and playerIsAlive(localPlayer.UserId)
end
function AutoSpam.canSend()
  local state = current
  if not state or not state.active then return false end
  local time = now(); local s = selectSnapshot(state, gameInfo.getSnapshotAt(time), time)
  local stop = deactivationGate(state, s, time, 0)
  if stop then
    deactivate(state, stop, time); state.lastSendBlockReason, state.lastSendBlockAt = stop, time
    return false
  end
  local gate = sampleGate(state, s, time); local activation = state.activationEvidence
  local recentActivation = activation
    and activation.ball == state.ball
    and time >= activation.at
    and time - activation.at <= math.max(0.1, frameLead(state) * 2 + networkLatency())
    and not lifecycleGate(state, s)
  if
    gate
    and not (recentActivation and (gate == "target_unknown" or gate == "snapshot_stale" or gate == "packet_old"))
    and not canBridge(state, s, time, gate)
  then
    state.lastSendBlockReason, state.lastSendBlockAt = gate, time; return false
  end
  return true
end
function AutoSpam.hasClashPrediction() return true end
function AutoSpam.createManualSession()
  local character = localPlayer.Character; local root = character and character:FindFirstChild("HumanoidRootPart")
  if not root then return nil end
  local reference = current and current.active and current
  return {
    external = true,
    active = true,
    character = character,
    root = root,
    activatedAt = now(),
    deathSerial = matchDeathSerial,
    partner = reference and reference.partner,
    ball = reference and reference.ball,
    gates = {},
    leg = 0,
  }
end
function AutoSpam.getManualStopReason(state, protectedUntil)
  if not state then return "player_died", false end
  local time = now(); local s = gameInfo.getSnapshotAt(time)
  if not state.partner then state.partner = nearestPartner(state, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE) end
  if not state.ball and s then state.ball = s.ball end
  local reason = deactivationGate(state, s, time, protectedUntil)
  if reason then return reason, false end
  return nil, true
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
function AutoSpam.getStatus()
  local state = current; local time = utils and now() or 0
  local s = state and gameInfo.getSnapshotAt(time); local animations = {}
  if state then
    for id, sensor in pairs(state.sensors) do
      local attempt = sensor.attempt
      if attempt and time <= attempt.expiresAt then
        animations[id] =
          { age = time - attempt.at, remaining = attempt.expiresAt - time, phase = attempt.phase, source = attempt.source, consumed = attempt.used == true }
      end
    end
  end
  return {
    active = state ~= nil and state.active,
    phase = state and state.phase or "detached",
    engineVersion = 4,
    reason = state and state.reason,
    windowFactor = 1,
    gates = state and table.clone(state.gates) or {},
    targetId = state and state.target or -1,
    clashPartnerId = state and state.partner or -1,
    targetUncertain = s and s.targetUncertain == true or false,
    snapshotAge = s and finite(s.syncAt) and time - s.syncAt or nil,
    ballDistance = s and state and vector(s.position) and (s.position - state.root.Position).Magnitude or nil,
    anticipationRemaining = state and state.anticipatingUntil and math.max(0, state.anticipatingUntil - time) or 0,
    reactivationRemaining = state and state.reactivateAt and math.max(0, state.reactivateAt - time) or 0,
    reactivationDelay = CONFIG.TIMING.REARM_DELAY,
    confirmedReturns = state and state.confirmedReturns and state.confirmedReturns.count or 0,
    prediction = state and state.prediction and table.clone(state.prediction) or nil,
    predictionEvidence = state and state.predictionEvidence and table.clone(state.predictionEvidence) or nil,
    animationSignals = animations,
    frameLead = state and frameLead(state) or nil,
    danger = state and state.danger and table.clone(state.danger) or nil,
    dashPrediction = state and state.dashPrediction,
    cooldownLimit = state and state.cooldownLimit,
    cooldownElapsed = state and state.cooldownSince and time - state.cooldownSince or nil,
    activationReason = state and state.active and state.reason or nil,
    lastActivationReason = lastActivationReason,
    lastActivationAt = lastActivationAt,
    lastStopReason = lastStopReason,
    lastStopAt = lastStopAt,
    lastSendBlockReason = state and state.lastSendBlockReason,
    lastSendBlockAt = state and state.lastSendBlockAt,
    lastBridgedSendAt = state and state.lastBridgedSendAt,
    clashStats = clashStatsModule and clashStatsModule.getStatus() or nil,
  }
end

-- contract
AutoSpam.__contract = {
  requires = {
    DeflectGeometry = "deflectgeometry",
    Utils = "utils",
    GameInfo = "gameinfo",
    ClashStats = "clashstats",
    Cooldown = "cooldown",
    Dash = "dash",
  },
  requiresMethods = {
    DeflectGeometry = {
      "getDanger",
      "getDeflectWindow",
      "getKillRadius",
      "getDefensePhysics",
      "getPlayerRawRadius",
      "addLatencyRadius",
      "getDeflectGeometry",
      "withSpeedWindowBonus",
      "projectRadius",
    },
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
      "trackCharacter",
      "untrackCharacter",
      "recordTransition",
      "apiVersion",
    },
    GameInfo = {
      "getDeflectTargetPrediction",
      "getDeflectAnimationCatalog",
      "areAbilitiesEnabled",
      "getSnapshotAt",
      "isSnapshotValid",
      "getPlayerMotion",
      "getHaunterEvent",
      "getLocalDashState",
      "getBallFrozen",
      "getAveragePing",
      "getTargetId",
      "getBallSpeedLimits",
    },
    Cooldown = { "getDeflectCooldownState" },
    Dash = { "tick", "getEstimate" },
    ClashStats = { "getStatus", "begin", "finish", "observe", "freeze", "get", "waitForNextClash" },
  },
  provides = {
    "setup",
    "bindCharacter",
    "detachCharacter",
    "teardown",
    "onBallSync",
    "onDefenseOpportunity",
    "isActive",
    "canSend",
    "canSendManual",
    "getActivationContext",
    "getStatus",
    "getTargetSwitch",
    "getDashData",
    "stopSpam",
    "hasClashPrediction",
    "createManualSession",
    "getManualStopReason",
  },
  onBallSync = true,
  bindCharacter = true,
}

return AutoSpam
