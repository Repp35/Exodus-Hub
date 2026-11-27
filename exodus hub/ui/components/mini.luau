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
    local base = definition.size or UDim2.fromOffset(context.Theme.CLASH_SIZE, context.Theme.CLASH_SIZE)
    local root = context.inst("TextButton", {
      Name = definition.name or "ExodusMini",
      Size = base,
      Position = definition.position or UDim2.fromOffset(14, 160),
      BackgroundColor3 = definition.color or C.accent,
      Text = definition.text or definition.title or "Action",
      TextColor3 = Color3.new(1, 1, 1),
      TextSize = definition.textSize or 15,
      Font = Enum.Font.GothamBold,
      Active = true,
      Visible = definition.visible ~= false,
      ZIndex = 8,
    }, parent)
    local radius = kit.corner(root, 999)
    local outline = kit.stroke(root, nil, 2)
    local handle = { Root = root, Header = root, Button = root, scope = scope, enabled = true }
    local current, start, initial, dragged
    local appearanceScale, square = definition.scale or 1, definition.square == true
    function handle.setAppearance(scale, squared)
      appearanceScale = math.clamp(tonumber(scale) or 1, 0.5, 2)
      square = squared == true
      root.Size = UDim2.fromOffset(base.X.Offset * appearanceScale, base.Y.Offset * appearanceScale)
      root:SetAttribute("ExodusMiniWidth", root.Size.X.Offset)
      root:SetAttribute("ExodusMiniHeight", root.Size.Y.Offset)
      root.TextSize = (definition.textSize or 15) * appearanceScale
      radius.CornerRadius = square and UDim.new(0, 12 * appearanceScale) or UDim.new(0.5, 0)
    end
    function handle.setInvisible(value)
      root.TextTransparency = value and 1 or 0
      root.BackgroundTransparency = value and 1 or 0
      outline.Transparency = value and 1 or 0
    end
    function handle.setVisible(value) root.Visible = value == true end
    function handle.setEnabled(value)
      handle.enabled = value == true
      root.Active, root.Selectable = handle.enabled, handle.enabled
    end
    function handle.setValue(value)
      current = value == true
      root.Text = current and (definition.onText or "ON") or (definition.offText or "OFF")
      root.BackgroundColor3 = current and C.green or C.red
    end
    function handle.getValue() return current end
    function handle.destroy()
      scope.destroy()
      root:Destroy()
    end
    if definition.draggable ~= false then
      context.Runtime.bindDrag(scope, root, function(input)
        if not start then
          start, initial, dragged = input.Position, root.Position, false
          return
        end
        local delta = input.Position - start
        if delta.Magnitude < 6 and not dragged then
          return
        end
        dragged = true
        local scale = math.max(0.01, root.AbsoluteSize.X / math.max(1, root.Size.X.Offset))
        local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or parent.AbsoluteSize
        root.Position = UDim2.fromOffset(
          math.clamp(initial.X.Offset + delta.X / scale, 0, math.max(0, view.X / scale - root.Size.X.Offset)),
          math.clamp(initial.Y.Offset + delta.Y / scale, 0, math.max(0, view.Y / scale - root.Size.Y.Offset))
        )
      end, function() return handle.enabled and not kit.suspended end)
      scope.connect(context.UIS.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
          if start and dragged and definition.onDragEnd then
            definition.onDragEnd(root.Position)
          end
          start, initial = nil, nil
        end
      end)
      scope.connect(context.UIS.WindowFocusReleased, function() start, initial, dragged = nil, nil, false end)
    end
    scope.connect(root.Activated, function()
      if kit.suspended or not handle.enabled or dragged then
        return
      end
      if definition.key then
        local value = not current
        if not context.commit(handle, definition, value) then
          return
        end
        handle.setValue(value)
      end
      if definition.onActivate then
        definition.onActivate()
      end
    end)
    if definition.enabled == false then
      handle.setEnabled(false)
    end
    handle.setAppearance(appearanceScale, square)
    if definition.key then
      handle.setValue(context.read(definition.key, definition.value))
      context.bind(handle, definition.key, handle.setValue)
    end
    if definition.scaleKey then
      context.bind(handle, definition.scaleKey, function(value) handle.setAppearance(value, square) end)
      handle.setAppearance(context.read(definition.scaleKey, appearanceScale), square)
    end
    if definition.squareKey then
      context.bind(handle, definition.squareKey, function(value) handle.setAppearance(appearanceScale, value) end)
      handle.setAppearance(appearanceScale, context.read(definition.squareKey, square))
    end
    scope.connect(root.Destroying, scope.destroy)
    scope.add(function() kit.scope.forget(handle) end)
    kit.scope.add(handle, handle.destroy)
    return handle
  end
end
Mini.__contract = { provides = { "setup", "install" }, requires = {} }
return Mini
