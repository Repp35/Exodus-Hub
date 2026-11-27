-- [[ dynamic parry ]]
--!optimize 2

-- code
local Dynamic = {}
local utils
local gameInfo
local cooldownInfo
local remote
local connections = {}
local nativeAbility
local binding
local session
local held
local protectedUntil
local editing = false
local lastStopReason
local active = false
local pulseUntil = 0
local epoch = 0
local function enabled() return utils and utils.isActive() and utils.getConfigValue("DynamicParry") == true end
local function connect(list, signal, callback)
  local c = signal:Connect(callback)
  list[#list + 1] = c
  return c
end
local function disconnect(list)
  for _, c in ipairs(list) do
    c:Disconnect()
  end
  table.clear(list)
end
local function stop()
  active, session = false, nil
  if utils then
    utils.setDynamicSpamActive(false)
  end
end
local function finite(x) return type(x) == "number" and x == x and x > -math.huge and x < math.huge end
local function cooldownExpired(time)
  local cd = cooldownInfo.getDeflectCooldownState()
  if not cd or cd.source == "unknown" or cd.blocking ~= true or cd.predictedReset == true then
    session.cooldownSince, session.cooldownEpisode = nil, nil
    return false
  end
  if finite(cd.lastParriedAt) and cd.lastParriedAt ~= session.cooldownParriedAt then
    session.cooldownParriedAt, session.cooldownSince = cd.lastParriedAt, time
  end
  if not session.cooldownSince or (cd.episode ~= nil and session.cooldownEpisode ~= cd.episode) then
    session.cooldownSince = finite(cd.blockingSince) and cd.blockingSince <= time and cd.blockingSince or time
    session.cooldownEpisode = cd.episode
  end
  local s = gameInfo.getSnapshotAt(time)
  local speed = s and (s.syncSpeed ~= nil and s.syncSpeed or s.speed)
  speed = finite(speed) and math.clamp(speed, 0, 1000) or 0
  local low, high = gameInfo.getBallSpeedLimits()
  local progress = finite(low) and finite(high) and high > low and math.clamp((speed - low) / (high - low), 0, 1) or 0
  local near = false
  for _, player in ipairs(utils.getPlayers():GetPlayers()) do
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local position = player.UserId ~= utils.getLocalPlayer().UserId and gameInfo.getPlayerMotion(player.UserId)
    local lives = player:GetAttribute("Lives")
    if
      position
      and humanoid
      and humanoid.Health > 0
      and player:GetAttribute("Playing") ~= false
      and (not finite(lives) or lives > 0)
      and (position - session.root.Position).Magnitude <= 10 + 6 * progress
    then
      near = true
      break
    end
  end
  local ping = gameInfo.getAveragePing()
  local latency = finite(ping) and math.clamp(ping * 0.5, 0, 0.25) or 0
  local limit = 0.225 - 0.125 * progress + latency + (near and 0.12 or 0)
  return time - session.cooldownSince >= limit
end
local function matches(input)
  local key = utils.getConfigValue("DynamicParryKey")
  return key ~= nil and key ~= Enum.KeyCode.Unknown and (input.KeyCode == key or input.UserInputType == key)
end
local function press(input)
  if not enabled() or editing or held then
    return
  end
  if active then
    stop()
    return
  end
  held, pulseUntil = input, os.clock() + 0.12
  local owner = epoch
  remote.fireNativeParry(function() return enabled() and epoch == owner end)
  task.delay(0.18, function()
    if epoch ~= owner or not held or not enabled() then
      return
    end
    local player = utils.getLocalPlayer()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    session = root and { character = character, root = root }
    if not session then
      return
    end
    local ping = gameInfo.getAveragePing()
    protectedUntil = os.clock() + 0.3 + math.max(0, tonumber(ping) or 0)
    active = true
    utils.setDynamicSpamActive(true)
  end)
end
local function release(input)
  if not held or (input ~= held and not matches(input)) then
    return
  end
  held = nil
  epoch += 1
  if utils.getConfigValue("DynamicParryMode") == "Hold" then
    stop()
  end
end
local function restore()
  if not binding then
    return
  end
  local old = binding
  binding = nil
  if old.ability.OnKeyDown == old.hook then
    old.ability.OnKeyDown = old.keyDown
  end
  old.view.destroy()
end
local function attach(ability)
  if not ability or type(ability.OnKeyDown) ~= "function" then
    return
  end
  local original = ability.Interface and ability.Interface.MobileUIAbilityFrame
  if binding and binding.ability == ability and binding.original == original and binding.clone.Parent then
    return
  end
  restore()
  local view = nativeAbility.create(ability, {
    name = "ExodusDynamicParry",
    animations = gameInfo.getNativeButtonAnimations(),
    onPress = function(input)
      if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        press(input)
      end
    end,
  })
  if not view then
    return
  end
  local oldKey = ability.OnKeyDown
  local function hook(self, input, processed)
    local service = game:GetService("UserInputService")
    local desktop = service.KeyboardEnabled or service.MouseEnabled or not service.TouchEnabled or utils.getConfigValue("ForcePCUI") == true
    if enabled() and desktop and matches(input) then
      return
    end
    return oldKey(self, input, processed)
  end
  binding = { ability = ability, original = view.original, clone = view.clone, view = view, hook = hook, keyDown = oldKey }
  ability.OnKeyDown = hook
end
function Dynamic.canSend()
  if not active then
    return false
  end
  if not enabled() or not utils.isDynamicSpamActive() then
    stop()
    return false
  end
  local player = utils.getLocalPlayer()
  local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
  if not humanoid or humanoid.Health <= 0 then
    stop()
    return false
  end
  if not session or player.Character ~= session.character or not session.root.Parent or not session.character.Parent then
    stop()
    return false
  end
  if utils.getConfigValue("DynamicParryDeactivation") ~= false then
    local time = os.clock()
    local expired = cooldownExpired(time)
    if expired and time >= (protectedUntil or 0) then
      lastStopReason = "cooldown"
      stop()
      return false
    end
  end
  return true
end
function Dynamic.setup(deps)
  Dynamic.teardown()
  utils, gameInfo, cooldownInfo, remote = deps.Utils, deps.GameInfo, deps.Cooldown, deps.Remote
  nativeAbility = deps.NativeAbility
  local input = game:GetService("UserInputService")
  connect(connections, input.InputBegan, function(event, processed)
    local desktop = input.KeyboardEnabled or input.MouseEnabled or not input.TouchEnabled or utils.getConfigValue("ForcePCUI") == true
    if desktop and not processed and not input:GetFocusedTextBox() and matches(event) then
      press(event)
    end
  end)
  local player = utils.getLocalPlayer()
  local function updateEditing()
    local value = player:GetAttribute("MobileLayoutEditing") == true
    if value and not editing then
      held = nil
      epoch += 1
      stop()
      restore()
      nativeAbility.reveal(gameInfo.getDeflectAbility())
    end
    editing = value
  end
  connect(connections, player:GetAttributeChangedSignal("MobileLayoutEditing"), updateEditing)
  updateEditing()
  connect(connections, input.InputEnded, release)
  connect(connections, input.WindowFocusReleased, function()
    held = nil
    epoch += 1
    stop()
  end)
  connections[#connections + 1] = utils.observeConfig(function(changes)
    if changes.DynamicParry ~= nil or changes.DynamicParryKey ~= nil or changes.DynamicParryMode ~= nil then
      held = nil
      epoch += 1
      stop()
      restore()
    end
  end)
  connect(connections, utils.getRunService().Heartbeat, function()
    if not enabled() then
      held = nil
      epoch += 1
      stop()
      restore()
      return
    end
    if editing then
      return
    end
    local ability = gameInfo.getDeflectAbility()
    if not ability then
      stop()
      restore()
      return
    end
    if binding and binding.ability == ability then
      if not binding.original.Parent or not binding.clone.Parent then
        held = nil
        epoch += 1
        stop()
        restore()
      end
    else
      held = nil
      epoch += 1
      stop()
      attach(ability)
    end
    if not binding then
      attach(ability)
    end
    if active then
      Dynamic.canSend()
    end
    if binding then
      local mobile = input.TouchEnabled and not input.KeyboardEnabled and not input.GamepadEnabled and utils.getConfigValue("ForcePCUI") ~= true
      binding.view.setState(active or held ~= nil or os.clock() < pulseUntil, mobile)
    end
  end)
  if enabled() and not editing then
    attach(gameInfo.getDeflectAbility())
  end
  return true
end
function Dynamic.teardown()
  epoch += 1
  held = nil
  stop()
  restore()
  disconnect(connections)
  utils, gameInfo, cooldownInfo, remote = nil, nil, nil, nil
end
function Dynamic.getStatus()
  return { active = active, held = held ~= nil, protectedUntil = protectedUntil, attached = binding ~= nil, lastStopReason = lastStopReason }
end
Dynamic.__contract = {
  access = { methods = { canSend = "combat.runtime" } },
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    Cooldown = "cooldown",
    Remote = "remote",
    NativeAbility = "uinativeability",
  },
  requiresMethods = {
    Utils = { "setDynamicSpamActive", "isDynamicSpamActive", "getConfigValue", "isActive", "getLocalPlayer", "getPlayers", "getRunService", "observeConfig" },
    GameInfo = { "getDeflectAbility", "getAveragePing", "getNativeButtonAnimations", "getSnapshotAt", "getBallSpeedLimits", "getPlayerMotion" },
    Cooldown = { "getDeflectCooldownState" },
    Remote = { "fireNativeParry" },
    NativeAbility = { "create", "reveal" },
  },
  provides = { "setup", "teardown", "canSend", "getStatus" },
}

return Dynamic
