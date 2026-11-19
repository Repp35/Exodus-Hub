-- [[ dynamic parry ]]

-- code
local Dynamic = {}
local utils, gameInfo, autoSpam, remote
local connections, uiConnections = {}, {}
local binding, session, held, pressedAt, protectedUntil
local editing = false
local lastStopReason
local active, pulseUntil, epoch = false, 0, 0
local function enabled() return utils and utils.isActive() and utils.getConfigValue("DynamicParry") == true end
local function connect(list, signal, callback)
  local c = signal:Connect(callback); list[#list + 1] = c
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
  if utils then utils.setDynamicSpamActive(false) end
end
local function matches(input)
  local key = utils.getConfigValue("DynamicParryKey"); return key ~= nil and key ~= Enum.KeyCode.Unknown and (input.KeyCode == key or input.UserInputType == key)
end
local function press(input)
  if not enabled() or editing or held then return end
  if active then stop(); return end
  held, pressedAt, pulseUntil = input, os.clock(), os.clock() + 0.12; local owner = epoch
  remote.fireNativeParry(function() return enabled() and epoch == owner end)
  task.delay(0.18, function()
    if epoch ~= owner or not held or not enabled() then return end
    session = autoSpam.createManualSession()
    if not session then return end
    local ping = gameInfo.getAveragePing(); protectedUntil = os.clock() + 0.3 + math.max(0, tonumber(ping) or 0)
    active = true; utils.setDynamicSpamActive(true)
  end)
end
local function release(input)
  if not held or (input ~= held and not matches(input)) then return end
  held = nil; epoch += 1
  if utils.getConfigValue("DynamicParryMode") == "Hold" then stop() end
end
local function restore()
  disconnect(uiConnections)
  if not binding then return end
  local old = binding; binding = nil
  if old.animations then pcall(old.animations.Unbind, old.animations, old.button) end
  for key, value in pairs(old.references) do
    if old.interface[key] == old.replacements[key] then old.interface[key] = value end
  end
  if old.ability.OnKeyDown == old.hook then old.ability.OnKeyDown = old.keyDown end
  if old.original.Parent then old.original.Visible = old.visible end
  if old.clone then old.clone:Destroy() end
end
local function attach(ability)
  local interface = ability and ability.Interface; local original = interface and interface.MobileUIAbilityFrame
  if not original or not original.Parent then return end
  if binding and binding.ability == ability and binding.original == original and binding.clone.Parent then return end
  restore(); local clone = original:Clone()
  clone.Name = "ExodusDynamicParry"
  for _, item in ipairs(clone:GetDescendants()) do
    if item:IsA("LuaSourceContainer") then item:Destroy() end
  end
  local function counterpart(item)
    if item == original then return clone end
    local path = {}; local node = item
    while node and node ~= original do
      table.insert(path, 1, node.Name); node = node.Parent
    end
    if node ~= original then return nil end
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
      if target then references[key], replacements[key], interface[key] = value, target, target end
    end
  end
  local button, image = interface.MobileUIAbilityButton, interface.MobileUIAbilityImage; image.Image = ""
  image.Visible = false
  for _, item in ipairs(clone:GetDescendants()) do
    if item:IsA("TextLabel") or item:IsA("TextButton") then item.Text = "" end
  end
  local animations = gameInfo.getNativeButtonAnimations(); local oldKey = ability.OnKeyDown
  local function hook(self, input, processed)
    local service = game:GetService("UserInputService"); local desktop = service.KeyboardEnabled or service.MouseEnabled or not service.TouchEnabled or utils.getConfigValue("ForcePCUI") == true
    if enabled() and desktop and matches(input) then return end
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

  ability.OnKeyDown = hook; local state = button:FindFirstChild("Label")
  if not state or not state:IsA("TextLabel") then
    state = Instance.new("TextLabel"); state.Font = Enum.Font.GothamBold
    state.Parent = button
  end
  state.Name = "DynamicState"; state.BackgroundTransparency = 1
  state.AnchorPoint = Vector2.new(0.5, 0.5); state.Position = UDim2.fromScale(0.5, 0.5)
  state.Size = UDim2.fromScale(0.8, 0.5); state.TextScaled = true
  state.TextColor3 = Color3.new(1, 1, 1); state.Text = "OFF"
  state.ZIndex = button.ZIndex + 5; state.Visible = true
  binding.state = state; clone.Parent = original.Parent
  original.Visible = false
  if animations then animations:Bind(button) end
  for _, property in ipairs({ "Size", "Position", "AnchorPoint", "Rotation", "LayoutOrder" }) do
    connect(uiConnections, original:GetPropertyChangedSignal(property), function()
      if clone.Parent then clone[property] = original[property] end
    end)
  end
  for _, property in ipairs({ "Size", "Position", "AnchorPoint", "Rotation" }) do
    local source = references.MobileUIAbilityButton
    connect(uiConnections, source:GetPropertyChangedSignal(property), function()
      if not clone.Parent then return end
      if animations then animations:Unbind(button) end
      button[property] = source[property]
      if animations then animations:Bind(button) end
    end)
  end
  connect(uiConnections, button.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then press(input) end
  end)
end
function Dynamic.canSend()
  if not active then return false end
  if not enabled() or not utils.isDynamicSpamActive() then stop(); return false end
  local player = utils.getLocalPlayer(); local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
  if not humanoid or humanoid.Health <= 0 then stop(); return false end
  if utils.getConfigValue("DynamicParryDeactivation") ~= false then
    local reason, allowed = autoSpam.getManualStopReason(session, protectedUntil)
    if reason then
      if reason ~= "player_died" and reason ~= "match_player_died" and reason ~= "opponent_left_or_died" then lastStopReason = reason end
      stop(); return false
    end
    return allowed ~= false
  end
  return true
end
function Dynamic.setup(deps)
  Dynamic.teardown(); utils, gameInfo, autoSpam, remote = deps.Utils, deps.GameInfo, deps.AutoSpam, deps.Remote
  local input = game:GetService("UserInputService")
  connect(connections, input.InputBegan, function(event, processed)
    local desktop = input.KeyboardEnabled or input.MouseEnabled or not input.TouchEnabled or utils.getConfigValue("ForcePCUI") == true
    if desktop and not processed and not input:GetFocusedTextBox() and matches(event) then press(event) end
  end)
  local player = utils.getLocalPlayer()
  local function updateEditing()
    local value = player:GetAttribute("MobileLayoutEditing") == true
    if value and not editing then
      held = nil; epoch += 1
      stop(); restore()
      local ability = gameInfo.getDeflectAbility(); local frame = ability and ability.Interface and ability.Interface.MobileUIAbilityFrame
      if frame and frame.Parent then frame.Visible = true end
    end
    editing = value
  end
  connect(connections, player:GetAttributeChangedSignal("MobileLayoutEditing"), updateEditing); updateEditing()
  connect(connections, input.InputEnded, release)
  connect(connections, input.WindowFocusReleased, function()
    held = nil; epoch += 1
    stop()
  end)
  connections[#connections + 1] = utils.observeConfig(function(changes)
    if changes.DynamicParry ~= nil or changes.DynamicParryKey ~= nil or changes.DynamicParryMode ~= nil then
      held = nil; epoch += 1
      stop(); restore()
    end
  end)
  connect(connections, utils.getRunService().Heartbeat, function()
    if not enabled() then
      held = nil; epoch += 1
      stop(); restore()
      return
    end
    if editing then return end
    local ability = gameInfo.getDeflectAbility()
    if not ability then
      stop(); restore()
      return
    end
    if binding and binding.ability == ability then
      if not binding.original.Parent or not binding.clone.Parent then
        held = nil; epoch += 1
        stop(); restore()
      end
    else
      held = nil; epoch += 1
      stop(); attach(ability)
    end
    if not binding then attach(ability) end
    if active then Dynamic.canSend() end
    if binding then
      binding.original.Visible = false; local mobile = input.TouchEnabled and not input.KeyboardEnabled and not input.GamepadEnabled and utils.getConfigValue("ForcePCUI") ~= true
      binding.clone.Visible = mobile; local on = active or held ~= nil or os.clock() < pulseUntil
      binding.state.Text = on and "ON" or "OFF"; binding.state.TextColor3 = Color3.new(1, 1, 1)
      binding.image.Image = ""; binding.image.Visible = false
      local body = on and Color3.fromRGB(24, 157, 73) or Color3.fromRGB(180, 34, 46); binding.button.ImageColor3 = binding.button.ImageColor3:Lerp(body, 0.65)
      if binding.button.BackgroundTransparency < 1 then binding.button.BackgroundColor3 = binding.button.BackgroundColor3:Lerp(body, 0.65) end
    end
  end)
  if enabled() and not editing then attach(gameInfo.getDeflectAbility()) end
  return true
end
function Dynamic.teardown()
  epoch += 1; held = nil
  stop(); restore()
  disconnect(connections); utils, gameInfo, autoSpam, remote = nil, nil, nil, nil
end
function Dynamic.getStatus()
  return { active = active, held = held ~= nil, protectedUntil = protectedUntil, attached = binding ~= nil, lastStopReason = lastStopReason }
end
Dynamic.__contract = {
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    AutoSpam = "autospam",
    Remote = "remote",
  },
  requiresMethods = {
    Utils = { "setDynamicSpamActive", "isDynamicSpamActive", "getConfigValue", "isActive", "getLocalPlayer", "getRunService", "observeConfig" },
    GameInfo = { "getDeflectAbility", "getAveragePing", "getNativeButtonAnimations" },
    AutoSpam = { "createManualSession", "getManualStopReason" },
    Remote = { "fireNativeParry" },
  },
  provides = { "setup", "teardown", "canSend", "getStatus" },
}

return Dynamic
