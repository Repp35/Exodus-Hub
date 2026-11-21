-- [[ autofierce ]]

-- module
local AutoFierce = {}
local deflectGeometry
local utils, gameInfo, remote, autoParry, cooldownInfo, autoSpam
local connections = {}
local lastFierceEpisode, localUserId
local pendingEpisode
local hookedAbility, hookedRaw, hookedWrapper
local epoch = 0
local errorAt = -math.huge

-- configuration
local CONFIG = {
  SYNC_MAX_AGE = 0.25,
  WINDOW_FACTOR = 0.3,
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
  local snapshot = gameInfo.getSnapshotAt(now)
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
local function currentInWindow(snapshot)
  local player = utils.getLocalPlayer(); local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  if not root or not root.Parent or typeof(snapshot.position) ~= "Vector3" then return false end
  local speed = snapshot.syncSpeed or snapshot.speed
  if not finite(speed) or speed < 16 or speed > 1000 then return false end
  local geometry = deflectGeometry.getAutoParryGeometry(speed, CONFIG.WINDOW_FACTOR, 0, 0)
  if not geometry or not finite(geometry.fullRadius) or geometry.fullRadius <= 0 then return false end
  local distance = (snapshot.position - root.Position).Magnitude; return finite(distance) and distance <= geometry.fullRadius
end
local function confirmedMiss(cooldown)
  return cooldown ~= nil
    and (cooldown.source == "local" or cooldown.source == "server")
    and cooldown.miss == true
    and cooldown.blocking == true
    and finite(cooldown.remaining)
    and cooldown.remaining > 0
    and finite(cooldown.episode)
    and cooldown.episode > 0
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
  if not enabled() or not fierceReady() or not confirmedMiss(cooldown) then return end
  local snapshot = validTargetSnapshot(now)
  if not snapshot or not currentInWindow(snapshot) or cooldown.episode <= lastFierceEpisode then return end
  local episode, ball, token = cooldown.episode, snapshot.ball, nil; local owner = epoch
  pendingEpisode = episode
  local ok, sent = pcall(function()
    return remote.fireFierce(function()
      if owner ~= epoch or not enabled() or not fierceReady() then return false end
      local currentSnapshot = validTargetSnapshot(os.clock())
      if not currentSnapshot or currentSnapshot.ball ~= ball then return false end
      local current = cooldownInfo.getDeflectCooldownState()
      if not confirmedMiss(current) or current.episode ~= episode or not currentInWindow(currentSnapshot) then return false end
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
  unhookManualFierce()
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
    DeflectGeometry = { "getAutoParryGeometry" },
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
      "isSnapshotValid",
      "getBallFrozen",
    },
    Cooldown = { "getDeflectCooldownState" },
    AutoParry = { "beginFierce", "cancelFierce" },
    Remote = { "fireFierce" },
    AutoSpam = { "stopSpam" },
  },
  provides = { "setup", "teardown" },
}

return AutoFierce
