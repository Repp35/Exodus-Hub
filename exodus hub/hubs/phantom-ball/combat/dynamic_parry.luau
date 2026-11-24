-- [[ dynamic parry ]]

-- code
local Dynamic = {}
local utils
local gameInfo
local cooldownInfo
local remote
local connections, uiConnections = {}, {}
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
  disconnect(uiConnections)
  if not binding then
    return
  end
  local old = binding
  binding = nil
  if old.animations then
    pcall(old.animations.Unbind, old.animations, old.button)
  end
  for key, value in pairs(old.references) do
    if old.interface[key] == old.replacements[key] then
      old.interface[key] = value
    end
  end
  if old.ability.OnKeyDown == old.hook then
    old.ability.OnKeyDown = old.keyDown
  end
  if old.original.Parent then
    old.original.Visible = old.visible
  end
  if old.clone then
    old.clone:Destroy()
  end
end
local function attach(ability)
  local interface = ability and ability.Interface
  local original = interface and interface.MobileUIAbilityFrame
  local sourceButton = interface and interface.MobileUIAbilityButton
  local sourceImage = interface and interface.MobileUIAbilityImage
  if
    not original
    or not original.Parent
    or not sourceButton
    or not sourceImage
    or not sourceButton:IsA("ImageButton")
    or not sourceButton:IsDescendantOf(original)
    or not sourceImage:IsDescendantOf(original)
    or type(ability.OnKeyDown) ~= "function"
  then
    return
  end
  if binding and binding.ability == ability and binding.original == original and binding.clone.Parent then
    return
  end
  restore()
  local clone = original:Clone()
  clone.Name = "ExodusDynamicParry"
  for _, item in ipairs(clone:GetDescendants()) do
    if item:IsA("LuaSourceContainer") then
      item:Destroy()
    end
  end
  local function counterpart(item)
    if item == original then
      return clone
    end
    local path = {}
    local node = item
    while node and node ~= original do
      table.insert(path, 1, node.Name)
      node = node.Parent
    end
    if node ~= original then
      return nil
    end
    local target = clone
    for _, name in ipairs(path) do
      target = target and target:FindFirstChild(name)
    end
    return target
  end
  local references, replacements = {}, {}
  for key, value in pairs(interface) do
    if typeof(value) == "Instance" and (value == original or value:IsDescendantOf(original)) then
      local target = counterpart(value)
      if target then
        references[key], replacements[key], interface[key] = value, target, target
      end
    end
  end
  local button, image = interface.MobileUIAbilityButton, interface.MobileUIAbilityImage
  image.Image = ""
  image.Visible = false
  for _, item in ipairs(clone:GetDescendants()) do
    if item:IsA("TextLabel") or item:IsA("TextButton") then
      item.Text = ""
    end
  end
  local animations = gameInfo.getNativeButtonAnimations()
  local oldKey = ability.OnKeyDown
  local function hook(self, input, processed)
    local service = game:GetService("UserInputService")
    local desktop = service.KeyboardEnabled or service.MouseEnabled or not service.TouchEnabled or utils.getConfigValue("ForcePCUI") == true
    if enabled() and desktop and matches(input) then
      return
    end
    return oldKey(self, input, processed)
  end
  local visible = original.Visible
  binding = {
    ability = ability,
    interface = interface,
    original = original,
    clone = clone,
    visible = visible,
    references = references,
    replacements = replacements,
    keyDown = oldKey,
    hook = hook,
    button = button,
    image = image,
    animations = animations,
  }

  ability.OnKeyDown = hook
  local state = button:FindFirstChild("Label")
  if not state or not state:IsA("TextLabel") then
    state = Instance.new("TextLabel")
    state.Font = Enum.Font.GothamBold
    state.Parent = button
  end
  state.Name = "DynamicState"
  state.BackgroundTransparency = 1
  state.AnchorPoint = Vector2.new(0.5, 0.5)
  state.Position = UDim2.fromScale(0.5, 0.5)
  state.Size = UDim2.fromScale(0.8, 0.5)
  state.TextScaled = true
  state.TextColor3 = Color3.new(1, 1, 1)
  state.Text = "OFF"
  state.ZIndex = button.ZIndex + 5
  state.Visible = true
  binding.state = state
  clone.Parent = original.Parent
  original.Visible = false
  if animations then
    animations:Bind(button)
  end
  for _, property in ipairs({ "Size", "Position", "AnchorPoint", "Rotation", "LayoutOrder" }) do
    connect(uiConnections, original:GetPropertyChangedSignal(property), function()
      if clone.Parent then
        clone[property] = original[property]
      end
    end)
  end
  for _, property in ipairs({ "Size", "Position", "AnchorPoint", "Rotation" }) do
    local source = references.MobileUIAbilityButton
    connect(uiConnections, source:GetPropertyChangedSignal(property), function()
      if not clone.Parent then
        return
      end
      if animations then
        animations:Unbind(button)
      end
      button[property] = source[property]
      if animations then
        animations:Bind(button)
      end
    end)
  end
  connect(uiConnections, button.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
      press(input)
    end
  end)
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
      local ability = gameInfo.getDeflectAbility()
      local frame = ability and ability.Interface and ability.Interface.MobileUIAbilityFrame
      if frame and frame.Parent then
        frame.Visible = true
      end
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
      if binding.original.Visible then
        binding.original.Visible = false
      end
      local mobile = input.TouchEnabled and not input.KeyboardEnabled and not input.GamepadEnabled and utils.getConfigValue("ForcePCUI") ~= true
      if binding.clone.Visible ~= mobile then
        binding.clone.Visible = mobile
      end
      local on = active or held ~= nil or os.clock() < pulseUntil
      local label = on and "ON" or "OFF"
      if binding.state.Text ~= label then
        binding.state.Text = label
      end
      local white = Color3.new(1, 1, 1)
      if binding.state.TextColor3 ~= white then
        binding.state.TextColor3 = white
      end
      if binding.image.Image ~= "" then
        binding.image.Image = ""
      end
      if binding.image.Visible then
        binding.image.Visible = false
      end
      local body = on and Color3.fromRGB(24, 157, 73) or Color3.fromRGB(180, 34, 46)
      if binding.button.ImageColor3 ~= body then
        binding.button.ImageColor3 = binding.button.ImageColor3:Lerp(body, 0.65)
      end
      if binding.button.BackgroundTransparency < 1 then
        binding.button.BackgroundColor3 = binding.button.BackgroundColor3:Lerp(body, 0.65)
      end
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
  },
  requiresMethods = {
    Utils = { "setDynamicSpamActive", "isDynamicSpamActive", "getConfigValue", "isActive", "getLocalPlayer", "getPlayers", "getRunService", "observeConfig" },
    GameInfo = { "getDeflectAbility", "getAveragePing", "getNativeButtonAnimations", "getSnapshotAt", "getBallSpeedLimits", "getPlayerMotion" },
    Cooldown = { "getDeflectCooldownState" },
    Remote = { "fireNativeParry" },
  },
  provides = { "setup", "teardown", "canSend", "getStatus" },
}

return Dynamic
