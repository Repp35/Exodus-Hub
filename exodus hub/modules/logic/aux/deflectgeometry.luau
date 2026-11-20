-- [[ deflectgeometry ]]

-- code
local Geometry = {}
local gameInfo, players, world
local CONFIG = {
  WINDOW_BASE = 0.85,
  WINDOW_SPREAD = 0.65,
  RANGE_BASE = 8.5,
  RANGE_BONUS_SPAN = 7.5,
  RANGE_BONUS_STEP = 0.225,
  RANGE_WINDOW_BONUS = 0.12,
  AUTO_PARRY_TRIGGER_PADDING = 0,
  AP_WINDOW_LOW_SPEED = 0.45,
  AP_WINDOW_HIGH_SPEED = 0.25,
  TRAINING_BASE_SPEED = 16,
  TRAINING_MAX_SPEED = 600,
  TRAINING_DEFLECT_DISTANCE = 8.5,
  TRAINING_TRIGGER_PADDING = 2,
  TRAINING_MAX_PING = 0.25,
  TRAINING_MAX_LEAD_FACTOR = 0.8,
  TRAINING_WINDOW_SLOW = 0.85,
  TRAINING_WINDOW_FAST = 0.2,
  TRAINING_WINDOW_FACTOR = 0.3,
  FRAME_BASE = 1 / 60,
}

local EMPTY_OPTIONS = {}
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function vector(value) return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z) end
local function validBallSpeed(value) return finite(value) and value >= 0 and value <= 1000 end
local function sharedLayout() return gameInfo.usesSharedLayout() end
local function projectParts(range, speed, window, factor, latency, extraRange, latencyFactor, padding)
  speed = finite(speed) and math.max(0, speed) or 0; range = finite(range) and range or 0
  extraRange = finite(extraRange) and extraRange or 0; window = finite(window) and math.max(0, window) or 0
  factor = finite(factor) and math.max(0, factor) or 1; latency = finite(latency) and math.max(0, latency) or 0
  latencyFactor = finite(latencyFactor) and math.max(0, latencyFactor) or 1; padding = finite(padding) and padding or 0
  local windowRadius, pingRadius = speed * window * factor, speed * latency * latencyFactor
  return range + extraRange + windowRadius + pingRadius + padding, windowRadius, pingRadius, window * factor + latency * latencyFactor
end
function Geometry.setup(deps)
  if type(deps) ~= "table" or type(deps.GameInfo) ~= "table" or type(deps.Utils) ~= "table" then return false, "GameInfo ou Utils ausente" end
  local nextPlayers, nextWorld = deps.Utils.getPlayers(), deps.Utils.getWorkspace()
  if not nextPlayers or not nextWorld then return false, "Players ou Workspace ausente" end
  gameInfo, players, world = deps.GameInfo, nextPlayers, nextWorld; return true
end
function Geometry.getDeflectRangeParameters() return CONFIG.RANGE_BASE, CONFIG.RANGE_BONUS_SPAN, sharedLayout() and 0.1125 or CONFIG.RANGE_BONUS_STEP end
function Geometry.getDeflectRange()
  local player = players.LocalPlayer; local range = player and player:GetAttribute("DeflectRange") or nil
  if sharedLayout() and player then return Geometry.getPlayerDeflectRange(player.UserId) end
  return range
end
function Geometry.getPlayerDeflectRange(id)
  local player = type(id) == "number" and players:GetPlayerByUserId(id)
  if not player then return nil end
  local range = player:GetAttribute("DeflectRange")
  if not finite(range) then return CONFIG.RANGE_BASE end
  range = math.clamp(range, CONFIG.RANGE_BASE, CONFIG.RANGE_BASE + CONFIG.RANGE_BONUS_SPAN)
  if sharedLayout() and range > CONFIG.RANGE_BASE and type(gameInfo.getClashContext) == "function" then
    local context = gameInfo.getClashContext(); local own = players.LocalPlayer
    if context and own and (id == own.UserId or id == context.partnerId) then
      local distance = gameInfo.getPlayerDistance(context.partnerId)
      if finite(distance) and distance <= math.max(20, range + 8) then return CONFIG.RANGE_BASE end
    end
  end
  return range
end
function Geometry.getPlayerRawRadius(id, speed, includePing)
  local range = Geometry.getPlayerDeflectRange(id)
  if not range then return nil end
  local latency = includePing and gameInfo.getAveragePing() or 0
  if not finite(latency) or latency < 0 then latency = 0 end
  return range + (finite(speed) and math.max(0, speed) * latency or 0)
end
function Geometry.getDeflectWindow(speed, includeResilience, playerId)
  local low, high = gameInfo.getBallSpeedLimits(); local gameBall = gameInfo.getDefenseSource()
  if not finite(speed) then
    local sync = gameInfo.getSyncData()
    if sync and finite(sync.Speed) then speed = sync.Speed end
  end
  if not finite(speed) or high <= low then return nil end
  local window = CONFIG.WINDOW_BASE - CONFIG.WINDOW_SPREAD * math.clamp((speed - low) / (high - low), 0, 1); local player = playerId and players:GetPlayerByUserId(playerId) or players.LocalPlayer
  local inClash = false
  if gameBall and player and type(gameBall.IsInClash) == "function" then inClash = gameBall:IsInClash(player) == true end
  if inClash and type(gameBall.GetClashMinWindow) == "function" then
    local minimum = gameBall:GetClashMinWindow(speed)
    if finite(minimum) then window = math.max(window, minimum) end
  end
  if includeResilience ~= false and not sharedLayout() then
    local range = Geometry.getDeflectRange()
    if finite(range) then window += math.clamp((range - CONFIG.RANGE_BASE) / CONFIG.RANGE_BONUS_SPAN, 0, 1) * CONFIG.RANGE_WINDOW_BONUS end
  end
  if inClash and type(gameBall.ApplyClashPressure) == "function" then
    window = gameBall:ApplyClashPressure(window, player)
  elseif inClash and type(gameBall.GetClashWindowScale) == "function" then
    local scale = gameBall:GetClashWindowScale()
    if finite(scale) and scale > 0 then window *= scale end
  end
  return window
end
function Geometry.getDefensePhysics()
  local gameBall = gameInfo.getDefenseSource(); local player = players.LocalPlayer
  local ping = gameInfo.getAveragePing()
  if not finite(ping) or ping < 0 then ping = 0 end
  local grace, cap = ping + 0.075, 0.35; local press = player and player:GetAttribute("PressDelay")
  if finite(press) then grace = math.max(grace, press + 0.05); cap = math.clamp(press + 0.05, 0.35, 0.45) end
  grace = math.clamp(grace, 0.075, cap); local inClash = gameBall and player and type(gameBall.IsInClash) == "function" and gameBall:IsInClash(player) == true
  if inClash and type(gameBall.ApplyClashPressureGrace) == "function" then grace = gameBall:ApplyClashPressureGrace(grace, player) end
  local kill = gameBall and type(gameBall.GetKillDistance) == "function" and gameBall:GetKillDistance() or 4
  return {
    killRadius = kill,
    grace = grace,
    ping = ping,
    uplink = ping,
    serverNow = world:GetServerTimeNow(),
    inClash = inClash == true,
    clashKnown = gameBall ~= nil and player ~= nil and type(gameBall.IsInClash) == "function",
  }
end
function Geometry.getDeflectGeometry(speed, window, factor, _scaleBase, latencyOverride, options)
  if not validBallSpeed(speed) then return nil end
  options = type(options) == "table" and options or EMPTY_OPTIONS; local includeResilience = options.resilience ~= false
  local range = includeResilience and Geometry.getDeflectRange() or CONFIG.RANGE_BASE
  if not finite(range) or range <= 0 then range = CONFIG.RANGE_BASE end
  if window == "ap" then
    local low, high = gameInfo.getBallSpeedLimits()
    if not finite(low) or not finite(high) or high <= low then return nil end
    local fraction = math.clamp((speed - low) / (high - low), 0, 1); local actual = Geometry.getDeflectWindow(speed, includeResilience)
    if not finite(actual) then return nil end
    window = math.max(
      0,
      actual
        + (CONFIG.AP_WINDOW_LOW_SPEED - CONFIG.WINDOW_BASE) * (1 - fraction)
        + (CONFIG.AP_WINDOW_HIGH_SPEED - (CONFIG.WINDOW_BASE - CONFIG.WINDOW_SPREAD)) * fraction
    )
  elseif not finite(window) then
    window = Geometry.getDeflectWindow(speed, includeResilience)
    if finite(window) then local minimum = finite(options.minimumWindow) and math.max(0, options.minimumWindow) or 0; window = math.max(window, minimum) end
  end
  if finite(window) then
    window = window * (finite(options.windowScale) and math.max(0, options.windowScale) or 1); window += finite(options.windowOffset) and options.windowOffset or 0
    if options.speedWindowBonus == true then
      local low, high = gameInfo.getBallSpeedLimits()
      if finite(low) and finite(high) and high > low then window += CONFIG.WINDOW_SPREAD * 0.20 * math.clamp((speed - low) / (high - low), 0, 1) end
    end
  end
  if not finite(window) or window < 0 then return nil end
  local latency = options.ping == false and 0 or (finite(latencyOverride) and latencyOverride or gameInfo.getAveragePing())
  if not finite(latency) or latency < 0 then latency = 0 end
  factor = finite(factor) and math.max(0, factor) or 1; local base = range
  local pingFactor = finite(options.latencyFactor) and math.max(0, options.latencyFactor) or factor
  local full, windowRadius, pingRadius, effectiveWindow = projectParts(base, speed, window, factor, latency, nil, pingFactor)
  return {
    fullRadius = full,
    baseRadius = CONFIG.RANGE_BASE,
    windowRadius = windowRadius,
    latencyRadius = pingRadius,
    pureRadius = CONFIG.RANGE_BASE,
    noWindowParryRadius = range,
    resilienceBonus = range - CONFIG.RANGE_BASE,
    pingRadius = pingRadius,
    deflectWindow = window,
    effectiveWindow = effectiveWindow,
    leadTime = window + latency,
    windowFactor = factor,
  }
end
function Geometry.getAutoParryGeometry(speed, factor, frameLead, latencyOverride, playerId)
  if not validBallSpeed(speed) then return nil end
  local low, high = gameInfo.getBallSpeedLimits()
  if not finite(low) or not finite(high) or high <= low then return nil end
  local window = Geometry.getDeflectWindow(speed, false, playerId); local range = playerId and Geometry.getPlayerDeflectRange(playerId) or Geometry.getDeflectRange()
  if not finite(range) or range <= 0 then range = CONFIG.RANGE_BASE end
  if not finite(window) or window < 0 then return nil end
  local latency = finite(latencyOverride) and math.max(0, latencyOverride) or gameInfo.getAveragePing()
  if not finite(latency) then latency = 0 end
  local factorValue = finite(factor) and math.clamp(factor, 0, 1) or 0.3; local frame = finite(frameLead) and math.clamp(frameLead, 0, 0.15) or 1 / 60
  local networkLead = latency + frame; local lead = latency + math.min(window * factorValue + frame, window * 0.95)
  return {
    fullRadius = range + CONFIG.AUTO_PARRY_TRIGGER_PADDING + speed * lead,
    pureRadius = CONFIG.RANGE_BASE,
    noWindowParryRadius = range,
    resilienceBonus = range - CONFIG.RANGE_BASE,
    pingRadius = speed * latency,
    deflectWindow = window,
    effectiveWindow = lead,
    leadTime = lead,
    serverLeadTime = window + latency,
    windowFactor = factorValue,
    triggerPadding = CONFIG.AUTO_PARRY_TRIGGER_PADDING,
    networkLead = networkLead,
    uplinkLead = latency,
    frameLead = frame,
    autoParry = true,
    killRadius = 4,
  }
end
function Geometry.getProjectedDeflectRadius(geometry, closingSpeed)
  if type(geometry) ~= "table" or not finite(geometry.noWindowParryRadius) or not finite(geometry.effectiveWindow) or not finite(closingSpeed) then return nil end
  return geometry.noWindowParryRadius + math.max(0, closingSpeed) * geometry.effectiveWindow
end
function Geometry.getTrainingGeometry(speed, factor)
  speed = finite(speed) and math.max(speed, CONFIG.TRAINING_BASE_SPEED) or CONFIG.TRAINING_BASE_SPEED; local span = CONFIG.TRAINING_MAX_SPEED - CONFIG.TRAINING_BASE_SPEED
  local progress = span > 0 and math.clamp((speed - CONFIG.TRAINING_BASE_SPEED) / span, 0, 1) or 1
  local blockWindow = CONFIG.TRAINING_WINDOW_SLOW + (CONFIG.TRAINING_WINDOW_FAST - CONFIG.TRAINING_WINDOW_SLOW) * progress; local deflectDistance = CONFIG.TRAINING_DEFLECT_DISTANCE
  factor = finite(factor) and math.clamp(factor, 0, CONFIG.TRAINING_MAX_LEAD_FACTOR) or CONFIG.TRAINING_WINDOW_FACTOR
  local effectiveWindow = blockWindow * factor
  return {
    fullRadius = deflectDistance + speed * effectiveWindow + CONFIG.TRAINING_TRIGGER_PADDING,
    pureRadius = deflectDistance,
    noWindowParryRadius = deflectDistance,
    resilienceBonus = 0,
    pingRadius = 0,
    deflectWindow = blockWindow,
    effectiveWindow = effectiveWindow,
    leadTime = blockWindow,
    windowFactor = factor,
    triggerPadding = CONFIG.TRAINING_TRIGGER_PADDING,
    training = true,
  }
end
function Geometry.isBallWithinDeflectRadius(factor)
  local snapshot = gameInfo.getSnapshotAt()
  if not gameInfo.isSnapshotValid(snapshot) or snapshot.teleported then return false end
  local player = players.LocalPlayer; local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  if not root or not root.Parent then return false end
  local speed = tonumber(snapshot.syncSpeed)
  if not finite(speed) or speed <= 0 then speed = snapshot.speed end
  if not finite(speed) or speed <= 0 then return false end
  local geometry = Geometry.getDeflectGeometry(speed, nil, factor, false); return geometry ~= nil and (snapshot.position - root.Position).Magnitude <= geometry.fullRadius
end
function Geometry.resolve(speed, options)
  options = type(options) == "table" and options or EMPTY_OPTIONS
  if options.profile == "training" then return Geometry.getTrainingGeometry(speed, options.factor) end
  if options.profile == "autoParry" then return Geometry.getAutoParryGeometry(speed, options.factor, options.frameLead, options.latency) end
  return Geometry.getDeflectGeometry(speed, options.window, options.factor, false, options.latency, options)
end
function Geometry.getRadius(speed, options)
  local result = Geometry.resolve(speed, options)
  if not result then return nil end
  local component = type(options) == "table" and options.component or "full"
  if component == "base" then return result.pureRadius end
  if component == "raw" then return result.noWindowParryRadius end
  if component == "resilience" then return result.resilienceBonus end
  if component == "ping" then return result.pingRadius end
  if component == "window" then return result.fullRadius - result.noWindowParryRadius - result.pingRadius - (result.triggerPadding or 0) end
  if component == "full" then return result.fullRadius end
  return nil
end
function Geometry.getGuaranteedRadius(value, speed, ping) return value.noWindowParryRadius + math.max(0, speed) * math.max(0, ping) end
function Geometry.withAutoParryFactor(value, factor, closingSpeed, ping)
  local result = table.clone(value); local uplink = finite(value.uplinkLead) and value.uplinkLead or ping
  local frame = finite(value.frameLead) and value.frameLead or math.max(0, (value.networkLead or 0) - uplink)
  result.windowFactor = factor
  result.effectiveWindow = uplink + math.min(value.deflectWindow * factor + frame, value.deflectWindow * 0.95); result.leadTime = result.effectiveWindow
  result.fullRadius = value.noWindowParryRadius + (value.triggerPadding or 0) + math.max(0, closingSpeed) * result.effectiveWindow; return result
end
function Geometry.getTrainingTrigger(value, closingSpeed, ping, frameAllowance, retryFactor)
  if finite(retryFactor) then return value.noWindowParryRadius + math.max(0, closingSpeed) * value.deflectWindow * retryFactor end
  local latency = finite(ping) and math.clamp(ping, 0, CONFIG.TRAINING_MAX_PING) or 0
  local lead = math.min(value.deflectWindow * CONFIG.TRAINING_MAX_LEAD_FACTOR, value.effectiveWindow + latency + CONFIG.FRAME_BASE + frameAllowance)
  return value.noWindowParryRadius + CONFIG.TRAINING_TRIGGER_PADDING + math.max(0, closingSpeed) * lead
end
function Geometry.getTrajectory(position, velocity, rootPosition, nominalSpeed, geometry, rangeOverride, rootVelocity)
  local delta = rootPosition - position; local distance = delta.Magnitude
  local ballVelocity = velocity
  if finite(nominalSpeed) and nominalSpeed > 0 and ballVelocity.Magnitude > nominalSpeed * 1.1 then ballVelocity = ballVelocity.Unit * nominalSpeed * 1.1 end
  if typeof(rootVelocity) ~= "Vector3" or not finite(rootVelocity.X) or not finite(rootVelocity.Y) or not finite(rootVelocity.Z) then rootVelocity = Vector3.zero end
  local relative = ballVelocity - rootVelocity; local closing = distance > 0 and relative:Dot(delta) / distance or 0
  if not finite(closing) then closing = 0 end
  local padding = finite(geometry.triggerPadding) and math.max(0, geometry.triggerPadding) or 0; local range = rangeOverride or (geometry.noWindowParryRadius + padding)
  local threshold = range + math.max(0, closing) * geometry.effectiveWindow; local entry = math.huge
  local c = delta:Dot(delta) - range * range
  if c <= 0 then
    entry = 0
  else
    local a = relative:Dot(relative); local b = delta:Dot(relative)
    if a > 0.000001 and b > 0 then
      local discriminant = b * b - a * c
      if discriminant >= 0 then entry = c / (b + math.sqrt(discriminant)) end
    end
  end
  return distance, closing, threshold, entry
end
function Geometry.getDanger(position, velocity, targetPosition, speed, range, responseTime, targetVelocity)
  if not vector(position) or not vector(velocity) or not vector(targetPosition) or not validBallSpeed(speed) then return nil end
  if not finite(range) or range <= 0 or not finite(responseTime) or responseTime < 0 then return nil end
  local g = { noWindowParryRadius = range, effectiveWindow = responseTime }
  local distance, closing, _, entry = Geometry.getTrajectory(position, velocity, targetPosition, speed, g, range, targetVelocity); local ballVelocity = velocity
  if speed > 0 and ballVelocity.Magnitude > speed * 1.1 then ballVelocity = ballVelocity.Unit * speed * 1.1 end
  local relative = ballVelocity - (vector(targetVelocity) and targetVelocity or Vector3.zero); local delta = targetPosition - position
  local squaredSpeed = relative:Dot(relative); local closestAt = squaredSpeed > 0.000001 and math.max(0, delta:Dot(relative) / squaredSpeed) or 0
  local closestDistance = (delta - relative * closestAt).Magnitude; local alignment = distance > 0 and squaredSpeed > 0.000001 and math.clamp(closing / math.sqrt(squaredSpeed), -1, 1) or 0
  local score = entry == 0 and 100 or (finite(entry) and responseTime > 0 and 100 * math.clamp(1 - entry / (2 * responseTime), 0, 1) or 0)
  return {
    score = score,
    ready = entry == 0 or (closing > 0 and entry <= responseTime),
    distance = distance,
    closingSpeed = closing,
    entryTime = entry,
    responseTime = responseTime,
    alignment = alignment,
    closestDistance = closestDistance,
    closestAt = closestAt,
    range = range,
  }
end
function Geometry.getTrainingLatency(ping) return finite(ping) and math.clamp(ping, 0, CONFIG.TRAINING_MAX_PING) or 0 end
function Geometry.getProjectedTriggerRadius(value, closingSpeed) return Geometry.getProjectedDeflectRadius(value, closingSpeed) + (value.triggerPadding or 0) end
function Geometry.addLatencyRadius(range, speed, latency) return range + math.max(0, speed) * math.max(0, latency) end
function Geometry.withSpeedWindowBonus(value, speed, low, high, factor)
  local result = table.clone(value)
  if finite(low) and finite(high) and high > low then
    local bonus = CONFIG.WINDOW_SPREAD * 0.20 * math.clamp((speed - low) / (high - low), 0, 1); result.deflectWindow += bonus
    result.effectiveWindow += bonus * factor
    result.fullRadius += speed * bonus * factor
    result.leadTime += bonus
  end
  return result
end
function Geometry.projectRadius(...)
  local fullRadius = projectParts(...); return fullRadius
end
function Geometry.compose(parts)
  if type(parts) ~= "table" then return nil end
  local full, windowRadius, pingRadius, effectiveWindow =
    projectParts(parts.range, parts.speed, parts.window, parts.factor, parts.latency, parts.extraRange, parts.latencyFactor, parts.padding)
  return { fullRadius = full, windowRadius = windowRadius, pingRadius = pingRadius, effectiveWindow = effectiveWindow }
end
function Geometry.getWindow(speed, options)
  local value = Geometry.resolve(speed, options)
  if not value then return nil end
  if type(options) == "table" and options.raw == true then return value.deflectWindow end
  return value.deflectWindow * value.windowFactor
end
function Geometry.getKillRadius(value) return type(value) == "table" and finite(value.killRadius) and value.killRadius or 4 end
Geometry.__contract = {
  requires = { GameInfo = "gameinfo", Utils = "utils" },
  requiresMethods = {
    GameInfo = {
      "usesSharedLayout",
      "getDefenseSource",
      "getBallSpeedLimits",
      "getSyncData",
      "getAveragePing",
      "getClashContext",
      "getPlayerDistance",
      "getSnapshotAt",
      "isSnapshotValid",
    },
    Utils = { "getPlayers", "getWorkspace" },
  },
  provides = {
    "setup",
    "getDeflectRangeParameters",
    "getDeflectRange",
    "getPlayerDeflectRange",
    "getPlayerRawRadius",
    "getDeflectWindow",
    "getDefensePhysics",
    "getDeflectGeometry",
    "getAutoParryGeometry",
    "getProjectedDeflectRadius",
    "getTrainingGeometry",
    "isBallWithinDeflectRadius",
    "resolve",
    "getRadius",
    "getGuaranteedRadius",
    "withAutoParryFactor",
    "getTrainingTrigger",
    "getTrajectory",
    "getDanger",
    "getTrainingLatency",
    "getProjectedTriggerRadius",
    "addLatencyRadius",
    "withSpeedWindowBonus",
    "projectRadius",
    "compose",
    "getWindow",
    "getKillRadius",
  },
}

return Geometry
