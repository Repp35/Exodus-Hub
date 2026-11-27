-- [[ mini ]]
--!optimize 2
-- @modules uimini

local Mini = {}
function Mini.setup() return true end
function Mini.install(context)
  local kit, inst, C = context.kit, context.inst, context.C
  function context.components.mini(parent, definition)
    definition = definition or {}
    local scope = context.Runtime.scope()
    local root = inst("CanvasGroup", {
      Name = definition.name or "ExodusMini",
      Size = definition.size or UDim2.fromOffset(112, 96),
      Position = definition.position or UDim2.fromOffset(14, 160),
      BackgroundColor3 = C.header,
      Visible = definition.visible ~= false,
      ZIndex = 15,
    }, parent)
    kit.corner(root, 14)
    kit.stroke(root, nil, 1.5)
    local header = inst("TextLabel", {
      Name = "Header",
      Size = UDim2.new(1, 0, 0.22, 0),
      BackgroundTransparency = 1,
      Text = definition.title or "Action",
      Font = context.FONT.strong,
      TextColor3 = C.subtext,
      TextScaled = true,
      Active = true,
      ZIndex = 17,
    }, root)
    local button = inst("TextButton", {
      Name = definition.buttonName or "Action",
      Size = UDim2.new(1, -12, 0.78, -8),
      Position = UDim2.new(0, 6, 0.22, 3),
      BackgroundColor3 = C.accent,
      Text = definition.text or "OFF",
      Font = context.FONT.strong,
      TextColor3 = C.text,
      TextScaled = true,
      ZIndex = 16,
    }, root)
    kit.corner(button, 10)
    inst("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 12 }, button)
    local held, current
    local handle = { Root = root, Header = header, Button = button, scope = scope, enabled = true }
    local function release(input)
      if held and (not input or held == input) then
        held = nil
        if definition.onHold then
          definition.onHold(false)
        end
      end
    end
    function handle.setAppearance(scale, square)
      scale = math.clamp(tonumber(scale) or 1, 0.5, 2)
      local size = definition.size or UDim2.fromOffset(112, 96)
      root.Size = UDim2.fromOffset((square and size.Y.Offset or size.X.Offset) * scale, size.Y.Offset * scale)
    end
    function handle.setVisible(value)
      root.Visible = value == true
      if not root.Visible then
        release()
      end
    end
    function handle.setValue(value)
      current = value == true
      button.Text = value and (definition.onText or "ON") or (definition.offText or "OFF")
      button.BackgroundColor3 = value and C.green or C.red
    end
    function handle.getValue() return current end
    function handle.setEnabled(enabled)
      handle.enabled = enabled == true
      button.Active, button.Selectable = handle.enabled, handle.enabled
      if not handle.enabled then
        release()
      end
    end
    function handle.destroy()
      scope.destroy()
      root:Destroy()
    end
    if definition.draggable ~= false then
      local start, initial
      context.Runtime.bindDrag(scope, header, function(input)
        if not start then
          start, initial = input.Position, root.Position
          return
        end
        local parentSize = parent.AbsoluteSize
        local scale = root.AbsoluteSize.X / math.max(1, root.Size.X.Offset)
        scale = math.max(0.01, scale)
        local delta = (input.Position - start) / scale
        local x = initial.X.Scale * parentSize.X / scale + initial.X.Offset + delta.X
        local y = initial.Y.Scale * parentSize.Y / scale + initial.Y.Offset + delta.Y
        root.Position = UDim2.fromOffset(
          math.clamp(x, 0, math.max(0, parentSize.X / scale - root.Size.X.Offset)),
          math.clamp(y, 0, math.max(0, parentSize.Y / scale - root.Size.Y.Offset))
        )
      end, function() return handle.enabled and not kit.suspended end)
      local function finishDrag()
        if start and definition.onDragEnd then
          definition.onDragEnd(root.Position)
        end
        start, initial = nil, nil
      end
      scope.connect(context.UIS.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
          finishDrag()
        end
      end)
      scope.connect(context.UIS.WindowFocusReleased, finishDrag)
    end
    context.drags[release] = release
    scope.add(function() context.drags[release] = nil end)
    scope.connect(button.Activated, function()
      if kit.suspended or not handle.enabled then
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
    scope.connect(button.InputBegan, function(input)
      if held or kit.suspended or not handle.enabled or not definition.onHold then
        return
      end
      if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        held = input
        definition.onHold(true)
      end
    end)
    scope.connect(context.UIS.InputEnded, release)
    scope.connect(context.UIS.WindowFocusReleased, function() release() end)
    scope.connect(root:GetPropertyChangedSignal("Visible"), function()
      if not root.Visible then
        release()
      end
    end)
    scope.connect(root.Destroying, scope.destroy)
    scope.add(function()
      release()
      kit.scope.forget(handle)
    end)
    kit.scope.add(handle, handle.destroy)
    if definition.key then
      handle.setValue(context.read(definition.key, definition.value))
      context.bind(handle, definition.key, handle.setValue)
    end
    if definition.enabled == false then
      handle.setEnabled(false)
    end
    return handle
  end
end
Mini.__contract = { provides = { "setup", "install" }, requires = {} }
return Mini
