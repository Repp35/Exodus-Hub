-- [[ autofierce ]]

-- module
local AutoFierce = {}
local deflectGeometry
local utils, gameInfo, remote, autoParry, cooldownInfo, autoSpam
local connections = {}
local lastFierceEpisode, localUserId
local pendingEpisode
local timerEpisode, timerStartedAt, timerReadyAt, timerWindowEndsAt
local hookedAbility, hookedRaw, hookedWrapper
local epoch = 0
local errorAt = -math.huge

-- configuration
local CONFIG = {
  SYNC_MAX_AGE = 0.25,
  WINDOW_FACTOR = 0.3,
  SERVER_FRAME_MARGIN = 1 / 60,
}

-- helpers
local function track(connection)
  connections[#connections + 1] = connection; utils.trackGlobal(connection)
  return connection
end
local function enabled() return utils and utils.isActive() and utils.getConfigValue("AutoFierce") == true and gameInfo.areAbilitiesEnabled() end
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function unhookManualFierce()
  local ability, wrapper, raw = hookedAbility, hookedWrapper, hookedRaw
  if ability and wrapper then
    pcall(function()
      if ability.ActivateAndBlock == wrapper then ability.ActivateAndBlock = raw end
    end)
  end
  hookedAbility, hookedRaw, hookedWrapper = nil, nil, nil
end
local function bindManualFierce()
  local ability = gameInfo.getFierceDeflectAbility()
  if ability == hookedAbility and ability and ability.ActivateAndBlock == hookedWrapper then return end
  unhookManualFierce()
  if type(ability) ~= "table" or type(ability.ActivateAndBlock) ~= "function" then return end
  local original, raw = ability.ActivateAndBlock, rawget(ability, "ActivateAndBlock"); local owner, boundParry = epoch, autoParry
  local wrapper = function(self, ...)
    local token
    if owner == epoch and pendingEpisode == nil and (not finite(self.Cooldown) or self.Cooldown <= 0) then
      local ok, value = pcall(boundParry.beginFierce)
      if ok then token = value end
    end
    local result = table.pack(pcall(original, self, ...))
    if owner == epoch and (not result[1] or result[2] == false) then boundParry.cancelFierce(token) end
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
  end
  local ok = pcall(function() ability.ActivateAndBlock = wrapper end)
  if ok and ability.ActivateAndBlock == wrapper then hookedAbility, hookedRaw, hookedWrapper = ability, raw, wrapper end
end
local function validTargetSnapshot(now)
  local snapshot = type(gameInfo.getParrySnapshot) == "function" and gameInfo.getParrySnapshot(now) or gameInfo.getSnapshotAt(now)
  if
    not gameInfo.isSnapshotValid(snapshot)
    or snapshot.teleported
    or snapshot.locked
    or snapshot.resetting
    or snapshot.ballCanMove == false
    or snapshot.targetUncertain
  then
    return nil
  end
  if localUserId == nil or snapshot.targetId ~= localUserId or gameInfo.getBallFrozen() == true then return nil end
  if not finite(snapshot.syncAt) or snapshot.syncAt <= 0 or now < snapshot.syncAt or now - snapshot.syncAt > CONFIG.SYNC_MAX_AGE then return nil end
  return snapshot
end
local function incomingInWindow(snapshot, now)
  local timing = autoParry.getTiming(snapshot, now, nil, CONFIG.WINDOW_FACTOR)
  if not timing or not finite(timing.distance) or not finite(timing.triggerDistance) or timing.distance > timing.triggerDistance then return nil end
  return timing.approaching and timing or nil
end
local function sustainedCooldown(cooldown, now, timing)
  if not cooldown or cooldown.blocking ~= true then return false end
  if cooldown.source ~= "local" and cooldown.source ~= "server" then return false end
  local startedAt = cooldown.blockingSince
  if not finite(startedAt) or startedAt <= 0 or startedAt > now then return false end
  if not finite(cooldown.episode) or cooldown.episode <= 0 then return false end
  local deadline = finite(cooldown.windowEndsAt) and cooldown.windowEndsAt or cooldown.missDeadline; local pendingOpen = finite(deadline) and deadline > now
  if cooldown.predictedReset == true then return false end
  if timing and cooldown.miss == true and not pendingOpen and cooldown.windowExpired ~= false then return true end
  local physics = deflectGeometry.getDefensePhysics(); local ping = gameInfo.getAveragePing()
  if not finite(ping) or ping < 0 then return false end
  local responseMargin = math.min(ping * 2, 1) + CONFIG.SERVER_FRAME_MARGIN
  if timerEpisode ~= cooldown.episode or timerStartedAt ~= startedAt then
    local window = deflectGeometry.getDeflectWindow()
    if not finite(window) or window <= 0 then return false end
    timerEpisode, timerStartedAt, timerReadyAt = cooldown.episode, startedAt, startedAt + window + responseMargin; timerWindowEndsAt = startedAt + window
  end
  if finite(cooldown.missDeadline) then timerReadyAt = math.max(timerReadyAt, cooldown.missDeadline + responseMargin) end
  if cooldown.predictedReset == true then return false end
  if timing then
    local entry = timing.predictionTimeToRange or timing.timeToRange; local killTime = timing.timeToKill
    if finite(killTime) and finite(cooldown.remaining) and cooldown.remaining + ping + CONFIG.SERVER_FRAME_MARGIN < killTime then return false end
    local miss = cooldown.miss == true and cooldown.windowExpired ~= false and not pendingOpen
    if miss then return true end
    if finite(killTime) and killTime <= responseMargin then
      local closesAt = finite(deadline) and deadline or timerWindowEndsAt; local canStillParry = closesAt and closesAt > now and (not finite(entry) or entry <= closesAt - now)
      if not canStillParry then return true end
    end
  end
  if physics and physics.inClash == true then return false end
  return now > timerReadyAt
end
local function fierceReady()
  local ability = gameInfo.getFierceDeflectAbility()
  if type(ability) ~= "table" or type(ability.ActivateAndBlock) ~= "function" or not finite(ability.Cooldown) or ability.Cooldown > 0 then return false end
  if type(ability.IsOwnerAlive) == "function" and not ability:IsOwnerAlive() then return false end
  if type(ability.IsAvailable) == "function" and not ability:IsAvailable(false) then return false end
  return true
end

-- detection
local function update()
  if pendingEpisode ~= nil then return end
  local now = os.clock(); local cooldown = cooldownInfo.getDeflectCooldownState()
  sustainedCooldown(cooldown, now)
  if not enabled() or not fierceReady() then return end
  local snapshot = validTargetSnapshot(now); local timing = snapshot and incomingInWindow(snapshot, now)
  if not timing or not finite(timing.timeToKill) or timing.timeToKill < 0 or not cooldown or not finite(cooldown.remaining) or cooldown.remaining <= 0 then return end
  local ping = gameInfo.getAveragePing()
  if not finite(ping) or ping < 0 or timing.timeToKill > cooldown.remaining + ping + CONFIG.SERVER_FRAME_MARGIN then return end
  if not sustainedCooldown(cooldown, now, timing) or cooldown.episode <= lastFierceEpisode then return end
  local episode, ball, token = cooldown.episode, snapshot.ball, nil; local owner = epoch
  pendingEpisode = episode
  local ok, sent = pcall(function()
    return remote.fireFierce(function()
      if owner ~= epoch or not enabled() or not fierceReady() then return false end
      local currentSnapshot = validTargetSnapshot(os.clock())
      if not currentSnapshot or currentSnapshot.ball ~= ball then return false end
      local current = cooldownInfo.getDeflectCooldownState(); local currentTiming = incomingInWindow(currentSnapshot, os.clock())
      if not current or current.episode ~= episode or not currentTiming or not finite(currentTiming.timeToKill) or currentTiming.timeToKill < 0 then return false end
      local currentPing = gameInfo.getAveragePing()
      if not finite(current.remaining) or current.remaining <= 0 or not finite(currentPing) or currentPing < 0 then return false end
      if
        currentTiming.timeToKill > current.remaining + currentPing + CONFIG.SERVER_FRAME_MARGIN or not sustainedCooldown(current, os.clock(), currentTiming)
      then
        return false
      end
      if not token then token = autoParry.beginFierce() end
      return true
    end)
  end)
  if owner ~= epoch then return end
  pendingEpisode = nil
  if ok and sent == true then
    if episode then lastFierceEpisode = math.max(lastFierceEpisode, episode) end
  else
    autoParry.cancelFierce(token)
  end
  if not ok and os.clock() - errorAt >= 1 then errorAt = os.clock(); warn("[AutoFierce] " .. tostring(sent)) end
end

-- lifecycle
function AutoFierce.setup(deps)
  if type(deps) ~= "table" or type(deps.DeflectGeometry) ~= "table" then return false, "DeflectGeometry ausente" end
  if
    type(deps) ~= "table"
    or type(deps.Utils) ~= "table"
    or type(deps.GameInfo) ~= "table"
    or type(deps.Remote) ~= "table"
    or type(deps.AutoParry) ~= "table"
    or type(deps.Cooldown) ~= "table"
    or type(deps.AutoSpam) ~= "table"
  then
    return false, "dependências ausentes: Utils, GameInfo ou Remote"
  end
  AutoFierce.teardown(); deflectGeometry = deps.DeflectGeometry
  utils, gameInfo, remote, autoParry, cooldownInfo = deps.Utils, deps.GameInfo, deps.Remote, deps.AutoParry, deps.Cooldown; autoSpam = deps.AutoSpam
  lastFierceEpisode, pendingEpisode = 0, nil; local player = utils.getLocalPlayer()
  localUserId = player and player.UserId; local runService = utils.getRunService()
  if not runService or not runService.Heartbeat then return false, "Heartbeat indisponível" end
  bindManualFierce(); local owner = epoch
  track(runService.Heartbeat:Connect(function()
    if owner ~= epoch then return end
    bindManualFierce(); update()
  end))
  return true
end
function AutoFierce.teardown()
  epoch += 1; errorAt = -math.huge
  unhookManualFierce(); timerEpisode, timerStartedAt, timerReadyAt, timerWindowEndsAt = nil, nil, nil, nil
  for _, connection in ipairs(connections) do
    if utils then utils.untrackGlobal(connection) end
    connection:Disconnect()
  end
  connections = {}; lastFierceEpisode, localUserId, pendingEpisode = nil, nil, nil
  utils, gameInfo, remote, autoParry, cooldownInfo, autoSpam = nil, nil, nil, nil, nil, nil
end

-- contract
AutoFierce.__contract = {
  requires = {
    DeflectGeometry = "deflectgeometry",
    Utils = "utils",
    GameInfo = "gameinfo",
    Remote = "remote",
    AutoParry = "autoparry",
    Cooldown = "cooldown",
    AutoSpam = "autospam",
  },
  requiresMethods = {
    DeflectGeometry = { "getDefensePhysics", "getDeflectWindow" },
    Utils = {
      "getConfigValue",
      "getLocalPlayer",
      "getRunService",
      "isActive",
      "observeConfig",
      "trackGlobal",
      "untrackGlobal",
    },
    GameInfo = {
      "areAbilitiesEnabled",
      "getFierceDeflectAbility",
      "getSnapshotAt",
      "getParrySnapshot",
      "isSnapshotValid",
      "getBallFrozen",
      "getAveragePing",
    },
    Cooldown = { "getDeflectCooldownState" },
    AutoParry = { "beginFierce", "cancelFierce", "getTiming" },
    Remote = { "fireFierce" },
    AutoSpam = { "stopSpam" },
  },
  provides = { "setup", "teardown" },
}

return AutoFierce
