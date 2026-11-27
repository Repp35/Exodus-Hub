-- [[ notification ]]
--!optimize 2
-- @modules uicornernotification

local Notification = {}
function Notification.setup() return true end
function Notification.create(context)
  local inst, C = context.inst, context.theme.COLORS
  local scope = context.scope.child()
  local cards, order, sequence = {}, {}, 0
  local layer = inst("Frame", {
    Name = "CornerNotifications",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 110,
  }, context.notifications.layer())
  scope.add(function() layer:Destroy() end)
  local function reflow()
    local view = context.viewport()
    local width = math.max(1, math.min(320, view.X - 24))
    local height = math.max(1, math.min(88, (view.Y - 48) / 3))
    for index, id in ipairs(order) do
      local card = cards[id]
      card.Root.Size = UDim2.fromOffset(width, height)
      context.twPlay(card.Root, "control", { Position = UDim2.new(1, -12, 1, -12 - (index - 1) * (height + 8)), GroupTransparency = 0 })
    end
  end
  local function dismiss(id)
    local card = cards[id]
    if not card then
      return
    end
    cards[id] = nil
    table.remove(order, table.find(order, id))
    context.twPlay(card.Root, "control", { Position = UDim2.new(1, card.Root.Size.X.Offset + 12, 1, card.Root.Position.Y.Offset), GroupTransparency = 1 })
    local timer = task.delay(0.35, function()
      card.scope.forget("exit")
      card.scope.destroy()
    end)
    card.scope.add("exit", function() task.cancel(timer) end)
    reflow()
  end
  local function show(title, message, options)
    if not scope.alive then
      return false
    end
    options = options or {}
    if not context.deps.NotificationPolicy.shouldShow(context.deps.Utils.getConfig(), context.state.desktop, { category = "system", topic = options.id }) then
      return false
    end
    sequence += 1
    local id = options.id or sequence
    dismiss(id)
    while #order >= 3 do
      dismiss(order[#order])
    end
    local owner = scope.child()
    local root = inst("CanvasGroup", {
      Name = "Notification",
      AnchorPoint = Vector2.new(1, 1),
      Position = UDim2.new(1, 340, 1, -12),
      BackgroundColor3 = C.card,
      BackgroundTransparency = 0.04,
      GroupTransparency = 1,
      ClipsDescendants = true,
      ZIndex = 110,
    }, layer)
    owner.add(function() root:Destroy() end)
    context.corner(root, 10)
    context.stroke(root, C.border, 1)
    local tint = options.kind == "warning" and C.red or options.kind == "success" and C.green or C.accent
    inst("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = tint, ZIndex = 111 }, root)
    inst("TextLabel", {
      Position = UDim2.fromOffset(14, 8),
      Size = UDim2.new(1, -48, 0, 22),
      BackgroundTransparency = 1,
      Text = tostring(title),
      TextColor3 = C.text,
      Font = context.theme.FONT.strong,
      TextSize = 13,
      TextTruncate = Enum.TextTruncate.AtEnd,
      TextXAlignment = Enum.TextXAlignment.Left,
      ZIndex = 111,
    }, root)
    local body = inst("ScrollingFrame", {
      Position = UDim2.fromOffset(14, 32),
      Size = UDim2.new(1, -28, 1, -38),
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
      Text = tostring(message),
      TextColor3 = C.subtext,
      Font = context.theme.FONT.body,
      TextSize = 12,
      TextWrapped = true,
      TextXAlignment = Enum.TextXAlignment.Left,
      ZIndex = 112,
    }, body)
    local close = inst("TextButton", {
      Position = UDim2.new(1, -32, 0, 6),
      Size = UDim2.fromOffset(26, 26),
      BackgroundTransparency = 1,
      Text = "×",
      TextColor3 = C.subtext,
      TextSize = 20,
      ZIndex = 113,
    }, root)
    cards[id] = { Root = root, scope = owner }
    table.insert(order, 1, id)
    owner.connect(close.Activated, function() dismiss(id) end)
    local timer = task.delay(math.clamp(tonumber(options.duration) or 5, 1, 60), function()
      owner.forget("timer")
      if cards[id] and cards[id].scope == owner then
        dismiss(id)
      end
    end)
    owner.add("timer", function() task.cancel(timer) end)
    reflow()
    return true
  end
  scope.connect(layer:GetPropertyChangedSignal("AbsoluteSize"), reflow)
  return { show = show, dismiss = dismiss, destroy = scope.destroy }
end
Notification.__contract = { provides = { "setup", "create" }, requires = {} }
return Notification
