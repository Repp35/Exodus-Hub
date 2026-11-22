-- [[ autofierce ]]

-- code
local AutoFierce = {}
local utils
local gameInfo
local geometry
local cooldown
local remote
local autoParry
local autoSpam
local generation = 0
local pending = false
local lastEpisode, errorAt = 0, -math.huge
local function enabled() return utils and utils.isActive() and utils.getConfigValue("AutoFierce") == true and gameInfo.areAbilitiesEnabled() end
local function fierceReady()
  local ability = gameInfo.getFierceDeflectAbility()
  if
    type(ability) ~= "table"
    or type(ability.ActivateAndBlock) ~= "function"
    or type(ability.Cooldown) ~= "number"
    or ability.Cooldown ~= ability.Cooldown
    or math.abs(ability.Cooldown) == math.huge
    or ability.Cooldown > 0
  then
    return false
  end
  if type(ability.IsOwnerAlive) == "function" and not ability:IsOwnerAlive() then return false end
  return type(ability.IsAvailable) ~= "function" or ability:IsAvailable(false)
end
local function eligible()
  if not enabled() or not fierceReady() then return nil end
  local now = os.clock(); local value = gameInfo.getDefenseSnapshot(now)
  local player = utils.getLocalPlayer(); local character = player and player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart"); local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  if
    not value
    or value.mode == "training"
    or not player
    or value.targetId ~= player.UserId
    or not root
    or not root.Parent
    or not humanoid
    or humanoid.Health <= 0
  then
    return nil
  end
  local t = geometry.getParryTiming(value, root.Position, {
    factor = 0.3,
    ping = gameInfo.getAveragePing(),
    frameLead = 1 / 60,
    rootVelocity = root.AssemblyLinearVelocity,
  })
  if not t or not t.ready or (not t.approaching and t.timeToKill ~= 0) then return nil end
  local recovery = cooldown.getDeflectRecoveryState(t.timeToKill, 1 / 60)
  if not recovery or not recovery.needsFierce then return nil end
  local observedCooldown = recovery.cooldown; local episode = observedCooldown.episode
  if type(episode) ~= "number" or episode <= lastEpisode then return nil end
  return value, episode
end
local function update()
  if pending then return end
  local value, episode = eligible()
  if not value then return end
  local owner, token = generation, nil; local boundParry = autoParry
  pending = true
  local ok, sent = pcall(remote.fireFierce, function()
    if owner ~= generation then return false end
    local current, currentEpisode = eligible()
    if not current or current.ball ~= value.ball or currentEpisode ~= episode then return false end
    if not token then token = boundParry.beginFierce(); autoSpam.stopSpam("fierce_rescue") end
    return true
  end)
  if owner ~= generation then return end
  pending = false
  if ok and sent == true then lastEpisode = episode else boundParry.cancelFierce(token) end
  if not ok and os.clock() - errorAt >= 1 then errorAt = os.clock(); utils.recordError("AutoFierce", tostring(sent)) end
end
local function safeUpdate()
  local ok, detail = pcall(update)
  if not ok and utils and os.clock() - errorAt >= 1 then errorAt = os.clock(); utils.recordError("AutoFierce", tostring(detail)) end
end
function AutoFierce.setup(deps)
  if type(deps) ~= "table" then return false, "dependências ausentes" end
  for _, name in ipairs({ "Utils", "GameInfo", "DeflectGeometry", "Cooldown", "Remote", "AutoParry", "AutoSpam" }) do
    if type(deps[name]) ~= "table" then return false, "dependência ausente: " .. name end
  end
  AutoFierce.teardown()
  utils, gameInfo, geometry, cooldown, remote, autoParry, autoSpam =
    deps.Utils, deps.GameInfo, deps.DeflectGeometry, deps.Cooldown, deps.Remote, deps.AutoParry, deps.AutoSpam
  return true
end
function AutoFierce.onBallSync()
  safeUpdate(); return true
end
function AutoFierce.teardown()
  generation += 1; pending, lastEpisode, errorAt = false, 0, -math.huge
  utils, gameInfo, geometry, cooldown, remote, autoParry, autoSpam = nil, nil, nil, nil, nil, nil, nil
end
AutoFierce.__contract = {
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    DeflectGeometry = "deflectgeometry",
    Cooldown = "cooldown",
    Remote = "remote",
    AutoParry = "autoparry",
    AutoSpam = "autospam",
  },
  requiresMethods = {
    Utils = { "isActive", "getConfigValue", "getLocalPlayer", "recordError" },
    GameInfo = { "getDefenseSnapshot", "getAveragePing", "areAbilitiesEnabled", "getFierceDeflectAbility" },
    DeflectGeometry = { "getParryTiming" },
    Cooldown = { "getDeflectRecoveryState", "observeDeflect" },
    Remote = { "fireFierce" },
    AutoParry = { "beginFierce", "cancelFierce" },
    AutoSpam = { "stopSpam" },
  },
  provides = { "setup", "teardown", "onBallSync" },
}

return AutoFierce
