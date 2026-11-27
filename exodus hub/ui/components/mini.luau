-- [[ mini ]]
--!optimize 2
-- @modules uimini

local Mini = {}
function Mini.setup() return true end
function Mini.install(context)
  function context.components.mini(parent, definition)
    definition = definition or {}
    local kit, C = context.kit, context.C
    local scope = context.Runtime.scope()
    local motion = context.Runtime.motion(scope)
    local root = context.inst("CanvasGroup", {
      Name = definition.name or "MiniUI",
      BackgroundTransparency = 1,
      Position = definition.position or UDim2.fromOffset(14, 160),
      Size = UDim2.fromOffset(64, 64),
      GroupTransparency = 1,
      Visible = false,
      ZIndex = 8,
    }, parent)
    local button = context.inst("TextButton", {
      Name = "Action",
      Size = UDim2.fromScale(1, 1),
      BackgroundColor3 = C.card,
      Text = "",
      AutoLocalize = false,
      Active = true,
      ZIndex = 8,
    }, root)
    local radius = kit.corner(button, 12)
    local outline = kit.stroke(button, definition.color or C.accent, 2)
    local label = context.inst("TextLabel", {
      Name = "Caption",
      Size = UDim2.new(1, -12, 1, -12),
      Position = UDim2.fromOffset(6, 6),
      BackgroundTransparency = 1,
      Text = definition.text or definition.title or "Action",
      AutoLocalize = false,
      TextColor3 = C.text,
      Font = context.Theme.FONT.strong,
      TextSize = 12,
      TextWrapped = true,
      ZIndex = 9,
    }, button)
    local check = context.inst("TextLabel", {
      Name = "Active",
      AnchorPoint = Vector2.new(1, 0),
      Position = UDim2.new(1, -4, 0, 2),
      Size = UDim2.fromOffset(18, 18),
      BackgroundTransparency = 1,
      Text = "✓",
      AutoLocalize = false,
      TextColor3 = C.text,
      Font = context.Theme.FONT.strong,
      TextSize = 16,
      TextTransparency = 1,
      ZIndex = 10,
    }, button)
    local pressScale = context.inst("UIScale", { Scale = 1 }, button)
    button.AnchorPoint, button.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
    local handle = { Root = root, Header = button, Button = button, scope = scope, enabled = true }
    local current, shown, invisible, revision = nil, false, false, 0
    local baseSize, shape, tint = 0, "square", definition.color or C.accent
    local dragStart, initial, dragged, held
    local function paint()
      motion.play(button, "control", { BackgroundColor3 = current and tint or (definition.offColor or C.card) })
      motion.play(check, "control", { TextTransparency = current and 0 or 1 })
      motion.play(outline, "control", { Color = current and tint or (definition.offColor or C.border) })
    end
    function handle.setValue(value)
      value = value == true
      if current == value then
        return
      end
      current = value
      paint()
    end
    function handle.getValue() return current end
    function handle.setColor(value)
      assert(typeof(value) == "Color3", "Mini UI color must be Color3")
      if tint == value then
        return
      end
      tint = value
      paint()
    end
    function handle.setSize(value)
      assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid Mini UI size")
      value = math.clamp(value, 28, 192)
      if value == baseSize then
        return
      end
      baseSize = value
      motion.play(root, "control", { Size = UDim2.fromOffset(baseSize, baseSize) })
      motion.play(radius, "control", { CornerRadius = shape == "round" and UDim.new(0.5, 0) or UDim.new(0, math.min(14, baseSize * 0.2)) })
      motion.play(label, "control", { TextSize = math.clamp(baseSize * 0.19, 9, 24) })
    end
    function handle.setShape(value)
      assert(value == "square" or value == "round", "Mini UI shape must be square or round")
      if shape == value then
        return
      end
      shape = value
      local size = baseSize
      baseSize = 0
      handle.setSize(size)
    end
    function handle.setAppearance(scale, square)
      handle.setShape(square == false and "round" or "square")
      handle.setSize((definition.size or 64) * math.clamp(tonumber(scale) or 1, 0.5, 2))
    end
    function handle.setInvisible(value)
      value = value == true
      if value == invisible then
        return
      end
      invisible = value
      if not shown then
        return
      end
      motion.group(root, "panel", { GroupTransparency = shown and not invisible and 0 or 1 })
    end
    function handle.setVisible(value)
      value = value == true
      if value == shown then
        return
      end
      shown, revision = value, revision + 1
      local version = revision
      if value then
        root.Visible = true
      end
      motion.group(root, "panel", { GroupTransparency = value and not invisible and 0 or 1 }, function()
        if revision == version then
          root.Visible = value
        end
      end)
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
    function handle.setText(value) label.Text = tostring(value) end
    function handle.pulse()
      motion.play(pressScale, "press", { Scale = 0.91 }, function() motion.play(pressScale, "feedback", { Scale = 1 }) end)
    end
    local function available() return handle.enabled and not kit.suspended and shown end
    if definition.draggable ~= false then
      context.Runtime.bindDrag(scope, button, function(input)
        if not dragStart then
          dragStart, initial, dragged = input.Position, root.Position, false
          return
        end
        local delta = input.Position - dragStart
        if delta.Magnitude < 8 and not dragged then
          return
        end
        dragged = true
        if held then
          held = nil
          if definition.onRelease then
            definition.onRelease()
          end
        end
        local scale = math.max(0.01, root.AbsoluteSize.X / math.max(1, root.Size.X.Offset))
        local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or parent.AbsoluteSize
        root.Position = UDim2.fromOffset(
          math.clamp(initial.X.Offset + delta.X / scale, 0, math.max(0, view.X / scale - root.Size.X.Offset)),
          math.clamp(initial.Y.Offset + delta.Y / scale, 0, math.max(0, view.Y / scale - root.Size.Y.Offset))
        )
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
      if not available() or dragged then
        return
      end
      if definition.key then
        local value = not current
        if not context.commit(handle, definition, value) then
          return
        end
        handle.setValue(value)
      end
      handle.pulse()
      if definition.onActivate then
        definition.onActivate()
      end
    end)
    function handle.destroy()
      release(nil)
      scope.destroy()
      root:Destroy()
    end
    handle.setSize(definition.size or 64)
    handle.setShape(definition.shape or "square")
    if definition.key then
      handle.setValue(context.read(definition.key, definition.value))
      context.bind(handle, definition.key, handle.setValue)
    else
      handle.setValue(definition.value)
    end
    if definition.scaleKey or definition.squareKey then
      local function appearance() handle.setAppearance(context.read(definition.scaleKey, 1), context.read(definition.squareKey, true)) end
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
