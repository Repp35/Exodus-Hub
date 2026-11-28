-- [[ corner notification ]]
--!optimize 2
-- @modules uicornernotification

local Notification = {}
function Notification.setup() return true end
local function escape(value) return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;") end
local function render(message)
  if type(message) ~= "table" then
    return tostring(message or ""), tostring(message or ""), false
  end
  local rich, plain = {}, {}
  for _, part in ipairs(message) do
    local value = type(part) == "table" and tostring(part.text or "") or tostring(part)
    plain[#plain + 1] = value
    local text = escape(value)
    if type(part) == "table" and typeof(part.color) == "Color3" then
      local color = part.color
      text = string.format('<font color="rgb(%d,%d,%d)">%s</font>', math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255), text)
    end
    rich[#rich + 1] = text
  end
  return table.concat(rich), table.concat(plain), true
end
function Notification.create(context)
  local inst, C = context.inst, context.theme.COLORS
  local scope = context.scope.child()
  local cards, order, sequence = {}, {}, 0
  local layer =
    inst("Frame", { Name = "CornerNotifications", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 110 }, context.notifications.layer())
  scope.add(function() layer:Destroy() end)
  local function reflow()
    local offset = 14
    for _, id in ipairs(order) do
      local card = cards[id]
      local width = math.max(1, math.min(286, context.viewport().X - 28))
      local bounds = game:GetService("TextService"):GetTextSize(card.plain, 12, context.theme.FONT.body, Vector2.new(math.max(1, width - 30), 10000))
      local height = math.clamp(bounds.Y + 42, 64, 108)
      context.twPlay(card.Root, "control", { Size = UDim2.fromOffset(width, height) })
      context.twPlay(card.Root, "panel", { Position = UDim2.new(1, -14, 1, -offset), GroupTransparency = 0 })
      offset += height + 8
    end
  end
  local function dismiss(id)
    local card = cards[id]
    if not card then
      return false
    end
    cards[id] = nil
    table.remove(order, table.find(order, id))
    card.scope.remove("timer")
    context.twPlay(card.Root, "panel", {
      Position = UDim2.new(1, card.Root.Size.X.Offset + 16, 1, card.Root.Position.Y.Offset),
      GroupTransparency = 1,
    })
    local timer = task.delay(context.theme.MOTION.panel.duration, function()
      card.scope.forget("exit")
      card.scope.destroy()
    end)
    card.scope.add("exit", function() task.cancel(timer) end)
    reflow()
    return true
  end
  local function show(title, message, options)
    if not scope.alive then
      return false
    end
    options = options or {}
    if
      not context.deps.NotificationPolicy.shouldShow(
        context.deps.State.getConfig(),
        context.state.desktop,
        { category = options.important and "critical" or "system", topic = options.id, channel = "corner" }
      )
    then
      return false
    end
    sequence += 1
    local id = options.id or sequence
    dismiss(id)
    while #order >= 3 do
      dismiss(order[#order])
    end
    local text, plain, rich = render(options.segments or message)
    local width = math.max(1, math.min(286, context.viewport().X - 28))
    local bounds = game:GetService("TextService"):GetTextSize(plain, 12, context.theme.FONT.body, Vector2.new(math.max(1, width - 30), 10000))
    local height = math.clamp(bounds.Y + 42, 64, 108)
    local owner = scope.child()
    local root = inst("CanvasGroup", {
      Name = "Notice",
      AnchorPoint = Vector2.new(1, 1),
      Size = UDim2.fromOffset(width, height),
      Position = UDim2.new(1, width + 16, 1, -14),
      BackgroundColor3 = C.card,
      GroupTransparency = 1,
      ClipsDescendants = true,
      ZIndex = 110,
    }, layer)
    owner.add(function() root:Destroy() end)
    context.corner(root, 12)
    context.stroke(root, nil, 1)
    local tint = typeof(options.color) == "Color3" and options.color or options.kind == "warning" and C.red or options.kind == "success" and C.green or C.accent
    inst("TextLabel", {
      Position = UDim2.fromOffset(14, 7),
      Size = UDim2.new(1, -48, 0, 20),
      BackgroundTransparency = 1,
      Text = tostring(title),
      AutoLocalize = false,
      TextColor3 = C.text,
      Font = context.theme.FONT.strong,
      TextSize = 13,
      TextTruncate = Enum.TextTruncate.AtEnd,
      TextXAlignment = Enum.TextXAlignment.Left,
      ZIndex = 111,
    }, root)
    local body = inst("ScrollingFrame", {
      Position = UDim2.fromOffset(14, 30),
      Size = UDim2.new(1, -28, 1, -40),
      BackgroundTransparency = 1,
      CanvasSize = UDim2.new(),
      AutomaticCanvasSize = Enum.AutomaticSize.Y,
      ScrollBarThickness = 2,
      ZIndex = 111,
    }, root)
    inst("TextLabel", {
      Size = UDim2.new(1, -4, 0, 0),
      AutomaticSize = Enum.AutomaticSize.Y,
      BackgroundTransparency = 1,
      Text = text,
      RichText = rich,
      AutoLocalize = false,
      TextColor3 = C.text,
      Font = context.theme.FONT.body,
      TextSize = 12,
      TextWrapped = true,
      TextXAlignment = Enum.TextXAlignment.Left,
      ZIndex = 112,
    }, body)
    local track = inst(
      "Frame",
      { Position = UDim2.new(0, 12, 1, -6), Size = UDim2.new(1, -24, 0, 2), BackgroundColor3 = tint, BackgroundTransparency = 0.8, ZIndex = 111 },
      root
    )
    local line = inst("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = tint, ZIndex = 112 }, track)
    context.corner(track, 2)
    context.corner(line, 2)
    local close = inst("TextButton", {
      Position = UDim2.new(1, -30, 0, 4),
      Size = UDim2.fromOffset(26, 26),
      BackgroundTransparency = 1,
      Text = "×",
      AutoLocalize = false,
      TextColor3 = C.subtext,
      TextSize = 20,
      ZIndex = 113,
    }, root)
    cards[id] = { Root = root, scope = owner, plain = plain }
    table.insert(order, 1, id)
    owner.connect(close.Activated, function() dismiss(id) end)
    local duration = tonumber(options.duration) or 5
    if duration ~= duration or math.abs(duration) == math.huge then
      duration = 5
    end
    duration = math.clamp(duration, 0.5, 60)
    local timer = task.delay(context.theme.MOTION.panel.duration, function()
      owner.forget("timer")
      if not cards[id] or cards[id].scope ~= owner then
        return
      end
      local tween = game:GetService("TweenService"):Create(line, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
      owner.add(function() tween:Cancel() end)
      owner.connect(tween.Completed, function(status)
        if status == Enum.PlaybackState.Completed and cards[id] and cards[id].scope == owner then
          dismiss(id)
        end
      end)
      tween:Play()
    end)
    owner.add("timer", function() task.cancel(timer) end)
    reflow()
    return { id = id, dismiss = function() return dismiss(id) end }
  end
  scope.connect(layer:GetPropertyChangedSignal("AbsoluteSize"), reflow)
  return { show = show, dismiss = dismiss, destroy = scope.destroy }
end
Notification.__contract = { provides = { "setup", "create" }, requires = {} }
return Notification
