-- [[ header ]]
--!optimize 2
-- @modules uiheader

local Header = {}
function Header.setup() return true end
function Header.create(context, parent)
  local T, inst = context.theme, context.inst
  local gap, buttonGap, buttonSize = 12, 6, 30
  local icon = inst("ImageLabel", {
    Name = "HubIcon",
    Position = UDim2.fromOffset(T.PAD, (T.TITLE_H - 28) / 2),
    Size = UDim2.fromOffset(28, 28),
    BackgroundTransparency = 1,
    ImageColor3 = Color3.new(1, 1, 1),
    ScaleType = Enum.ScaleType.Fit,
    Visible = false,
    ZIndex = 7,
  }, parent)
  local title = inst("Frame", { Name = "HeaderText", BackgroundTransparency = 1, ClipsDescendants = true, Active = true, ZIndex = 7 }, parent)
  local brand = inst("TextLabel", {
    Name = "Brand",
    BackgroundTransparency = 1,
    Text = context.brand.name .. (context.hub.version and (" | v" .. context.hub.version) or ""),
    RichText = false,
    TextColor3 = T.COLORS.text,
    TextSize = T.TITLE_TEXT_SIZE,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 7,
  }, title)
  local author = inst("TextLabel", {
    Name = "Author",
    BackgroundTransparency = 1,
    Text = "— " .. context.brand.author,
    TextColor3 = T.COLORS.text,
    TextTransparency = T.AUTHOR_TRANSPARENCY,
    TextSize = T.AUTHOR_TEXT_SIZE,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 7,
  }, title)
  local buttons = inst("ScrollingFrame", {
    Name = "HeaderButtons",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -T.PAD, 0.5, -18),
    AnchorPoint = Vector2.new(1, 0),
    Size = UDim2.fromOffset(0, 38),
    CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.X,
    ScrollBarThickness = 0,
    ScrollBarImageColor3 = T.COLORS.subtext,
    Active = true,
    ClipsDescendants = true,
    ZIndex = 9,
  }, parent)
  inst("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, buttonGap),
  }, buttons)
  inst("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2) }, buttons)
  local function refresh()
    local count = 0
    for _, child in ipairs(buttons:GetChildren()) do
      if child:IsA("GuiButton") and child.Visible then
        count += 1
      end
    end
    local contentWidth = math.max(0, count * buttonSize + math.max(0, count - 1) * buttonGap + 4)
    local available = math.floor(T.PANEL_W * 0.35)
    local controlsWidth = math.min(contentWidth, available)
    buttons.Size, buttons.CanvasSize = UDim2.fromOffset(controlsWidth, 38), UDim2.fromOffset(contentWidth, 0)
    buttons.ScrollingEnabled = contentWidth > controlsWidth
    buttons.ScrollBarThickness = buttons.ScrollingEnabled and 2 or 0
    if not buttons.ScrollingEnabled then
      buttons.CanvasPosition = Vector2.new(0, 0)
    end
    local left = T.PAD + (icon.Visible and 28 + gap or 0)
    local width = math.max(0, T.PANEL_W - T.PAD - controlsWidth - gap - left)
    title.Position, title.Size = UDim2.fromOffset(left, 0), UDim2.fromOffset(width, T.TITLE_H)
    local plain = context.brand.name .. (context.hub.version and (" | v" .. context.hub.version) or "")
    local bounds = game:GetService("TextService"):GetTextSize(plain, T.TITLE_TEXT_SIZE, Enum.Font.GothamBlack, Vector2.new(10000, T.TITLE_H))
    local brandWidth = math.min(width, math.ceil(bounds.X) + 2)
    brand.Size = UDim2.fromOffset(brandWidth, T.TITLE_H)
    author.Position = UDim2.fromOffset(brandWidth + T.TITLE_SPACING, 0)
    author.Size = UDim2.fromOffset(math.max(0, width - brandWidth - T.TITLE_SPACING), T.TITLE_H)
    author.Visible = author.Size.X.Offset > 24
  end
  local function addButton(button)
    button.Size = UDim2.fromOffset(buttonSize, buttonSize)
    context.scope.connect(button:GetPropertyChangedSignal("Visible"), refresh)
    refresh()
  end
  context.scope.connect(buttons.ChildAdded, function(child)
    if child:IsA("GuiButton") then
      addButton(child)
    end
  end)
  context.scope.connect(buttons.ChildRemoved, refresh)
  refresh()
  return {
    buttons = buttons,
    title = title,
    icon = icon,
    setIcon = function(image)
      icon.Image, icon.Visible = image or "", image ~= nil
      refresh()
    end,
    refresh = refresh,
  }
end
Header.__contract = { provides = { "setup", "create" }, requires = {} }
return Header
