-- [[ mini ]]
--!optimize 2
-- @modules uimini

local Mini = {}
function Mini.setup() return true end
local function surface(context, parent, definition)
  local inst, kit, C = context.inst, context.kit, context.C
  if not definition.panel then
    local size = definition.size or context.Theme.CLASH_SIZE
    local button = inst("TextButton", {
      Name = definition.name or "MiniUI",
      Size = UDim2.fromOffset(size, size),
      Position = UDim2.fromOffset(-size - 40, 0),
      BackgroundColor3 = C.red,
      BackgroundTransparency = 1,
      TextTransparency = 1,
      Text = "",
      TextColor3 = Color3.new(1, 1, 1),
      TextSize = definition.textSize or 14,
      Font = Enum.Font.GothamBold,
      Active = true,
      Visible = false,
      ZIndex = 8,
    }, parent)
    local radius = kit.corner(button, 999)
    local outline = kit.stroke(button, nil, 2)
    outline.Transparency = 1
    return button, button, button, radius, outline
  end
  local root = inst("CanvasGroup", {
    Name = definition.name or "ExodusSpamMini",
    Visible = false,
    GroupTransparency = 1,
    Size = UDim2.fromOffset(context.Theme.MINI_W, context.Theme.MINI_H),
    BackgroundColor3 = C.header,
    ZIndex = 15,
  }, parent)
  local radius = kit.corner(root, 14)
  kit.corner(
    inst("Frame", {
      Size = UDim2.new(1, 8, 1, 8),
      Position = UDim2.fromOffset(-4, -4),
      BackgroundColor3 = C.accent,
      BackgroundTransparency = 0.92,
      ZIndex = 14,
    }, root),
    18
  )
  local outline = kit.stroke(root, nil, 1.5)
  local header = inst("Frame", {
    Size = UDim2.new(1, 0, 0.22, 0),
    BackgroundColor3 = Color3.fromRGB(20, 20, 46),
    BackgroundTransparency = 0.05,
    ZIndex = 16,
  }, root)
  kit.corner(header, 14)
  inst("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Color3.fromRGB(20, 20, 46),
    BackgroundTransparency = 0.05,
    ZIndex = 16,
  }, header)
  kit.corner(
    inst("Frame", {
      Size = UDim2.new(0.5, 0, 0, 2),
      Position = UDim2.new(0.25, 0, 0, 0),
      BackgroundColor3 = C.accentPink,
      ZIndex = 17,
    }, header),
    1
  )
  inst("TextLabel", {
    Size = UDim2.new(1, -16, 1, 0),
    Position = UDim2.fromOffset(8, 0),
    BackgroundTransparency = 1,
    Text = definition.title or "Spam",
    TextColor3 = C.subtext,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Center,
    Font = Enum.Font.GothamBold,
    ZIndex = 17,
  }, header)
  local button = inst("TextButton", {
    Name = "SpamButton",
    Size = UDim2.new(1, -12, 0.78, -8),
    Position = UDim2.new(0, 6, 0.22, 3),
    BackgroundColor3 = C.red,
    Text = "OFF",
    TextColor3 = Color3.new(1, 1, 1),
    TextScaled = true,
    Font = Enum.Font.GothamBold,
    ZIndex = 16,
  }, root)
  kit.corner(button, 10)
  inst("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 12 }, button)
  return root, button, header, radius, outline
end
function Mini.install(context)
  function context.components.mini(parent, definition)
    definition = definition or {}
    local kit, C = context.kit, context.C
    local actionButton = definition.action == true
      or (
        definition.action == nil
        and definition.key == nil
        and definition.value == nil
        and definition.onActivate ~= nil
        and definition.onText == nil
        and definition.offText == nil
      )
    local scope = context.Runtime.scope()
    local motion = context.Runtime.motion(scope)
    local root, button, header, radius, outline = surface(context, parent, definition)
    local handle = { Root = root, Header = header, Button = button, scope = scope, enabled = true }
    local clickScale
    if actionButton then
      clickScale = context.inst("UIScale", { Scale = 1 }, button)
    end
    local current, shown, invisible, revision = nil, false, false, 0
    local shape = "round"
    local width = definition.panel and context.Theme.MINI_W or (definition.size or context.Theme.CLASH_SIZE)
    local height = definition.panel and context.Theme.MINI_H or width
    local target = definition.position or UDim2.fromOffset(14, 160)
    local hiddenX = definition.panel and ((workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 1920) + 30) or -width - 40
    root.Position = UDim2.fromOffset(hiddenX, target.Y.Offset)
    local tint, offColor = definition.color or definition.onColor or C.green, definition.offColor or (actionButton and definition.color) or C.red
    local caption = definition.text or definition.title or ""
    local onText = definition.onText or (actionButton and caption or (caption ~= "" and caption .. "\nON" or "ON"))
    local offText = definition.offText or (actionButton and caption or (caption ~= "" and caption .. "\nOFF" or "OFF"))
    local dragStart, initial, dragged, held
    local sizeScale = 1
    local function paint(immediate)
      button.Text = current and onText or offText
      if not definition.panel then
        button.TextSize = (current and (definition.onTextSize or definition.textSize or 14) or (definition.offTextSize or definition.textSize or 14))
          * sizeScale
      end
      local color = current and tint or offColor
      if immediate then
        button.BackgroundColor3 = color
      else
        motion.play(button, "control", { BackgroundColor3 = color })
      end
    end
    function handle.pulse()
      local pressed = definition.panel and UDim2.new(1, -14, 0.78, -12) or UDim2.fromOffset(width - 6, height - 6)
      local restored = definition.panel and UDim2.new(1, -12, 0.78, -8) or UDim2.fromOffset(width, height)
      motion.play(button, "press", { Size = pressed }, function() motion.play(button, "feedback", { Size = restored }) end)
    end
    function handle.click()
      if not clickScale then
        return
      end
      motion.play(clickScale, "press", { Scale = 0.9 }, function()
        motion.play(clickScale, "feedback", { Scale = 1.04 }, function() motion.play(clickScale, "control", { Scale = 1 }) end)
      end)
    end
    function handle.setValue(value)
      value = value == true
      if current == value then
        return
      end
      local first = current == nil
      current = value
      paint(first)
      if definition.panel and not first then
        handle.pulse()
      end
    end
    function handle.getValue() return current end
    function handle.setColor(value)
      assert(typeof(value) == "Color3", "Mini UI color must be Color3")
      tint = value
      if actionButton then
        offColor = value
      end
      paint(false)
    end
    function handle.setDimensions(x, y)
      assert(type(x) == "number" and x == x and math.abs(x) < math.huge and type(y) == "number" and y == y and math.abs(y) < math.huge, "Invalid Mini UI size")
      x, y = math.max(1, x), math.max(1, y)
      if x == width and y == height then
        return
      end
      width, height = x, y
      sizeScale = width / (definition.size or context.Theme.CLASH_SIZE)
      motion.play(root, "feedback", { Size = UDim2.fromOffset(width, height) })
      paint(false)
    end
    function handle.setSize(value)
      assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid Mini UI size")
      value = math.clamp(value, 28, 384)
      handle.setDimensions(value, definition.panel and value * context.Theme.MINI_H / context.Theme.MINI_W or value)
    end
    function handle.setShape(value)
      assert(value == "square" or value == "round", "Mini UI shape must be square or round")
      if shape == value or definition.panel then
        return
      end
      shape = value
      motion.play(radius, "control", { CornerRadius = UDim.new(0, shape == "round" and 999 or 12) })
    end
    function handle.setAppearance(scale, square)
      scale = math.clamp(tonumber(scale) or 1, 0.5, 2)
      handle.setShape(square == true and "square" or "round")
      if definition.panel then
        handle.setDimensions(context.Theme.MINI_W * scale, context.Theme.MINI_H * scale)
      else
        handle.setSize((definition.size or context.Theme.CLASH_SIZE) * scale)
      end
    end
    local function fade(value)
      local alpha = value and not invisible and 0 or 1
      if definition.panel then
        return motion.group(root, "panel", { GroupTransparency = alpha })
      end
      motion.play(outline, "panel", { Transparency = alpha })
      return motion.play(button, "panel", { TextTransparency = alpha, BackgroundTransparency = alpha })
    end
    function handle.setInvisible(value)
      value = value == true
      if value == invisible then
        return
      end
      invisible = value
      if shown then
        fade(true)
      end
    end
    function handle.setPosition(position, offscreenX)
      if target == position and hiddenX == offscreenX then
        return
      end
      target, hiddenX = position, offscreenX or hiddenX
      if shown then
        motion.play(root, "feedback", { Position = target })
      else
        root.Position = UDim2.fromOffset(hiddenX, target.Y.Offset)
      end
    end
    function handle.setVisible(value)
      value = value == true
      if shown == value then
        return
      end
      shown, revision = value, revision + 1
      local version = revision
      if value then
        root.Visible = true
      end
      motion.play(root, "panel", { Position = value and target or UDim2.fromOffset(hiddenX, target.Y.Offset) })
      local tween = fade(value)
      local function complete()
        if revision == version and root.Parent then
          root.Visible = value
        end
      end
      if tween then
        local connection
        connection = scope.connect(tween.Completed, function(state)
          scope.remove(connection)
          if state == Enum.PlaybackState.Completed then
            complete()
          end
        end)
      else
        complete()
      end
      if not value and held then
        held = nil
        if definition.onRelease then
          definition.onRelease()
        end
      end
    end
    function handle.setEnabled(value)
      handle.enabled = value == true
      button.Active, button.Selectable = handle.enabled, handle.enabled
    end
    function handle.setText(value)
      onText, offText = tostring(value), tostring(value)
      paint(false)
    end
    function handle.isDragging() return dragged == true end
    local function available() return handle.enabled and not kit.suspended and shown end
    if definition.draggable ~= false then
      context.Runtime.bindDrag(scope, header, function(input)
        if not dragStart then
          dragStart, initial, dragged = input.Position, root.Position, false
          return
        end
        local delta = input.Position - dragStart
        if delta.X * delta.X + delta.Y * delta.Y < context.Theme.DRAG_THRESHOLD_SQ and not dragged then
          return
        end
        dragged = true
        local scale = math.max(0.01, root.AbsoluteSize.X / math.max(1, root.Size.X.Offset))
        local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or parent.AbsoluteSize
        root.Position = UDim2.fromOffset(
          math.clamp(initial.X.Offset + delta.X / scale, 0, math.max(0, view.X / scale - root.Size.X.Offset)),
          math.clamp(initial.Y.Offset + delta.Y / scale, 0, math.max(0, view.Y / scale - root.Size.Y.Offset))
        )
        target = root.Position
      end, available)
    end
    scope.connect(button.InputBegan, function(input)
      if available() and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
        held = input
        if definition.onPress then
          definition.onPress(input)
        end
      end
    end)
    local function release(input)
      if held and (input == nil or input == held) then
        held = nil
        if definition.onRelease then
          definition.onRelease(input)
        end
      end
      if not input or input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if dragStart and dragged and definition.onDragEnd then
          definition.onDragEnd(root.Position)
        end
        dragStart, initial = nil, nil
      end
    end
    scope.connect(context.UIS.InputEnded, release)
    scope.connect(context.UIS.WindowFocusReleased, function() release(nil) end)
    scope.connect(button.Activated, function()
      if not available() or handle.isDragging() then
        return
      end
      if definition.key then
        local value = not current
        if not context.commit(handle, definition, value) then
          return
        end
        handle.setValue(value)
      end
      if actionButton then
        handle.click()
      elseif definition.pulse then
        handle.pulse()
      end
      if definition.onActivate then
        definition.onActivate()
      end
    end)
    function handle.destroy()
      release(nil)
      scope.destroy()
      root:Destroy()
    end
    handle.setShape(definition.shape or "round")
    if definition.key then
      handle.setValue(context.read(definition.key, definition.value))
      context.bind(handle, definition.key, handle.setValue)
    else
      handle.setValue(definition.value)
    end
    if definition.scaleKey or definition.squareKey then
      local function appearance() handle.setAppearance(context.read(definition.scaleKey, 1), context.read(definition.squareKey, false)) end
      if definition.scaleKey then
        context.bind(handle, definition.scaleKey, appearance)
      end
      if definition.squareKey then
        context.bind(handle, definition.squareKey, appearance)
      end
      appearance()
    end
    handle.setVisible(definition.visible ~= false)
    scope.connect(root.Destroying, function()
      release(nil)
      scope.destroy()
    end)
    scope.add(function() kit.scope.forget(handle) end)
    kit.scope.add(handle, handle.destroy)
    return handle
  end
end
Mini.__contract = { provides = { "setup", "install" }, requires = {} }
return Mini
