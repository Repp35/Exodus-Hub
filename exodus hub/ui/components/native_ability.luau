-- [[ native ability ]]
--!optimize 2
-- @modules uinativeability

local Ability = {}
local Runtime
function Ability.setup(deps)
  Runtime = deps.Runtime
  return true
end
function Ability.create(ability, options)
  options = options or {}
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
  then
    return
  end
  local scope = Runtime.scope()
  local clone = original:Clone()
  clone.Name = options.name or "ExodusNativeAbility"
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
  local animations = options.animations
  local visible = original.Visible
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
  clone.Parent = original.Parent
  original.Visible = false
  if animations then
    animations:Bind(button)
  end
  for _, property in ipairs({ "Size", "Position", "AnchorPoint", "Rotation", "LayoutOrder" }) do
    scope.connect(original:GetPropertyChangedSignal(property), function()
      if clone.Parent then
        clone[property] = original[property]
      end
    end)
  end
  for _, property in ipairs({ "Size", "Position", "AnchorPoint", "Rotation" }) do
    local source = references.MobileUIAbilityButton
    scope.connect(source:GetPropertyChangedSignal(property), function()
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
  if options.onPress then
    scope.connect(button.InputBegan, options.onPress)
  end
  local handle = { original = original, clone = clone, button = button, image = image, state = state }
  function handle.setState(on, mobile)
    original.Visible = false
    clone.Visible = mobile
    state.Text = on and "ON" or "OFF"
    state.TextColor3 = Color3.new(1, 1, 1)
    image.Image, image.Visible = "", false
    local body = on and Color3.fromRGB(24, 157, 73) or Color3.fromRGB(180, 34, 46)
    button.ImageColor3 = button.ImageColor3:Lerp(body, 0.65)
    if button.BackgroundTransparency < 1 then
      button.BackgroundColor3 = button.BackgroundColor3:Lerp(body, 0.65)
    end
  end
  scope.add(function()
    if animations then
      pcall(animations.Unbind, animations, button)
    end
    for key, value in pairs(references) do
      if interface[key] == replacements[key] then
        interface[key] = value
      end
    end
    if original.Parent then
      original.Visible = visible
    end
    clone:Destroy()
  end)
  function handle.destroy() scope.destroy() end
  return handle
end
function Ability.reveal(ability)
  local frame = ability and ability.Interface and ability.Interface.MobileUIAbilityFrame
  if frame and frame.Parent then
    frame.Visible = true
  end
end
Ability.__contract = { provides = { "setup", "create", "reveal" }, requires = { Runtime = "uiruntime" }, requiresMethods = { Runtime = { "scope" } } }
return Ability
