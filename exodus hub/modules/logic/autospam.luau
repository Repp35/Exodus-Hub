-- [[ auto spam ]]

local AutoSpam = {}

local utils, gameInfo, clashStatsModule, cooldownInfo, dashInfo, deflectGeometry
local players, runService, localPlayer, current
local generation, matchDeathSerial = 0, 0
local lastActivationReason, lastActivationAt, lastStopReason, lastStopAt
local evaluate
local CONFIG = {
  ACTIVATION = {
    RETURN = 0.6,
    MAX_CLASH_DISTANCE = 35,
    WINDOW_FACTOR = 0.9,
    CLOSE_TARGET_DISTANCE = 5,
    HAUNTER_RANGE = 11,
    HAUNTER_MATCH_RADIUS = 5,
    HAUNTER_LIFETIME = 0.15,
    DASH_MAX_SNAPSHOT_AGE = 0.15,
    DASH_DETECTION_RANGE = 70,
    DASH_MIN_ALIGNMENT = 0.6,
  },
  SIGNAL = {
    BLOCK_LIFETIME = 0.65,
    MERGE_INTERVAL = 0.04,
    SCAN_INTERVAL = 0.05,
    CATALOG_INTERVAL = 0.5,
    STOP_GRACE = 0.05,
  },
  TIMING = {
    SNAPSHOT_MAX_AGE = 0.5,
    PACKET_CACHE_AGE = 0.2,
    HISTORY_MAX_AGE = 0.75,
    PHYSICAL_EXIT_DELAY = 0.12,
    PREDICTION_OBSERVATION_DELAY = 0.24,
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
  state.activationEvidence, state.predictionArmed, state.predictionEvidence = nil, nil, nil
  for _, sensor in pairs(state.sensors or {}) do
    sensor.attempt = nil
  end
end
local function deactivate(state, reason, time)
  if not state.active then return false end
  time = time or now(); state.active, state.phase, state.reason, state.lastGate = false, "idle", reason, reason
  state.prediction, state.anticipatingUntil, state.physicalExitSince = nil, nil, nil; state.sendContinuity = nil
  if reason == "opponent_left_or_died" then clashStatsModule.freeze(state.partner, state) end
  state.predictionArmed = nil; state.partner, state.deathSerial = nil, nil
  lastStopReason, lastStopAt = reason, time; utils.setAutoSpamActive(false)
  utils.recordTransition("AutoSpam", "active", "idle", reason); return true
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
local function localColorTarget(s)
  local report = s and s.targetSignals
  for _, signal in ipairs(report and report.signals or {}) do
    if signal.name == "ball.targetColor" and signal.available and signal.targeted then return true end
  end
  return false
end
local function observedTarget(s)
  local target = s and not s.targetUncertain and targetOf(s)
  if target then return target end
  return localColorTarget(s) and localPlayer.UserId or nil
end
local function lifecycleGate(state, s)
  if not s or not s.ball or not s.ball.Parent then return "snapshot_invalid" end
  if s.ball ~= state.ball or s.teleported or s.resetting or s.ballValid == false or s.valid == false then return "ball_reset" end
  if s.mode == "training" then return "training" end
  if gameInfo.getBallFrozen() == true then return "ball_paused" end
  if s.locked or s.ballCanMove == false then return "ball_reset" end
end
local function sampleGate(state, s, time)
  local gate = lifecycleGate(state, s)
  if gate then return gate end
  local order = sequenceOrder(state, s.syncSequence)
  if order == "old" or order == "invalid" then return "packet_" .. order end
  if s.syncAt ~= nil and (not finite(s.syncAt) or time < s.syncAt or time - s.syncAt > CONFIG.TIMING.SNAPSHOT_MAX_AGE) then return "snapshot_stale" end
  if not observedTarget(s) then return "target_unknown" end
end
local function activationTarget(state, s, time)
  local receipt = state.receipt
  if receipt and time >= receipt.at and time - receipt.at <= CONFIG.ACTIVATION.RETURN + networkLatency() then return receipt.target end
  return observedTarget(s)
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
local function insideSpamWindow(state, s, time)
  if not s or not vector(s.position) or not vector(state.root.Position) then return false end
  if s.syncAt ~= nil and (not finite(s.syncAt) or time < s.syncAt or time - s.syncAt > CONFIG.TIMING.SNAPSHOT_MAX_AGE) then return false end
  local g = geometry(s, CONFIG.ACTIVATION.WINDOW_FACTOR)
  if not g or not finite(g.fullRadius) or g.fullRadius < 0 then return false end
  local delta = s.position - state.root.Position; return delta:Dot(delta) <= g.fullRadius * g.fullRadius
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
  if not packet and not (s.targetSignals and s.targetSignals.known) and not localColorTarget(s) then return end
  local target = observedTarget(s)
  if not target then return end
  local previous, previousReceipt = state.target, state.receipt; local confirmed = not s.targetUncertain and targetOf(s) == target
  if previous == target then return end
  local me = localPlayer.UserId; state.leg = (state.leg or 0) + 1
  local sensor = state.sensors and state.sensors[target]; local attempt = sensor and sensor.attempt
  if
    target ~= me
    and attempt
    and not attempt.used
    and attempt.ball == state.ball
    and time >= attempt.at
    and time - attempt.at <= CONFIG.SIGNAL.MERGE_INTERVAL
  then
    attempt.leg, attempt.target = state.leg, target
  end
  if state.active and not state.partner then
    local partner = target ~= me and target or (previous ~= me and previous or nil)
    if partner and playerIsAlive(partner) then state.partner = partner end
  end
  local distance = vector(s.position) and (s.position - state.root.Position).Magnitude or nil
  state.target, state.receipt =
    target, { target = target, at = time, position = s.position, distance = distance, leg = state.leg, color = localColorTarget(s), confirmed = confirmed }
  state.pending, state.exchange = nil, nil
  if state.lastSwitchAt then state.intervalMs = (time - state.lastSwitchAt) * 1000 end
  state.lastSwitchAt = time
  if previous == me and target ~= me then
    state.outbound = confirmed and previousReceipt and previousReceipt.confirmed and { partner = target, at = time } or nil; state.previousOpponent = target
    state.exchange = { partner = target, at = time }
  elseif target == me and previous and previous ~= me then
    local outbound = state.outbound
    if
      confirmed
      and outbound
      and outbound.partner == previous
      and time >= outbound.at
      and time - outbound.at <= CONFIG.ACTIVATION.RETURN + networkLatency()
    then
      local h = state.confirmedReturns; local count = h and h.partner == previous and time - h.at <= CONFIG.TIMING.HISTORY_MAX_AGE and h.count + 1 or 1
      local returnGeometry = geometry(s, 0.8); state.confirmedReturns = { partner = previous, count = count, at = time }
      state.pending = {
        partner = previous,
        at = time,
        leg = state.leg,
        inWindow = finite(distance) and returnGeometry ~= nil and distance <= returnGeometry.fullRadius,
      }
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
local function autoHardStop(state, s)
  if not utils.isActive() then return "hub_inactive" end
  if utils.getConfigValue("AutoSpam") ~= true then return "disabled" end
  if utils.getWorkspace():GetAttribute("MatchStatus") ~= 6 then return "match_ended" end
  if gameInfo.getBallFrozen() == true then return "ball_paused" end
  if state.active and (not s or not s.ball or not s.ball.Parent or s.ball ~= state.ball or s.teleported or s.resetting) then return "ball_reset" end
  if state.active and state.partner and not nearPartner(state, state.partner, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE) then return "opponent_out_of_range" end
  if not state.character.Parent or not state.root.Parent or not playerIsAlive(localPlayer.UserId) then return "player_died" end
  if state.deathSerial and state.deathSerial ~= matchDeathSerial then return "match_player_died" end
  if state.partner and not playerIsAlive(state.partner) then return "opponent_left_or_died" end
  local target = s and not s.targetUncertain and targetOf(s)
  if state.active and state.partner and target and target ~= localPlayer.UserId and target ~= state.partner then return "target_redirected_far" end
end
local function predictionMargin(state)
  local factor = tonumber(utils.getConfigValue("AutoSpamPredictionMargin")); factor = finite(factor) and math.clamp(factor, 0.5, 2) or 1
  local delay = CONFIG.TIMING.PREDICTION_OBSERVATION_DELAY + networkLatency(); return delay * factor, factor
end
local function liveAttempt(state, partner, time)
  local sensor = state.sensors and state.sensors[partner]; local attempt = sensor and sensor.attempt
  if not attempt or attempt.phase ~= "start" or attempt.ball ~= state.ball or attempt.leg ~= state.leg or time < attempt.at or time > attempt.expiresAt then return nil end
  if time - attempt.at > math.min(0.12 + networkLatency(), 0.25) then return nil end
  local playing = false
  for track in pairs(attempt.tracks) do
    if track.IsPlaying then playing = true; break end
  end
  if playing then attempt.lastPlayingAt = time end
  if not playing and time - (attempt.lastPlayingAt or attempt.at) > CONFIG.SIGNAL.STOP_GRACE + networkLatency() then return nil end
  return attempt
end
local function solveReturn(state, s, time)
  state.gates.prediction = "waiting_opponent_target"; state.predictionEvidence, state.predictionArmed = nil, nil
  local gate = sampleGate(state, s, time)
  if gate then state.gates.prediction = gate; return nil end
  local partner = observedTarget(s)
  if not partner or partner == localPlayer.UserId then return nil end
  local g = geometry(s, 0.3)
  if not g or not vector(s.position) then state.gates.prediction = "prediction_geometry_invalid"; return nil end
  if not nearPartner(state, partner, math.max(13, g.noWindowParryRadius)) then state.gates.prediction = "opponent_out_of_range"; return nil end
  if state.consumedLeg == state.leg then state.gates.prediction = "leg_consumed"; return nil end
  local aimed, score, margin, source = gameInfo.getDeflectTargetPrediction(partner)
  if aimed ~= localPlayer.UserId then state.gates.prediction = "return_not_aimed_at_self"; return nil end
  if
    (source == "camera" and (not finite(score) or score < 0.75 or not finite(margin) or margin < 0.03))
    or (source == "root" and (not finite(score) or score < 0.9 or not finite(margin) or margin < 0.15))
  then
    state.gates.prediction = "return_aim_uncertain"; return nil
  end
  local other, motion = gameInfo.getPlayerMotion(partner); local own = state.root.Position
  if not vector(other) or not vector(s.velocity) then return nil end
  motion = vector(motion) and motion or Vector3.zero; local position, velocity, speed = flight(state, s, time)
  if not vector(position) or not vector(velocity) or not finite(speed) or speed <= 0 then return nil end
  local otherRadius = deflectGeometry.getPlayerRawRadius(partner, speed, false); local ownRadius = deflectGeometry.getPlayerRawRadius(localPlayer.UserId, speed, false)
  local apFactor = tonumber(utils.getConfigValue("AutoParryWindowFactor")); apFactor = finite(apFactor) and math.clamp(apFactor, 0, 1) or 0.4
  local opponentGeometry = deflectGeometry.getAutoParryGeometry(speed, apFactor, frameLead(state), 0, partner)
  local ownGeometry = deflectGeometry.getAutoParryGeometry(speed, apFactor, frameLead(state), networkLatency() * 2, localPlayer.UserId)
  if not finite(otherRadius) or not finite(ownRadius) or not opponentGeometry or not ownGeometry then return nil end
  local delay, factor = predictionMargin(state); local gap = (other - own).Magnitude
  local dangerRadius = deflectGeometry.projectRadius(otherRadius, speed, math.min(delay, g.effectiveWindow), 1, networkLatency())
  local killRadius = deflectGeometry.getKillRadius(deflectGeometry.getDefensePhysics())
  if not finite(dangerRadius) or not finite(killRadius) then return nil end
  if gap > dangerRadius or math.max(0, gap - killRadius) / speed > delay then state.gates.prediction = "pair_has_reaction_time"; return nil end
  local opponentTrigger = otherRadius + opponentGeometry.fullRadius - opponentGeometry.noWindowParryRadius
  local contactLead = math.min(opponentGeometry.effectiveWindow, 0.08 + networkLatency(), 0.16)
  local danger = deflectGeometry.getDanger(position, velocity, other, speed, otherRadius, contactLead, motion)
  if (position - other).Magnitude > opponentTrigger or not danger or not danger.ready or not finite(danger.entryTime) then state.gates.prediction = "opponent_not_ready"; return nil end
  if (position - other).Magnitude > 0.1 and (not finite(danger.closingSpeed) or danger.closingSpeed <= 0) then state.gates.prediction = "ball_leaving_opponent"; return nil end
  local arrival = math.max(0, danger.entryTime); local contact = position + velocity * arrival
  local ownMotion = vector(state.root.AssemblyLinearVelocity) and state.root.AssemblyLinearVelocity or Vector3.zero; local futureOwn = own + ownMotion * arrival
  local delta = futureOwn - contact
  if delta.Magnitude <= 0.001 then state.gates.prediction = "return_geometry_invalid"; return nil end
  local returnVelocity = delta / delta.Magnitude * speed; local ownTrigger = ownRadius + ownGeometry.fullRadius - ownGeometry.noWindowParryRadius
  local returnTrigger = ownRadius; local returnDanger = deflectGeometry.getDanger(contact, returnVelocity, futureOwn, speed, returnTrigger, delay, ownMotion)
  local lethalReturnTime = math.max(0, delta.Magnitude - killRadius) / speed
  if not returnDanger or not returnDanger.ready or arrival + lethalReturnTime > delay then state.gates.prediction = "return_has_reaction_time"; return nil end
  local returnTime = math.max(0, delta.Magnitude - ownRadius) / speed
  local evidence = {
    partner = partner,
    ball = s.ball,
    leg = state.leg,
    at = time,
    contactIn = arrival,
    returnIn = returnTime,
    lethalReturnIn = lethalReturnTime,
    contactLead = contactLead,
    reactionMargin = delay,
    marginFactor = factor,
    opponentTriggerRadius = opponentTrigger,
    pairDangerRadius = dangerRadius,
    returnTriggerRadius = returnTrigger,
    deadline = time + arrival + returnTime + delay,
    aimSource = source,
    aimScore = score,
    aimMargin = margin,
    danger = danger,
    returnDanger = returnDanger,
  }

  state.predictionEvidence, state.predictionArmed = evidence, evidence; local attempt = liveAttempt(state, partner, time)
  if not attempt then state.gates.prediction = "armed_waiting_blockstart"; return nil end
  if attempt.used then state.gates.prediction = "attempt_consumed"; return nil end
  if time + arrival > math.min(attempt.expiresAt, attempt.at + math.min(opponentGeometry.deflectWindow, 0.12 + networkLatency())) then
    state.gates.prediction = "attempt_expires_before_contact"; return nil
  end
  evidence.source, evidence.animationPhase = attempt.source, "start"; state.gates.prediction = "ready"
  return { reason = "extreme_return_prediction", partner = partner, prediction = evidence, attempt = attempt }
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
    and state.pending
    and not state.pending.used
    and state.pending.leg == state.leg
    and state.pending.inWindow
    and time >= state.pending.at
    and time - state.pending.at <= CONFIG.ACTIVATION.RETURN + networkLatency()
  then
    state.gates.close = "ready"; return { reason = "close_target", partner = state.pending.partner, pending = state.pending, closeReceipt = receipt }
  end
  if utils.getConfigValue("AutoSpamClashPrediction") ~= false then
    local candidate = solveReturn(state, s, time)
    if candidate then return candidate end
  else
    state.predictionArmed, state.predictionEvidence = nil, nil; state.gates.prediction = "disabled"
  end
  local pending = state.pending; local returnGeometry = geometry(s, 0.8)
  if not pending then
    state.gates.returnTarget = "return_no_round_trip"
  elseif pending.used or pending.leg ~= state.leg then
    state.gates.returnTarget = "return_consumed"
  elseif time < pending.at or time - pending.at > CONFIG.ACTIVATION.RETURN + networkLatency() then
    state.gates.returnTarget = "return_expired"
  elseif not pending.inWindow or not returnGeometry or not vector(s.position) or (s.position - state.root.Position).Magnitude > returnGeometry.fullRadius then
    state.gates.returnTarget = "return_outside_window"
  elseif target ~= localPlayer.UserId then
    state.gates.returnTarget = "return_not_self"
  else
    state.gates.returnTarget = "ready"; return { reason = "return_target", partner = pending.partner, pending = pending, closeReceipt = receipt }
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
  state.activatedAt, state.deathSerial, state.lastGate = time, matchDeathSerial, candidate.reason; state.physicalExitSince = nil
  state.predictionArmed = nil; state.prediction = candidate.prediction
  state.anticipatingUntil = candidate.prediction and candidate.prediction.deadline
  if candidate.prediction then state.consumedLeg = state.leg end
  if candidate.attempt then candidate.attempt.used = true end
  if candidate.pending then candidate.pending.used = true end
  if candidate.closeReceipt then candidate.closeReceipt.used = true end
  state.activationEvidence = { at = time, ball = s.ball, partner = candidate.partner, target = activationTarget(state, s, time) }; state.cooldownSince = nil
  local cd = cooldownInfo.getDeflectCooldownState(); state.cooldownEpisode = cd and cd.episode
  lastActivationReason, lastActivationAt = candidate.reason, time; clashStatsModule.begin(candidate.partner, time)
  utils.recordTransition("AutoSpam", "idle", "active", candidate.reason); utils.setAutoSpamActive(true)
end
local function autoStop(state, s, time)
  local reason = autoHardStop(state, s)
  if reason then return reason end
  if not insideSpamWindow(state, s, time) then return "outside_spam_window" end
  local speed = snapshotSpeed(s) or 0; local low, high = gameInfo.getBallSpeedLimits()
  local progress = finite(low) and finite(high) and high > low and math.clamp((speed - low) / (high - low), 0, 1) or 0; local other = playerPosition(state.partner)
  local near = other and (other - state.root.Position).Magnitude <= 10 + 6 * progress; local limit = 0.225 - 0.125 * progress + networkLatency() + (near and 0.12 or 0)
  state.cooldownLimit = limit; local cd = cooldownInfo.getDeflectCooldownState()
  state.cooldown = cd
  if not cd or cd.source == "unknown" or cd.blocking ~= true or cd.predictedReset == true then
    state.cooldownSince, state.cooldownEpisode = nil, nil
  else
    if finite(cd.lastParriedAt) and cd.lastParriedAt ~= state.cooldownParriedAt then state.cooldownParriedAt, state.cooldownSince = cd.lastParriedAt, time end
    if not state.cooldownSince or (cd.episode ~= nil and state.cooldownEpisode ~= cd.episode) then
      state.cooldownSince = finite(cd.blockingSince) and cd.blockingSince <= time and cd.blockingSince or time; state.cooldownEpisode = cd.episode
    end
    if time - state.cooldownSince >= limit then return "cooldown" end
  end
  if lifecycleGate(state, s) == "ball_reset" then state.physicalExitSince = nil; return nil end
  local target = activationTarget(state, s, time)
  if state.prediction then
    if target == localPlayer.UserId then
      state.phase, state.prediction, state.anticipatingUntil = "clashing", nil, nil
    elseif utils.getConfigValue("AutoSpamClashPrediction") == false then
      return "prediction_disabled"
    elseif time >= state.prediction.deadline then
      return "anticipation_expired"
    else
      local aim = gameInfo.getDeflectTargetPrediction(state.partner)
      if aim and aim ~= localPlayer.UserId then return "prediction_redirected" end
    end
  end
  if not other or not s or not vector(s.position) or not vector(s.velocity) then return nil end
  local g = geometry(s, 1); local range = g and g.fullRadius or 20
  local ownDelta, otherDelta = state.root.Position - s.position, other - s.position
  if ownDelta.Magnitude > range and otherDelta.Magnitude > range and s.velocity:Dot(ownDelta) < 0 and s.velocity:Dot(otherDelta) < 0 then
    state.physicalExitSince = state.physicalExitSince or time
    if time - state.physicalExitSince >= CONFIG.TIMING.PHYSICAL_EXIT_DELAY then return "ball_left_exchange" end
  else
    state.physicalExitSince = nil
  end
end
local function deactivationGate(state, s, time) return autoStop(state, s, time) end
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
local function nativeActivation(state, s, time)
  if not insideSpamWindow(state, s, time) then return nil end
  local context = gameInfo.getNativeClashContext(); local partner = context and context.partnerId
  if not partner or not nearPartner(state, partner, CONFIG.ACTIVATION.MAX_CLASH_DISTANCE) then return nil end
  local cd = cooldownInfo.getDeflectCooldownState()
  if state.cooldownSince and cd and cd.blocking == true and cd.predictedReset ~= true and time - state.cooldownSince >= (state.cooldownLimit or math.huge) then return nil end
  return { partner = partner, reason = "native_clash" }
end
evaluate = function(state, s, time, packet)
  if current ~= state then return end
  state.gates = {}
  if not state.active then state.predictionArmed, state.predictionEvidence = nil, nil end
  local stop = autoHardStop(state, s)
  if stop then
    deactivate(state, stop, time); state.lastGate = stop
    clearEvidence(state); return
  end
  if s and s.ball ~= state.ball then state.ball, state.sequence, state.packetSnapshot, state.packetAt = s.ball, nil, nil, nil; clearEvidence(state) end
  local order = sequenceOrder(state, s and s.syncSequence)
  if order == "old" or order == "invalid" then packet = false end
  if order == "new" then state.sequence = s.syncSequence end
  if packet then state.packetSnapshot, state.packetAt = table.clone(s), time end
  local gate = lifecycleGate(state, s)
  if gate == "ball_reset" then clearEvidence(state) end
  if s and gate ~= "ball_reset" and gate ~= "training" and gate ~= "ball_paused" then observeTarget(state, s, time, packet) end
  if state.active then
    stop = deactivationGate(state, s, time)
    if stop then
      deactivate(state, stop, time)
      if stop == "ball_left_exchange" then clearEvidence(state) end
      return
    end
    rememberContinuity(state, time)
    if gate == "ball_paused" or gate == "training" or gate == "ball_not_moving" then
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
  local candidate = nativeActivation(state, s, time)
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
  if phase ~= "start" then return end
  if seeded and sensor.tracks[track] then return end
  local time = now(); local playback, rate = track.TimePosition, track.Speed
  if not finite(playback) or playback < 0 or not finite(rate) or rate <= 0 then return end
  local age = playback / rate; local lifetime = CONFIG.SIGNAL.BLOCK_LIFETIME
  sensor.tracks[track] = true
  if age >= lifetime then return end
  local attempt = sensor.attempt
  if not attempt or attempt.ball ~= state.ball or time > attempt.expiresAt or time - attempt.observedAt > CONFIG.SIGNAL.MERGE_INTERVAL then
    attempt = {
      at = time - age,
      observedAt = time,
      expiresAt = time - age + lifetime,
      ball = state.ball,
      leg = state.leg,
      target = observedTarget(gameInfo.getSnapshotAt(time)),
      source = seeded and "animation_scan" or "animation_event",
      phase = "start",
      tracks = {},
    }

    sensor.attempt = attempt
  end
  attempt.tracks[track], attempt.lastPlayingAt = true, time
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
    animationCatalog = {},
  }

  current = state; local initial = gameInfo.getSnapshotAt(now())
  state.ball = initial and initial.ball
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
  local function refreshNative()
    if current == state then evaluate(state, gameInfo.getSnapshotAt(now()), now(), false) end
  end
  if type(utils.observeConfig) == "function" then
    local c = utils.observeConfig(refreshNative); state.connections[c] = true
    utils.trackCharacter(c)
  end
  local world = utils.getWorkspace()
  for _, name in ipairs({ "LastParryAt", "LastParryBy", "LastParryTarget", "ClashHits" }) do
    listen(state, world:GetAttributeChangedSignal(name), refreshNative)
  end
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
    if vector(state.lastRootPosition) and (root.Position - state.lastRootPosition).Magnitude > CONFIG.ACTIVATION.HAUNTER_RANGE then
      state.recentRootPosition, state.recentRootAt = state.lastRootPosition, time
    end
    evaluate(state, selectSnapshot(state, gameInfo.getSnapshotAt(time), time), time, false)
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
  refreshNative(); return true
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
  local stop = deactivationGate(state, s, time)
  if stop then
    deactivate(state, stop, time); state.lastSendBlockReason, state.lastSendBlockAt = stop, time
    return false
  end
  local gate = lifecycleGate(state, s)
  if gate then state.lastSendBlockReason, state.lastSendBlockAt = gate, time; return false end
  return true
end
function AutoSpam.hasClashPrediction() return false end
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
    engineVersion = 5,
    reason = state and state.reason,
    windowFactor = 1,
    gates = state and table.clone(state.gates) or {},
    targetId = state and state.target or -1,
    clashPartnerId = state and state.partner or -1,
    targetUncertain = s and s.targetUncertain == true or false,
    snapshotAge = s and finite(s.syncAt) and time - s.syncAt or nil,
    ballDistance = s and state and vector(s.position) and (s.position - state.root.Position).Magnitude or nil,
    anticipationRemaining = state and state.anticipatingUntil and math.max(0, state.anticipatingUntil - time) or 0,
    confirmedReturns = state and state.confirmedReturns and state.confirmedReturns.count or 0,
    prediction = state and state.prediction and table.clone(state.prediction) or nil,
    predictionEvidence = state and state.predictionEvidence and table.clone(state.predictionEvidence) or nil,
    predictionArmed = state and state.predictionArmed ~= nil or false,
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
      "getAutoParryGeometry",
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
      "getNativeClashContext",
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
  },
  onBallSync = true,
  bindCharacter = true,
}

return AutoSpam
