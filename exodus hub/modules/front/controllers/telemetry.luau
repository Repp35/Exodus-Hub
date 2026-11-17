-- [[ telemetry ]]

-- module
local Controller = {}

-- configuration
local CONFIG = { UPDATE_INTERVAL = 1 / 20 }

-- setup
function Controller.setup() return true end

-- controller
function Controller.create(context)
  local playerGui = context.playerGui; local Utils = context.deps.Utils
  local AutoSpam = context.deps.AutoSpam; local StatusView = context.deps.StatusView
  local AutoParry = context.deps.AutoParry; local C = context.theme.COLORS
  local RunService = context.services.RunService; local inst = context.inst
  local corner = context.corner; local twPlay = context.twPlay
  local setTextIfChanged = context.setTextIfChanged; local trackConn = context.trackConn
  local untrackConn = context.untrackConn; local safeDisconnect = context.safeDisconnect
  context.refs.informationGui = inst("ScreenGui", {
    Name = "ExodusInformationOverlay",
    DisplayOrder = 2147483647,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    Parent = playerGui,
  })
  context.refs.toastLayer = inst("Frame", {
    Name = "ExodusToastLayer",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ZIndex = 199,
    Parent = context.refs.informationGui,
  })
  local textService = game:GetService("TextService")
  local function compactInformation(label)
    local paddingX, paddingY = 8, 5; label.TextSize = 14
    label.TextWrapped = false; label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top; label.BorderSizePixel = 0
    label.ZIndex = 100; label.BackgroundTransparency = 1
    label.TextTransparency = 1; label.Visible = false
    corner(label, 8)
    inst("UIPadding", {
      PaddingLeft = UDim.new(0, paddingX),
      PaddingRight = UDim.new(0, paddingX),
      PaddingTop = UDim.new(0, paddingY),
      PaddingBottom = UDim.new(0, paddingY),
      Parent = label,
    })
    local function resize()
      local bounds = textService:GetTextSize(label.Text, label.TextSize, label.Font, Vector2.new(1000, 1000))
      label.Size = UDim2.fromOffset(math.ceil(bounds.X) + paddingX * 2, math.ceil(bounds.Y) + paddingY * 2)
    end
    trackConn(label:GetPropertyChangedSignal("Text"):Connect(resize)); resize()
    local shown, activeTween = false, nil
    return function(visible)
      if shown == visible then return end
      shown = visible
      if activeTween then activeTween:Cancel() end
      if visible then label.Visible = true end
      local transition = twPlay(label, "control", {
        BackgroundTransparency = visible and 0.2 or 1,
        TextTransparency = visible and 0 or 1,
      })
      activeTween = transition
      if transition then
        local connection
        connection = trackConn(transition.Completed:Connect(function(playbackState)
          safeDisconnect(connection); untrackConn(connection)
          if activeTween ~= transition then return end
          activeTween = nil
          if playbackState == Enum.PlaybackState.Completed and not shown then label.Visible = false end
        end))
      elseif not shown then
        label.Visible = false
      end
    end
  end
  local distanceLabel = inst("TextLabel", {
    Name = "ClashDistance",
    Size = UDim2.fromOffset(1, 1),
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 0),
    BackgroundColor3 = C.header,
    BackgroundTransparency = 0.2,
    Text = "",
    TextColor3 = C.text,
    TextSize = 14,
    Font = Enum.Font.GothamSemibold,
    Visible = false,
    ZIndex = 20,
    Parent = context.refs.informationGui,
  })
  local travelLabel = inst("TextLabel", {
    Name = "ClashTravelTime",
    Size = UDim2.fromOffset(1, 1),
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -20),
    BackgroundColor3 = C.header,
    BackgroundTransparency = 0.2,
    Text = "",
    TextColor3 = C.text,
    TextSize = 14,
    Font = Enum.Font.GothamSemibold,
    Visible = false,
    ZIndex = 20,
    Parent = context.refs.informationGui,
  })
  local gateLabel = inst("TextLabel", {
    Name = "AutoSpamGateInfo",
    Size = UDim2.fromOffset(1, 1),
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = C.header,
    BackgroundTransparency = 1,
    TextTransparency = 1,
    Text = "",
    TextColor3 = C.text,
    TextSize = 14,
    Font = Enum.Font.GothamSemibold,
    Visible = false,
    ZIndex = 20,
    Parent = context.refs.informationGui,
  })
  local apLabel = inst("TextLabel", {
    Name = "APMaxCps",
    Size = UDim2.fromOffset(1, 1),
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, 0, 0.5, 0),
    BackgroundColor3 = C.header,
    Text = "",
    TextColor3 = C.text,
    TextSize = 14,
    Font = Enum.Font.GothamSemibold,
    Parent = context.refs.informationGui,
  })
  local setAPVisible = compactInformation(apLabel); local setDistanceVisible = compactInformation(distanceLabel)
  local setTravelVisible = compactInformation(travelLabel); local setGateVisible = compactInformation(gateLabel)
  local failures = {}
  local function read(name, provider)
    local ok, value = pcall(provider.getStatus)
    if ok and type(value) == "table" then failures[name] = nil; return value end
    if not failures[name] then failures[name] = true; pcall(Utils.recordError, "Info", name .. ": " .. tostring(ok and "invalid status" or value)) end
    return nil
  end
  local function render(label, show, enabled, lines)
    local text = enabled and table.concat(lines or {}, "\n") or ""
    if text == "" then label.Visible = false end
    setTextIfChanged(label, text); show(text ~= "")
  end
  local function updateInformation()
    if not context.refs.informationGui.Parent then return end
    local enabled = {
      ap = Utils.getConfigValue("APMaxCpsVisible") == true,
      gates = Utils.getConfigValue("ClashGateInfoVisible") == true,
      travel = Utils.getConfigValue("ClashTravelTimeVisible") == true,
      distance = Utils.getConfigValue("ClashDistanceVisible") == true,
    }

    local data = {}
    if enabled.ap then data.ap = read("AutoParry", AutoParry) end
    if enabled.gates or enabled.travel or enabled.distance then data.autoSpam = read("AutoSpam", AutoSpam) end
    local panels = StatusView.format(data); render(apLabel, setAPVisible, enabled.ap, panels.ap)
    render(gateLabel, setGateVisible, enabled.gates, panels.gates); render(travelLabel, setTravelVisible, enabled.travel, panels.travel)
    render(distanceLabel, setDistanceVisible, enabled.distance, panels.distance)
  end
  local elapsed = 0
  trackConn(RunService.Heartbeat:Connect(function(dt)
    if context.state.closing then return end
    elapsed += dt
    if elapsed < CONFIG.UPDATE_INTERVAL then return end
    elapsed %= CONFIG.UPDATE_INTERVAL; updateInformation()
  end))
  return {}
end

-- contract
Controller.__contract = { provides = { "setup", "create" }, requires = {} }

return Controller
