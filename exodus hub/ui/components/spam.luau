-- [[ spam panel ]]
--!optimize 2
-- @modules uispampanel

local Spam = {}
function Spam.setup() return true end
function Spam.install(context)
  function context.components.spam(parent, definition)
    definition = definition or {}
    local inst, C = context.inst, context.C
    local corner, stroke = context.kit.corner, context.kit.stroke
    local size = definition.size or UDim2.fromOffset(context.Theme.MINI_W, context.Theme.MINI_H)
    local root = inst("CanvasGroup", {
      Name = definition.name or "ExodusSpamMini",
      Visible = definition.visible ~= false,
      GroupTransparency = 0,
      Size = UDim2.fromOffset(size.X.Offset, size.Y.Offset),
      BackgroundColor3 = C.header,
      BorderSizePixel = 0,
      ZIndex = 15,
      Parent = parent,
    })
    corner(root, 14)
    corner(
      inst("Frame", {
        Size = UDim2.new(1, 8, 1, 8),
        Position = UDim2.new(0, -4, 0, -4),
        BackgroundColor3 = C.accent,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
        ZIndex = 14,
        Parent = root,
      }),
      18
    )
    stroke(root, nil, 1.5)
    local miniTitleBar = inst("Frame", {
      Size = UDim2.new(1, 0, 0.22, 0),
      BackgroundColor3 = Color3.fromRGB(20, 20, 46),
      BackgroundTransparency = 0.05,
      BorderSizePixel = 0,
      ZIndex = 16,
      Parent = root,
    })
    corner(miniTitleBar, 14)
    inst("Frame", {
      Size = UDim2.new(1, 0, 0, 12),
      Position = UDim2.new(0, 0, 1, -12),
      BackgroundColor3 = Color3.fromRGB(20, 20, 46),
      BackgroundTransparency = 0.05,
      BorderSizePixel = 0,
      ZIndex = 16,
      Parent = miniTitleBar,
    })
    corner(
      inst("Frame", {
        Size = UDim2.new(0.5, 0, 0, 2),
        Position = UDim2.new(0.25, 0, 0, 0),
        BackgroundColor3 = C.accentPink,
        BorderSizePixel = 0,
        ZIndex = 17,
        Parent = miniTitleBar,
      }),
      1
    )
    inst("TextLabel", {
      Size = UDim2.new(1, -16, 1, 0),
      Position = UDim2.new(0, 8, 0, 0),
      BackgroundTransparency = 1,
      Text = definition.title or "Spam",
      TextColor3 = C.subtext,
      TextScaled = true,
      TextXAlignment = Enum.TextXAlignment.Center,
      Font = Enum.Font.GothamBold,
      ZIndex = 17,
      Parent = miniTitleBar,
    })
    local spamButton = inst("TextButton", {
      Name = "SpamButton",
      Size = UDim2.new(1, -12, 0.78, -8),
      Position = UDim2.new(0, 6, 0.22, 3),
      BackgroundColor3 = definition.value == true and C.green or C.red,
      BorderSizePixel = 0,
      Text = definition.value == true and "ON" or "OFF",
      TextColor3 = Color3.new(1, 1, 1),
      TextScaled = true,
      Font = Enum.Font.GothamBold,
      ZIndex = 16,
      Parent = root,
    })
    corner(spamButton, 10)
    inst("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 12 }, spamButton)
    local scope = context.Runtime.scope()
    local handle = { Root = root, Header = miniTitleBar, Button = spamButton, scope = scope }
    function handle.setValue(value)
      spamButton.Text = value and "ON" or "OFF"
      spamButton.BackgroundColor3 = value and C.green or C.red
    end
    function handle.setVisible(value) root.Visible = value == true end
    function handle.destroy()
      scope.destroy()
      root:Destroy()
    end
    scope.connect(root.Destroying, scope.destroy)
    scope.add(function() context.kit.scope.forget(handle) end)
    context.kit.scope.add(handle, handle.destroy)
    if definition.onActivate then
      scope.connect(spamButton.Activated, function()
        if not context.kit.suspended then
          definition.onActivate()
        end
      end)
    end
    return handle
  end
end
Spam.__contract = { provides = { "setup", "install" }, requires = {} }
return Spam
