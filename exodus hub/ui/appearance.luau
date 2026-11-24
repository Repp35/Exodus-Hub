-- [[ shared surface appearance ]]
--!optimize 2
-- @modules uiappearance

local Appearance = {}
function Appearance.setup() return true end
function Appearance.borderColor(background, light)
  local hue, saturation, value = background:ToHSV()
  local brightness = value + (1 - value) * 0.16
  return Color3.fromHSV(hue, saturation, brightness)
end
local function instance(class, properties, parent)
  local object = Instance.new(class)
  for key, value in pairs(properties) do
    object[key] = value
  end
  object.Parent = parent
  return object
end
local function palette(kind)
  if kind == "critical" then
    return Color3.fromRGB(153, 27, 27)
  end
  if kind == "success" then
    return Color3.fromRGB(20, 92, 58)
  end
  if kind == "warning" then
    return Color3.fromRGB(100, 67, 18)
  end
  return Color3.fromRGB(45, 55, 130)
end
function Appearance.notification(parent, name)
  local card = instance("CanvasGroup", {
    Name = name,
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, 18),
    Size = UDim2.fromOffset(80, 26),
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    GroupTransparency = 1,
    ClipsDescendants = true,
    ZIndex = 100,
  }, parent)
  instance("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
  local outline = instance("Frame", {
    Name = "Outline",
    Size = UDim2.new(1, -2, 1, -2),
    Position = UDim2.fromOffset(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 102,
  }, card)
  instance("UICorner", { CornerRadius = UDim.new(0, 9) }, outline)
  instance("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, outline)
  local content = instance("ScrollingFrame", {
    Name = "Content",
    Size = UDim2.new(1, -20, 1, -12),
    Position = UDim2.fromOffset(10, 6),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(),
    ScrollBarThickness = 0,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Active = true,
    ClipsDescendants = true,
    ZIndex = 101,
  }, card)
  instance("TextLabel", {
    Name = "Message",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 1, 0),
    Text = "",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    TextWrapped = true,
    TextTruncate = Enum.TextTruncate.None,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    RichText = false,
    ZIndex = 101,
  }, content)
  return card
end
function Appearance.updateNotification(card, message, kind, viewport)
  local content = card:FindFirstChild("Content")
  -- Replace cards created by older loaders rather than retain an incompatible layout.
  assert(content and content:IsA("ScrollingFrame"), "Unsupported notification surface")
  local label = content:FindFirstChild("Message")
  local maxWidth = math.max(24, math.min(280, viewport.X - 24))
  local padding = math.min(10, math.max(2, (maxWidth - 4) / 4))
  local measure = game:GetService("TextService")
  local value = tostring(message)
  local function bounds(width) return measure:GetTextSize(value, 11, Enum.Font.GothamMedium, Vector2.new(math.max(1, width), 100000)) end
  local size = bounds(maxWidth - padding * 2)
  local width = math.min(maxWidth, math.max(math.min(80, maxWidth), math.ceil(size.X) + padding * 2 + 2))
  size = bounds(width - padding * 2)
  local maxHeight = math.max(26, viewport.Y - 48)
  local height = math.min(maxHeight, math.max(26, math.ceil(size.Y) + 14))
  local overflow = size.Y + 12 > height
  if overflow then
    size = bounds(width - padding * 2 - 4)
  end
  card.Size = UDim2.fromOffset(width, height)
  card.BackgroundColor3 = palette(kind)
  card.BackgroundTransparency = 0.12
  local outline = card:FindFirstChild("Outline")
  outline:FindFirstChildOfClass("UIStroke").Color = Appearance.borderColor(card.BackgroundColor3)
  content.Position = UDim2.fromOffset(padding, 6)
  content.Size = UDim2.new(1, -padding * 2, 1, -12)
  content.ScrollingEnabled, content.ScrollBarThickness = overflow, overflow and 2 or 0
  content.ScrollBarImageColor3 = Color3.new(1, 1, 1)
  content.CanvasSize = UDim2.fromOffset(0, math.ceil(size.Y) + 2)
  content.CanvasPosition = Vector2.new(0, 0)
  label.Text = value
  label.Size = UDim2.new(1, overflow and -4 or 0, 0, math.max(height - 12, math.ceil(size.Y) + 2))
  return card
end
Appearance.__contract = { provides = { "setup", "borderColor", "notification", "updateNotification" }, requires = {} }
return Appearance
