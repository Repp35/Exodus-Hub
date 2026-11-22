-- [[ auto spam ]]

-- module
local AutoSpam = {}
local utils
local profiler
local gameInfo
local clashStatsModule
local cooldownInfo
local deflectGeometry
local players
local runService
local localPlayer
local current
local generation = 0
local matchDeathSerial = 0
local lastActivationReason
local lastActivationAt
local lastStopReason
local lastStopAt
local evaluate

-- configuration
local CONFIG = {
  ACTIVATION = {
    RETURN = 0.6,
    WINDOW_FACTOR = 0.9,
    REACTIVATION_COOLDOWN = 0.15,
    CLOSE_TARGET_DISTANCE = 5,
  },
  TIMING = {
    SNAPSHOT_MAX_AGE = 0.5,
    PACKET_CACHE_AGE = 0.2,
  },
}

-- helpers
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
  local _, _, humanoid = gameInfo.getPlayerParts(id); return humanoid ~= nil and finite(humanoid.Health) and humanoid.Health > 0
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
  state.target, state.outbound, state.returnEvidence, state.receipt, state.exchange = nil, nil, nil, nil, nil; state.confirmedReturns, state.exchangeHistory, state.lastPairExchangeAt = nil, nil, nil
  state.packetSnapshot, state.packetAt, state.receivedSequence = nil, nil, nil; state.leg = (state.leg or 0) + 1
end
local function deactivate(state, reason, time)
  if not state.active then return false end
  time = time or now(); state.active, state.phase, state.reason, state.lastGate = false, "idle", reason, reason
  if reason == "opponent_left_or_died" then clashStatsModule.freeze(state.partner, state) end
  state.partner, state.deathSerial = nil, nil; state.cooldownSince, state.cooldownInitialRemaining = nil, nil
  state.reactivateAt = time + CONFIG.ACTIVATION.REACTIVATION_COOLDOWN; lastStopReason, lastStopAt = reason, time
  utils.setAutoSpamActive(false); utils.recordTransition("AutoSpam", "active", "idle", reason)
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
local function lifecycleGate(state, s)
  if not s or not s.ball or not s.ball.Parent then return "snapshot_invalid" end
  if s.ball ~= state.ball or s.teleported or s.resetting or s.ballValid == false or s.valid == false then return "ball_reset" end
  if s.mode == "training" then return "training" end
  if gameInfo.getBallFrozen() == true then return "ball_paused" end
  if s.locked or s.ballCanMove == false then return "ball_reset" end
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
local function geometry(state, s, factor)
  local speed = snapshotSpeed(s)
  if not speed or speed <= 0 then return nil end
  local key = factor or 1; local memo = state.evaluation
  if memo and memo[key] then return memo[key], speed end
  local g = deflectGeometry.getDeflectGeometry(speed, "game", key, false, networkLatency())
  if not g or not finite(g.effectiveWindow) or not finite(g.noWindowParryRadius) then return nil end
  local low, high = gameInfo.getBallSpeedLimits(); local result = deflectGeometry.withSpeedWindowBonus(g, speed, low, high, key)
  if memo then memo[key] = result end
  return result, speed
end
local function opponentDistanceLimit(state, s, partner)
  local memo = state.evaluation
  if memo and memo.distanceLimit then return memo.distanceLimit end
  local speed = snapshotSpeed(s)
  if not speed then return 0 end
  local factor = utils.getConfigValue("AutoParryWindowFactor"); factor = finite(factor) and math.clamp(factor, 0, 1) or 0.3
  local own = deflectGeometry.getAutoParryGeometry(speed, factor, frameLead(state), gameInfo.getAveragePing()); local radius = own and own.fullRadius
  local result = finite(radius) and radius >= 0 and math.max(10, radius) or 0
  if memo then memo.distanceLimit = result end
  return result
end
local function insideSpamWindow(state, s, time, factor)
  if not s or not vector(s.position) or not vector(state.root.Position) then return false end
  if s.syncAt ~= nil and (not finite(s.syncAt) or time < s.syncAt or time - s.syncAt > CONFIG.TIMING.SNAPSHOT_MAX_AGE) then return false end
  local windowFactor = factor or CONFIG.ACTIVATION.WINDOW_FACTOR; local g = geometry(state, s, windowFactor)
  if not g or not finite(g.fullRadius) or g.fullRadius < 0 then return false end
  local delta = s.position - state.root.Position; return delta:Dot(delta) <= g.fullRadius * g.fullRadius
end
local function predictedRecipient(s)
  if not s or not vector(s.position) or not vector(s.velocity) then return nil end
  local speed = snapshotSpeed(s)
  if not speed or speed <= 0 then return nil end
  local best, earliest
  profiler.count("combat.recipient_scans")
  for _, player in ipairs(gameInfo.getPlayers()) do
    profiler.count("combat.recipient_players")
    if playerIsAlive(player.UserId) and player:GetAttribute("Playing") ~= false then
      local position, motion = gameInfo.getPlayerMotion(player.UserId); local radius = deflectGeometry.getPlayerRawRadius(player.UserId, speed, false)
      if vector(position) and finite(radius) and radius > 0 then
        local delta = position - s.position; local velocity = s.velocity - (vector(motion) and motion or Vector3.zero)
        local a, b = velocity:Dot(velocity), delta:Dot(velocity); local c = delta:Dot(delta) - radius * radius
        if c <= 0 and b >= 0 then return player.UserId, 0 end
        if a > 0 and b > 0 then
          local discriminant = b * b - a * c
          if discriminant >= 0 then
            local entry = math.max(0, (b - math.sqrt(discriminant)) / a)
            if entry <= 2.5 and (not earliest or entry < earliest) then best, earliest = player.UserId, entry end
          end
        end
      end
    end
  end
  return best, earliest
end
local function calculateRecipientRisk(state, s)
  local authoritativeTarget = s and userId(s.exchangeTargetId)
  if
    authoritativeTarget
    and authoritativeTarget ~= localPlayer.UserId
    and not nearPartner(state, authoritativeTarget, opponentDistanceLimit(state, s, authoritativeTarget))
  then
    return "confirmed_far_target", authoritativeTarget
  end
  local recipient, arrival = predictedRecipient(s)
  if recipient == localPlayer.UserId then return nil, recipient, arrival end
  return nil, recipient, arrival
end
local function recipientRisk(state, s)
  local memo = state.evaluation
  if not memo then return calculateRecipientRisk(state, s) end
  if not memo.riskChecked then memo.risk, memo.recipient, memo.arrival = calculateRecipientRisk(state, s); memo.riskChecked = true end
  return memo.risk, memo.recipient, memo.arrival
end
local function observeTarget(state, s, time, event)
  if not event and not (s.targetSignals and s.targetSignals.known) then return end
  local target = s and not s.targetUncertain and targetOf(s)
  if not target or state.target == target then return end
  local previous = state.target; local history = state.foreignHistory
  if
    previous
    and previous ~= localPlayer.UserId
    and target ~= localPlayer.UserId
    and history
    and history.from == target
    and history.to == previous
    and history.ball == s.ball
    and time >= history.at
  then
    local speed = snapshotSpeed(s); local g = speed and deflectGeometry.getAutoParryGeometry(speed, 1, frameLead(state), gameInfo.getAveragePing(), target)
    local budget = g and g.effectiveWindow and g.effectiveWindow + networkLatency() + frameLead(state) or 0
    if time - history.at <= math.min(CONFIG.ACTIVATION.RETURN + networkLatency(), budget) then state.foreignClash = { ball = s.ball, a = target, b = previous, at = time } end
  elseif target == localPlayer.UserId then
    state.foreignClash = nil
  end
  state.foreignHistory = previous and { from = previous, to = target, at = time, ball = s.ball } or nil; state.leg = state.leg + 1
  local becameTarget = target == localPlayer.UserId and previous ~= localPlayer.UserId and (previous ~= nil or event == true)
  local ballPosition = event and vector(s.realPosition) and s.realPosition or s.position
  local distance = becameTarget and vector(ballPosition) and vector(state.root.Position) and (ballPosition - state.root.Position).Magnitude or nil; state.target = target
  state.receipt = {
    from = previous,
    target = target,
    at = time,
    leg = state.leg,
    ball = s.ball,
    closeAtSwitch = becameTarget and finite(distance) and distance <= CONFIG.ACTIVATION.CLOSE_TARGET_DISTANCE or false,
    distanceAtSwitch = distance,
  }
  if state.lastSwitchAt and time >= state.lastSwitchAt then state.intervalMs = (time - state.lastSwitchAt) * 1000 end
  state.lastSwitchAt = time; local me = localPlayer.UserId
  if previous and (previous == me or target == me) then state.exchange = { partner = previous == me and target or previous, at = time, ball = s.ball } else state.exchange = nil end
  if previous == me then
    state.outbound = { partner = target, at = time, ball = s.ball }; state.returnEvidence = nil
  elseif target == me then
    local outbound = state.outbound
    if
      outbound
      and outbound.partner == previous
      and outbound.ball == s.ball
      and time >= outbound.at
      and time - outbound.at <= CONFIG.ACTIVATION.RETURN + networkLatency()
    then
      local h = state.confirmedReturns; state.confirmedReturns = { partner = previous, at = time, count = h and h.partner == previous and h.count + 1 or 1 }
      state.returnEvidence = { partner = previous, at = time, ball = s.ball, leg = state.leg, interval = time - outbound.at }; state.lastPairExchangeAt = time
    end
    state.outbound = nil
  else
    state.outbound, state.returnEvidence, state.confirmedReturns = nil, nil, nil
  end
  local h = state.exchangeHistory or {}; state.exchangeHistory = h
  if target == me and previous then
    if h.partner == previous and h.inboundAt then h.cycle = time - h.inboundAt end
    h.partner, h.inboundAt = previous, time
  end
end
local function externalGate(state, s, time)
  local clash = state.foreignClash
  if
    clash
    and s
    and clash.ball == s.ball
    and time >= clash.at
    and time - clash.at <= CONFIG.ACTIVATION.RETURN + networkLatency()
    and targetOf(s) ~= localPlayer.UserId
  then
    return "other_players_clashing"
  end
  return recipientRisk(state, s)
end
local function distantTargetGate(state, s)
  if not state.active or not s then return nil end
  local target = userId(s.exchangeTargetId)
  if not target and not s.targetUncertain then target = userId(s.targetId) end
  if not target or target == localPlayer.UserId or target == state.partner then return nil end
  local targetPosition = playerPosition(target)
  if not vector(targetPosition) then return nil end
  local g = geometry(state, s, 1)
  if not g or not finite(g.fullRadius) or g.fullRadius <= 0 then return nil end
  if (targetPosition - state.root.Position).Magnitude > g.fullRadius then return "distant_target" end
  return nil
end
local function autoHardStop(state, s)
  if not utils.isActive() then return "hub_inactive" end
  if utils.getConfigValue("AutoSpam") ~= true then return "disabled" end
  if utils.getWorkspace():GetAttribute("MatchStatus") ~= 6 then return "match_ended" end
  if gameInfo.getBallFrozen() == true then return "ball_paused" end
  if not state.character.Parent or not state.root.Parent or not playerIsAlive(localPlayer.UserId) then return "player_died" end
  if state.deathSerial and state.deathSerial ~= matchDeathSerial then return "match_player_died" end
  if state.partner and not playerIsAlive(state.partner) then return "opponent_left_or_died" end
  return distantTargetGate(state, s)
end
local function activate(state, candidate, s, time)
  state.active, state.phase, state.reason, state.partner = true, "clashing", candidate.reason, candidate.partner
  state.activatedAt, state.deathSerial, state.lastGate = time, matchDeathSerial, candidate.reason; state.cooldownSince, state.cooldownInitialRemaining, state.cooldownEpisode = nil, nil, nil
  lastActivationReason, lastActivationAt = candidate.reason, time; clashStatsModule.begin(candidate.partner, time)
  utils.recordTransition("AutoSpam", "idle", "active", candidate.reason); utils.setAutoSpamActive(true)
end
local function autoStop(state, s, time)
  local reason = autoHardStop(state, s)
  if reason then return reason end
  local speed = snapshotSpeed(s) or 0; local low, high = gameInfo.getBallSpeedLimits()
  local progress = finite(low) and finite(high) and high > low and math.clamp((speed - low) / (high - low), 0, 1) or 0; local other = playerPosition(state.partner)
  local near = other and (other - state.root.Position).Magnitude <= 10 + 6 * progress; local limit = 0.225 - 0.125 * progress + networkLatency() + (near and 0.12 or 0)
  local cd = cooldownInfo.getDeflectCooldownState(); state.cooldown = cd
  if cd and cd.source == "local" and cd.blocking == true and cd.miss == true then return "miss_confirmed" end
  local localBlocked = cd and ((cd.source == "local" and finite(cd.localRemaining) and cd.localRemaining > 0) or (cd.source == nil and cd.blocking == true))
  if not localBlocked then
    state.cooldownSince, state.cooldownInitialRemaining = nil, nil; state.cooldownLimit = limit
  else
    local began = finite(cd.blockingSince) and cd.blockingSince <= time and cd.blockingSince or time; state.cooldownSince = math.min(state.cooldownSince or began, began)
    if not state.cooldownInitialRemaining and finite(cd.localRemaining) and cd.localRemaining > 0 then state.cooldownInitialRemaining = cd.localRemaining end
    if finite(state.cooldownInitialRemaining) then limit = math.min(limit, math.max(0.08, state.cooldownInitialRemaining * 0.8)) end
    state.cooldownLimit = limit
    if time - state.cooldownSince >= limit then return "cooldown" end
  end
end
local function deactivationGate(state, s, time) return autoStop(state, s, time) end
local function observeStats(state, s, time, packet)
  if not s or not gameInfo.isSnapshotValid(s) then return end
  local stats = clashStatsModule.get()
  if stats and stats.frozen and not state.active then clashStatsModule.waitForNextClash() end
  clashStatsModule.observe(state, s, time, packet == true)
end
local function fastReturnActivation(state, s, time)
  if not s then state.gates.fastReturn = "snapshot_unavailable"; return nil end
  local evidence = state.returnEvidence
  if evidence then
    if evidence.ball ~= s.ball or evidence.leg ~= state.leg or time < evidence.at or time - evidence.at > CONFIG.ACTIVATION.RETURN + networkLatency() then
      state.returnEvidence = nil; state.gates.fastReturn = "return_expired"
    elseif targetOf(s) ~= localPlayer.UserId then
      state.gates.fastReturn = "return_not_self"
    elseif not nearPartner(state, evidence.partner, opponentDistanceLimit(state, s, evidence.partner)) then
      state.gates.fastReturn = "partner_unavailable"
    elseif not insideSpamWindow(state, s, time, 0.6) then
      state.gates.fastReturn = "return_outside_window"
    else
      local g = geometry(state, s, 1); local budget = g and g.effectiveWindow + networkLatency() + frameLead(state) or 0
      if evidence.interval <= budget then state.gates.fastReturn = "ready"; return { partner = evidence.partner, reason = "fast_return" } end
      state.gates.fastReturn = "return_has_reaction_time"
    end
  else
    state.gates.fastReturn = "no_return_evidence"
  end
  return nil
end
local function closeTargetActivation(state, s, time)
  local receipt = state.receipt
  if not s or not receipt or receipt.ball ~= s.ball or receipt.leg ~= state.leg or receipt.target ~= localPlayer.UserId then state.gates.closeTarget = "no_target_switch"; return nil end
  if not receipt.closeAtSwitch then state.gates.closeTarget = "switch_outside_5_studs"; return nil end
  if targetOf(s) ~= localPlayer.UserId then state.gates.closeTarget = "target_changed"; return nil end
  state.gates.closeTarget = "ready"; return { partner = receipt.from, reason = "close_target" }
end
local function chooseActivation(state, s, time)
  local closeTarget = closeTargetActivation(state, s, time); local fastReturn = fastReturnActivation(state, s, time)
  return closeTarget or fastReturn
end
local function evaluateCore(state, s, time, packet)
  if current ~= state then return end
  table.clear(state.gates)
  if s and s.ball ~= state.ball then state.ball, state.sequence, state.packetSnapshot, state.packetAt = s.ball, nil, nil, nil; clearEvidence(state) end
  local order = sequenceOrder(state, s and s.syncSequence)
  if order == "old" or order == "invalid" then return end
  if order == "new" then state.sequence = s.syncSequence end
  if packet and s then state.packetSnapshot, state.packetAt = table.clone(s), time end
  if s then observeTarget(state, s, time, packet) end
  if state.active then
    local stop = deactivationGate(state, s, time)
    if stop then deactivate(state, stop, time); return end
    local gate = lifecycleGate(state, s)
    if gate then state.lastGate, state.gates.common = gate, gate; return end
    state.lastGate, state.gates.common = "active", nil; observeStats(state, s, time, packet)
    return
  end
  local candidate = chooseActivation(state, s, time)
  if candidate then
    if time >= (state.reactivateAt or 0) then activate(state, candidate, s, time) else state.lastGate = "reactivation_cooldown" end
  else
    state.lastGate = state.gates.closeTarget == "ready" and state.gates.closeTarget or state.gates.fastReturn
  end
  observeStats(state, s, time, packet)
end
evaluate = function(state, s, time, packet)
  local previous = state.evaluation; local memo = not previous and state.scratch or {}
  if not memo then memo = {}; state.scratch = memo end
  table.clear(memo); state.evaluation = memo
  local ok, message = pcall(evaluateCore, state, s, time, packet); state.evaluation = previous
  if not ok then error(message, 0) end
end
local function watchPlayer(state, player)
  if state.sensors[player.UserId] then return end
  local sensor = { player = player, characterConnections = {}, playerConnections = {}, lives = player:GetAttribute("Lives") }
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
    disconnectPool(state, sensor.characterConnections); sensor.character, sensor.humanoid, sensor.reported = character, nil, false
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
  if type(deps) ~= "table" or not deps.Utils or not deps.GameInfo or not deps.ClashStats or not deps.Cooldown or not deps.DeflectGeometry then return false, "dependências ausentes" end
  if current then detach("setup") end
  profiler = deps.Profiler; utils, gameInfo, clashStatsModule, cooldownInfo, deflectGeometry = deps.Utils, deps.GameInfo, deps.ClashStats, deps.Cooldown, deps.DeflectGeometry
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
  }

  current = state; local initial = gameInfo.getSnapshotAt(now())
  state.ball = initial and initial.ball
  for _, player in ipairs(gameInfo.getPlayers()) do
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
  listen(state, character.AncestryChanged, function(_, parent)
    if not parent and current == state then detach("character_removed") end
  end)
  AutoSpam.step(); return true
end
function AutoSpam.step(dt)
  local state = current
  if not state then return end
  if finite(dt) and dt > 0 then state.frameInterval = dt end
  local time = now(); evaluate(state, selectSnapshot(state, gameInfo.getSnapshotAt(time), time), time, false)
end
function AutoSpam.detachCharacter() detach("detach") end
function AutoSpam.teardown()
  detach("teardown"); utils, gameInfo, clashStatsModule, cooldownInfo, deflectGeometry = nil, nil, nil, nil, nil
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
    if order == "old" or order == "invalid" or (order == "same" and state.receivedSequence == incoming and data.Teleported ~= true) then return end
    state.receivedSequence = incoming; s = table.clone(s)
    s.syncSequence, s.syncAt = incoming, time
    if data.TargetPlayerID ~= nil then
      if not userId(data.TargetPlayerID) then state.target, state.outbound, state.returnEvidence, state.exchange = nil, nil, nil, nil; state.leg = state.leg + 1 end
      s.exchangeTargetId, s.targetId, s.targetUncertain = data.TargetPlayerID, data.TargetPlayerID, not userId(data.TargetPlayerID); s.targeted = data.TargetPlayerID == localPlayer.UserId
    end
    if data.Speed ~= nil then s.syncSpeed = data.Speed end
    if data.RealPosition ~= nil then s.realPosition = data.RealPosition end
    if vector(data.ForcedDirection) then s.syncDirection = data.ForcedDirection end
    s.teleported = data.Teleported == true
    if type(data.Locked) == "boolean" then s.locked = data.Locked end
    if data.ServerTime ~= nil then s.serverTime = data.ServerTime end
  end
  if data.Source == "target" and data.TargetPlayerID ~= nil and not userId(data.TargetPlayerID) then
    state.target, state.outbound, state.returnEvidence, state.exchange = nil, nil, nil, nil; state.leg = state.leg + 1
  end
  local targetEvent = data.Source == "target" and userId(data.TargetPlayerID) or nil
  if targetEvent then
    s = table.clone(s); s.syncSequence = state.sequence or s.syncSequence
    s.targetId, s.exchangeTargetId = targetEvent, targetEvent; s.targeted, s.targetUncertain = targetEvent == localPlayer.UserId, false
  end
  evaluate(state, s, time, received or targetEvent ~= nil)
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
  local closeSend = state.reason == "close_target" and s and targetOf(s) == localPlayer.UserId
  if not closeSend and not insideSpamWindow(state, s, time) then state.lastSendBlockReason, state.lastSendBlockAt = "outside_spam_window", time; return false end
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
  local s = state and gameInfo.getSnapshotAt(time)
  return {
    active = state ~= nil and state.active,
    phase = state and state.phase or "detached",
    engineVersion = 6,
    reason = state and state.reason,
    windowFactor = CONFIG.ACTIVATION.WINDOW_FACTOR,
    gates = state and table.clone(state.gates) or {},
    targetId = state and state.target or -1,
    clashPartnerId = state and state.partner or -1,
    targetUncertain = s and s.targetUncertain == true or false,
    snapshotAge = s and finite(s.syncAt) and time - s.syncAt or nil,
    ballDistance = s and state and vector(s.position) and (s.position - state.root.Position).Magnitude or nil,
    confirmedReturns = state and state.confirmedReturns and state.confirmedReturns.count or 0,
    lastActivationReason = lastActivationReason,
    lastActivationAt = lastActivationAt,
    lastStopReason = lastStopReason,
    lastStopAt = lastStopAt,
    lastSendBlockReason = state and state.lastSendBlockReason,
    lastSendBlockAt = state and state.lastSendBlockAt,
    cooldownLimit = state and state.cooldownLimit,
    cooldownElapsed = state and state.cooldownSince and time - state.cooldownSince or nil,
    clashStats = clashStatsModule and clashStatsModule.getStatus() or nil,
  }
end

-- contract
AutoSpam.__contract = {
  requires = {
    Profiler = "profiler",
    DeflectGeometry = "deflectgeometry",
    Utils = "utils",
    GameInfo = "gameinfo",
    ClashStats = "clashstats",
    Cooldown = "cooldown",
  },
  requiresMethods = {
    Profiler = { "count" },
    DeflectGeometry = {
      "getAutoParryGeometry",
      "getPlayerRawRadius",
      "getDeflectGeometry",
      "withSpeedWindowBonus",
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
    },
    GameInfo = {
      "getPlayers",
      "getPlayerParts",
      "getSnapshotAt",
      "isSnapshotValid",
      "getPlayerMotion",
      "getLocalDashState",
      "getBallFrozen",
      "getAveragePing",
      "getBallSpeedLimits",
    },
    Cooldown = { "getDeflectCooldownState" },
    ClashStats = { "getStatus", "begin", "finish", "observe", "freeze", "get", "waitForNextClash" },
  },
  provides = {
    "step",
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
  bindCharacter = true,
}

return AutoSpam
