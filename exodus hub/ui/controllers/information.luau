-- [[ game readout overlays ]]
--!optimize 2
-- @modules uitelemetry

local Controller = {}
function Controller.setup() return true end
function Controller.create(context)
  local inst, utils = context.inst, context.deps.State
  local gui = inst("ScreenGui", {
    Name = "ExodusInformationOverlay",
    DisplayOrder = context.theme.DISPLAY_ORDER,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    Parent = context.playerGui,
  })
  context.scope.add(context.deps.Runtime.mountLayer(gui, context.playerGui, context.theme.SCREEN_LAYERS.information))
  context.refs.informationGui = gui
  local textService = game:GetService("TextService")
  local entries = {}
  for _, definition in ipairs(context.deps.Model.getReadouts()) do
    local label = inst("TextLabel", {
      Name = definition.id,
      Size = UDim2.fromOffset(1, 1),
      AnchorPoint = definition.anchor,
      Position = definition.position,
      BackgroundColor3 = context.theme.COLORS.header,
      Text = "",
      TextColor3 = context.theme.COLORS.text,
      TextSize = 14,
      Font = Enum.Font.GothamSemibold,
      TextXAlignment = Enum.TextXAlignment.Left,
      TextYAlignment = Enum.TextYAlignment.Top,
      TextTransparency = 1,
      BackgroundTransparency = 1,
      Visible = false,
      ZIndex = 100,
      Parent = gui,
    })
    context.corner(label, 8)
    inst("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, label)
    entries[#entries + 1] = { label = label, definition = definition, shown = false, revision = 0 }
  end
  local function refresh()
    for _, entry in ipairs(entries) do
      local label, definition = entry.label, entry.definition
      local enabled = utils.getConfigValue(definition.key) == true
      local text = ""
      if enabled then
        local ok, value = pcall(definition.read)
        if ok then
          text = tostring(value or "")
          entry.failed = false
        elseif not entry.failed then
          utils.recordError("Readout." .. definition.id, value)
          entry.failed = true
        end
      end
      if label.Text ~= text and text ~= "" then
        label.Text = text
        local bounds = textService:GetTextSize(text, label.TextSize, label.Font, Vector2.new(1000, 1000))
        label.Size = UDim2.fromOffset(math.ceil(bounds.X) + 16, math.ceil(bounds.Y) + 10)
      end
      local shown = text ~= ""
      if entry.shown ~= shown then
        entry.shown = shown
        entry.revision += 1
        local revision = entry.revision
        if shown then
          label.Visible = true
        end
        context.motion.play(label, "control", { TextTransparency = shown and 0 or 1, BackgroundTransparency = shown and 0.2 or 1 }, function()
          if revision == entry.revision and label.Parent then
            label.Visible = shown
          end
        end)
      end
    end
  end
  if #entries > 0 then
    local elapsed = 0
    context.trackConn(context.services.RunService.Heartbeat:Connect(function(dt)
      elapsed += dt
      if elapsed >= 0.05 and not context.state.closing then
        elapsed = 0
        refresh()
      end
    end))
    context.scope.add(utils.observeConfig(refresh))
    refresh()
  end
  return {}
end
Controller.__contract = { provides = { "setup", "create" }, requires = {} }
return Controller
