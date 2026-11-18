-- [[ dynamic parry ]]

-- code
local Dynamic = {}
local utils, gameInfo, autoSpam, remote
local connections, uiConnections = {}, {}
local binding, session, held, pressedAt, protectedUntil
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
  if not enabled() or held then return end
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
  restore(); local clone = Instance.new("Frame")
  clone.Name = "ExodusDynamicParry"; clone.Size, clone.Position, clone.AnchorPoint = original.Size, original.Position, original.AnchorPoint
  clone.LayoutOrder, clone.ZIndex, clone.BackgroundTransparency = original.LayoutOrder, original.ZIndex, 1; local button = Instance.new("TextButton")
  button.Name = "DynamicButton"; button.Size = UDim2.fromScale(1, 1)
  button.Text = ""; button.AutoButtonColor = false
  button.Selectable = true; button.BackgroundColor3 = Color3.fromRGB(160, 32, 43)
  button.BackgroundTransparency = 0.08; button.BorderSizePixel = 0
  button.ZIndex = clone.ZIndex + 1; button.Parent = clone
  local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0.24, 0)
  corner.Parent = button; local outline = Instance.new("UIStroke")
  outline.Thickness = 2; outline.Color = Color3.fromRGB(255, 80, 95)
  outline.Parent = button; local image = Instance.new("ImageLabel")
  image.Name = "ParryIcon"; image.BackgroundTransparency = 1
  image.AnchorPoint = Vector2.new(0.5, 0); image.Position = UDim2.fromScale(0.5, 0.08)
  image.Size = UDim2.fromScale(0.64, 0.57); image.ScaleType = Enum.ScaleType.Fit
  image.Image = interface.MobileUIAbilityImage.Image; image.ImageColor3 = Color3.new(1, 1, 1)
  image.ZIndex = button.ZIndex + 2; image.Parent = button
  local clipping = Instance.new("Frame"); clipping.Name = "CooldownClipping"
  clipping.BackgroundTransparency = 1; clipping.Size = UDim2.fromScale(1, 1)
  clipping.ClipsDescendants = true; clipping.ZIndex = button.ZIndex + 1
  clipping.Parent = button; local cooldown = Instance.new("Frame")
  cooldown.Name = "Cooldown"; cooldown.AnchorPoint = Vector2.new(0, 1)
  cooldown.Position = UDim2.fromScale(0, 1); cooldown.Size = UDim2.fromScale(1, 0)
  cooldown.BackgroundColor3 = Color3.new(0, 0, 0); cooldown.BackgroundTransparency = 0.45
  cooldown.BorderSizePixel = 0; cooldown.ZIndex = clipping.ZIndex
  cooldown.Parent = clipping; local flash = Instance.new("Frame")
  flash.Name = "RecoveryFlash"; flash.Size = UDim2.fromScale(1, 1)
  flash.BackgroundColor3 = Color3.new(1, 1, 1); flash.BackgroundTransparency = 1
  flash.BorderSizePixel = 0; flash.ZIndex = button.ZIndex + 3
  flash.Parent = button; local flashCorner = Instance.new("UICorner")
  flashCorner.CornerRadius = corner.CornerRadius; flashCorner.Parent = flash
  local references = {}
  local replacements = {
    MobileUIAbilityFrame = clone,
    MobileUIAbilityButton = button,
    MobileUIAbilityImage = image,
    MobileUIAbilityCooldown = cooldown,
    MobileUICooldownFlash = flash,
  }

  for key, value in pairs(replacements) do
    references[key], interface[key] = interface[key], value
  end
  local oldKey = ability.OnKeyDown
  local function hook(self, input, processed)
    if enabled() and matches(input) then return end
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
    outline = outline,
  }

  ability.OnKeyDown = hook; local state = Instance.new("TextLabel")
  state.Name = "DynamicState"; state.BackgroundTransparency = 1
  state.Size = UDim2.fromScale(1, 0.22); state.Position = UDim2.fromScale(0, 0.76)
  state.TextScaled = true; state.Font = Enum.Font.GothamBold
  state.TextColor3 = Color3.new(1, 1, 1); state.TextStrokeTransparency = 0.25
  state.ZIndex = button.ZIndex + 5; state.Parent = button
  binding.state = state; clone.Parent = original.Parent
  original.Visible = false
  connect(uiConnections, button.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then press(input) end
  end)
  local scale = Instance.new("UIScale"); scale.Parent = button
  binding.scale = scale
end
function Dynamic.canSend()
  if not active then return false end
  if not enabled() or not utils.isDynamicSpamActive() then stop(); return false end
  local player = utils.getLocalPlayer(); local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
  if not humanoid or humanoid.Health <= 0 then stop(); return false end
  if utils.getConfigValue("DynamicParryDeactivation") ~= false then
    local reason = autoSpam.getManualStopReason(session, protectedUntil)
    if reason then stop(); return false end
  end
  return true
end
function Dynamic.setup(deps)
  Dynamic.teardown(); utils, gameInfo, autoSpam, remote = deps.Utils, deps.GameInfo, deps.AutoSpam, deps.Remote
  local input = game:GetService("UserInputService")
  connect(connections, input.InputBegan, function(event, processed)
    if not processed and not input:GetFocusedTextBox() and matches(event) then press(event) end
  end)
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
      binding.original.Visible = false; local mobile = input.TouchEnabled and not input.KeyboardEnabled and not input.MouseEnabled
      binding.clone.Visible = mobile; local on = active or held ~= nil or os.clock() < pulseUntil
      binding.state.Text = on and "ON" or "OFF"; binding.state.TextColor3 = Color3.new(1, 1, 1)
      local body = on and Color3.fromRGB(24, 157, 73) or Color3.fromRGB(160, 32, 43); local edge = on and Color3.fromRGB(105, 255, 150) or Color3.fromRGB(255, 80, 95)
      binding.button.BackgroundColor3 = binding.button.BackgroundColor3:Lerp(body, 0.65); binding.outline.Color = binding.outline.Color:Lerp(edge, 0.65)
      local target = held and 0.93 or 1; binding.scale.Scale += (target - binding.scale.Scale) * 0.6
    end
  end)
  if enabled() then attach(gameInfo.getDeflectAbility()) end
  return true
end
function Dynamic.teardown()
  epoch += 1; held = nil
  stop(); restore()
  disconnect(connections); utils, gameInfo, autoSpam, remote = nil, nil, nil, nil
end
function Dynamic.getStatus() return { active = active, held = held ~= nil, protectedUntil = protectedUntil, attached = binding ~= nil } end
Dynamic.__contract = {
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    AutoSpam = "autospam",
    Remote = "remote",
  },
  requiresMethods = {
    Utils = { "setDynamicSpamActive", "isDynamicSpamActive", "getConfigValue", "isActive", "getLocalPlayer", "getRunService", "observeConfig" },
    GameInfo = { "getDeflectAbility", "getAveragePing" },
    AutoSpam = { "createManualSession", "getManualStopReason" },
    Remote = { "fireNativeParry" },
  },
  provides = { "setup", "teardown", "canSend", "getStatus" },
}

return Dynamic
