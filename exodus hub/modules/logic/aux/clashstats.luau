-- [[ clash stats ]]

-- module
local ClashStats = {}
local utils
local gameInfo
local players
local localPlayer
local deflectGeometry
local stats

-- configuration
local CONFIG = {
  CLASH_RETENTION_SECONDS = 1.5,
  PACKET_FALLBACK_SECONDS = 0.5,
  CPS_SAMPLE_CAP = 35,
  CPS_SMOOTHING_FACTOR = 0.2,
}

-- helpers
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function userId(value)
  if type(value) == "string" then value = tonumber(value) end
  return finite(value) and value > 0 and value % 1 == 0 and value or nil
end
local function snapshotSpeed(snapshot)
  if not snapshot then return nil end
  local speed = tonumber(snapshot.syncSpeed); return finite(speed) and speed > 0 and speed or snapshot.speed
end

-- formatting
local function formatPoint(point)
  if typeof(point) ~= "Vector3" then return "unavailable" end
  return string.format("%.2f, %.2f, %.2f", point.X, point.Y, point.Z)
end
local function formatSample(title, sample)
  if not sample then return title .. ": unavailable\n" end
  return string.format(
    "%s\nMy position: %s\nOpponent position: %s\nBall position: %s\nDistance: %s studs\nSpeed: %s\n",
    title,
    formatPoint(sample.own),
    formatPoint(sample.opponent),
    formatPoint(sample.ball),
    sample.distance and string.format("%.2f", sample.distance) or "?",
    sample.speed and string.format("%.2f", sample.speed) or "?"
  )
end

-- lifecycle
function ClashStats.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" or type(deps.GameInfo) ~= "table" then return false, "dependências ausentes" end
  if type(deps.DeflectGeometry) ~= "table" then return false, "DeflectGeometry ausente" end
  ClashStats.teardown(); utils, gameInfo, deflectGeometry = deps.Utils, deps.GameInfo, deps.DeflectGeometry
  players, localPlayer = utils.getPlayers(), utils.getLocalPlayer()
  if not players or not localPlayer then return false, "serviços indisponíveis" end
  stats = nil; return true
end
function ClashStats.teardown()
  stats = nil; utils, gameInfo, players, localPlayer, deflectGeometry = nil, nil, nil, nil, nil
end

-- recording
function ClashStats.finish(reason, time)
  if not stats or stats.frozen then return end
  time = finite(time) and time or stats.lastObserved or stats.startedAt; stats.frozen, stats.waitingForClash = true, false
  stats.duration = math.max(0, time - stats.startedAt); stats.cps = stats.duration > 0 and stats.totalSwitches / stats.duration or 0
  stats.endReason = reason
end
function ClashStats.begin(partner, time)
  if stats and not stats.frozen then ClashStats.finish("novo clash", stats.lastObserved) end
  local previous = stats
    and {
      ball = stats.incomingBall,
      target = stats.travelObservedTarget,
      last = stats.lastIncomingTTI,
      penultimate = stats.previousIncomingTTI,
      at = stats.incomingRecordedAt,
      outgoing = stats.lastOutgoingTTI,
      outgoingPrevious = stats.previousOutgoingTTI,
      outgoingAt = stats.outgoingRecordedAt,
      partner = stats.partnerId,
    }
  stats = stats or {}; table.clear(stats)
  if previous then
    stats.incomingBall, stats.travelObservedTarget = previous.ball, previous.target
    stats.lastIncomingTTI, stats.previousIncomingTTI, stats.incomingRecordedAt = previous.last, previous.penultimate, previous.at
    if previous.partner == partner then stats.lastOutgoingTTI, stats.previousOutgoingTTI, stats.outgoingRecordedAt = previous.outgoing, previous.outgoingPrevious, previous.outgoingAt end
  end
  stats.partnerId, stats.cps, stats.lastObserved = partner, 0, time; stats.startedAt, stats.startedDate = time, os.date("!%Y-%m-%d %H:%M:%S")
  stats.totalSwitches, stats.frozen = 0, false
end

-- observation
function ClashStats.observe(session, snapshot, time, fresh)
  local partner = session.active and session.partner
  if not partner then local context = gameInfo.getClashContext(); partner = context and context.partnerId end
  local target = userId(snapshot.exchangeTargetId or snapshot.targetId)
  if
    not partner
    and stats
    and not stats.frozen
    and time - (stats.lastSwitchAt or stats.startedAt) <= CONFIG.CLASH_RETENTION_SECONDS
    and (target == localPlayer.UserId or target == stats.partnerId)
  then
    partner = stats.partnerId
  end
  if not partner then
    if stats and not stats.frozen and time - stats.lastObserved > CONFIG.CLASH_RETENTION_SECONDS then ClashStats.finish("clash encerrado", stats.lastObserved) end
    if stats and stats.frozen then stats.waitingForClash = true end
    return
  end
  if stats and stats.frozen then
    if not stats.waitingForClash then return end
    ClashStats.begin(partner, time)
  elseif not stats or stats.partnerId ~= partner or time - stats.lastObserved > CONFIG.CLASH_RETENTION_SECONDS then
    ClashStats.begin(partner, time)
  end
  local observeTarget = fresh or not stats.lastPacketAt or time - stats.lastPacketAt > CONFIG.PACKET_FALLBACK_SECONDS
  if fresh then stats.lastPacketAt = time end
  if observeTarget and target then
    local me = localPlayer.UserId
    if fresh then
      if stats.incomingBall ~= snapshot.ball or snapshot.teleported or snapshot.resetting then
        stats.travelObservedTarget = nil
        if stats.incomingBall ~= snapshot.ball then
          stats.lastIncomingTTI, stats.previousIncomingTTI, stats.incomingRecordedAt = nil, nil, nil; stats.lastOutgoingTTI, stats.previousOutgoingTTI, stats.outgoingRecordedAt = nil, nil, nil
        end
        stats.incomingBall = snapshot.ball
      end
      if
        (target == me or target == partner)
        and stats.travelObservedTarget ~= target
        and not snapshot.teleported
        and not snapshot.resetting
        and not snapshot.locked
      then
        local root = session.root
        if target ~= me then
          local position, velocity = gameInfo.getPlayerMotion(target); root = typeof(position) == "Vector3" and { Parent = true, Position = position, AssemblyLinearVelocity = velocity } or nil
        end
        local position = typeof(snapshot.realPosition) == "Vector3" and snapshot.realPosition or snapshot.position; local velocity = snapshot.velocity
        local tti
        if root and root.Parent and typeof(position) == "Vector3" and typeof(velocity) == "Vector3" then
          local delta = root.Position - position; local distance = delta.Magnitude
          local kill = deflectGeometry.getKillRadius(deflectGeometry.getDefensePhysics()); local remaining = math.max(0, distance - kill)
          local rootVelocity = typeof(root.AssemblyLinearVelocity) == "Vector3" and root.AssemblyLinearVelocity or Vector3.zero
          local closing = distance > 0 and (velocity - rootVelocity):Dot(delta) / distance or 0
          if remaining == 0 then
            tti = 0
          elseif finite(closing) and closing > 0 then
            local acceleration = finite(snapshot.syncAcceleration) and math.max(0, snapshot.syncAcceleration) or 0
            tti = acceleration > 0.0001 and 2 * remaining / (closing + math.sqrt(closing * closing + 2 * acceleration * remaining)) or remaining / closing
          end
        end
        local value = finite(tti) and tti >= 0 and tti or nil
        if target == me then stats.previousIncomingTTI, stats.lastIncomingTTI, stats.incomingRecordedAt = stats.lastIncomingTTI, value, time
        else stats.previousOutgoingTTI, stats.lastOutgoingTTI, stats.outgoingRecordedAt = stats.lastOutgoingTTI, value, time end
      end
      stats.travelObservedTarget = target
    end
    if stats.lastTarget == me and target == partner then
      stats.cycleArmed = true; stats.lastSwitchAt = time
    elseif stats.lastTarget == partner and target == me then
      if stats.cycleArmed then
        stats.totalSwitches += 1
        if stats.lastCycleAt and time > stats.lastCycleAt then
          stats.cycleInterval = time - stats.lastCycleAt; local sample = math.min(CONFIG.CPS_SAMPLE_CAP, 1 / stats.cycleInterval)
          stats.currentCps = stats.currentCps and (stats.currentCps + CONFIG.CPS_SMOOTHING_FACTOR * (sample - stats.currentCps)) or sample
        end
        stats.lastCycleAt = time
      end
      stats.cycleArmed = false; stats.lastSwitchAt = time
    elseif target ~= me and target ~= partner then
      stats.cycleArmed, stats.lastCycleAt, stats.cycleInterval, stats.currentCps = false, nil, nil, nil
    end
    stats.lastTarget = target
  end
  local duration = time - stats.startedAt; stats.cps = duration > 0 and stats.totalSwitches / duration or 0
  local speed = snapshotSpeed(snapshot)
  if finite(speed) and speed >= 0 then stats.speed = speed end
  local root = session.root
  if not root or not root.Parent then return end
  local other = gameInfo.getPlayerMotion(partner); local own = root.Position
  local distance = typeof(other) == "Vector3" and (other - own).Magnitude or nil
  if finite(distance) then stats.distance = distance end
  stats.lastObserved = time; local sample = stats.endSample or {}
  sample.time, sample.distance, sample.speed, sample.cps = math.max(0, time - stats.startedAt), distance, stats.speed, stats.cps
  sample.own, sample.opponent, sample.ball = own, other, snapshot.position
  if not stats.startSample then stats.startSample = table.clone(sample) end
  stats.endSample = sample
end
function ClashStats.freeze(playerId, session)
  if not stats or stats.frozen or (playerId ~= localPlayer.UserId and playerId ~= stats.partnerId) then return end
  local time = utils.now(); stats.deceasedId = playerId
  local sample = stats.endSample
  if sample and session and session.root and session.root.Parent then
    local other = gameInfo.getPlayerMotion(stats.partnerId); sample.own, sample.opponent = session.root.Position, other
    if typeof(other) == "Vector3" then sample.distance = (other - sample.own).Magnitude end
  end
  ClashStats.finish(playerId == localPlayer.UserId and "jogador morreu" or "oponente morreu", time)
end
function ClashStats.waitForNextClash()
  if stats and stats.frozen then stats.waitingForClash = true end
end
function ClashStats.get() return stats end
function ClashStats.getStatus()
  if not stats then return {} end
  local currentCps = stats.currentCps
  if currentCps and not stats.frozen then currentCps = math.min(currentCps, 1 / math.max(stats.cycleInterval or 0, stats.lastCycleAt and utils.now() - stats.lastCycleAt or math.huge)) end
  local duration = stats.duration or (stats.startedAt and math.max(0, utils.now() - stats.startedAt))
  return {
    partnerId = stats.partnerId,
    distance = stats.distance,
    cps = stats.cps,
    currentCps = currentCps,
    startSample = stats.startSample and table.clone(stats.startSample) or nil,
    endSample = stats.endSample and table.clone(stats.endSample) or nil,
    endReason = stats.endReason,
    speed = stats.speed,
    frozen = stats.frozen,
    duration = duration,
    lastIncomingTTI = stats.lastIncomingTTI,
    previousIncomingTTI = stats.previousIncomingTTI,
    incomingRecordedAt = stats.incomingRecordedAt,
    lastOutgoingTTI = stats.lastOutgoingTTI,
    previousOutgoingTTI = stats.previousOutgoingTTI,
    outgoingRecordedAt = stats.outgoingRecordedAt,
    deceasedName = stats.deceasedId and (stats.deceasedId == localPlayer.UserId and "You" or "Opponent") or nil,
    deceasedId = stats.deceasedId,
  }
end

-- contract
ClashStats.__contract = {
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    DeflectGeometry = "deflectgeometry",
  },
  requiresMethods = {
    DeflectGeometry = { "getKillRadius", "getDefensePhysics" },
    Utils = { "getLocalPlayer", "getPlayers", "now" },
    GameInfo = { "getClashContext", "getPlayerMotion" },
  },
  provides = { "setup", "teardown", "begin", "finish", "observe", "freeze", "get", "getStatus", "waitForNextClash" },
}

return ClashStats
