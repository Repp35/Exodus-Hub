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
  local StatusView = context.deps.StatusView; local C = context.theme.COLORS
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
  if context.combatUI == false then return {} end
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
  local lastActivation, lastStop = nil, nil; local lastPeak, lastDistance = nil, {}
  local lastTravel = {}
  local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
  local function validText(v) return type(v) == "string" and v ~= "" and v ~= "nil" and v ~= "null" end
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
    if enabled.ap then data.ap = context.deps.Status.get("autoparry") end
    if enabled.gates then data.dynamicParry = context.deps.Status.get("dynamicparry") end
    if enabled.gates or enabled.travel or enabled.distance then data.autoSpam = context.deps.Status.get("autospam") end
    if type(data.autoSpam) == "table" then
      local status = data.autoSpam
      if
        type(status.lastActivationReason) == "string"
        and status.lastActivationReason ~= ""
        and status.lastActivationReason ~= "nil"
        and status.lastActivationReason ~= "null"
      then
        lastActivation = status.lastActivationReason
      end
      if type(status.lastStopReason) == "string" and status.lastStopReason ~= "" and status.lastStopReason ~= "nil" and status.lastStopReason ~= "null" then lastStop = status.lastStopReason end
    end
    local status = type(data.autoSpam) == "table" and table.clone(data.autoSpam) or {}; status.lastActivationReason, status.lastStopReason = lastActivation, lastStop
    data.autoSpam = status; local peak = type(data.ap) == "table" and data.ap.maxObservedCps
    if finite(peak) and peak > 0 and (not lastPeak or peak > lastPeak) then lastPeak = peak end
    data.ap = { maxObservedCps = lastPeak }; local stats = type(status.clashStats) == "table" and status.clashStats or {}
    if stats.partnerId and stats.partnerId ~= lastTravel.partnerId then
      lastTravel.partnerId = stats.partnerId; lastTravel.outgoingRecordedAt, lastTravel.lastOutgoingTTI, lastTravel.previousOutgoingTTI = nil, nil, nil
    end
    if finite(stats.outgoingRecordedAt) then
      lastTravel.outgoingRecordedAt, lastTravel.lastOutgoingTTI, lastTravel.previousOutgoingTTI =
        stats.outgoingRecordedAt, stats.lastOutgoingTTI, stats.previousOutgoingTTI
    end
    if finite(stats.incomingRecordedAt) then
      lastTravel.incomingRecordedAt, lastTravel.lastIncomingTTI, lastTravel.previousIncomingTTI =
        stats.incomingRecordedAt, stats.lastIncomingTTI, stats.previousIncomingTTI
    end
    if finite(stats.travelElapsed) and stats.travelElapsed >= 0 and validText(stats.travelTargetName) then
      lastTravel.travelElapsed, lastTravel.travelTargetName = stats.travelElapsed, stats.travelTargetName
    end
    if finite(stats.lastTravelTime) and stats.lastTravelTime > 0 then lastTravel.lastTravelTime, lastTravel.lastTravelTargetName = stats.lastTravelTime, stats.lastTravelTargetName end
    if finite(stats.fatalTravelTime) and stats.fatalTravelTime > 0 then lastTravel.fatalTravelTime, lastTravel.deceasedName = stats.fatalTravelTime, stats.deceasedName end
    data.travel = lastTravel; local panels = StatusView.format(data)
    if #panels.distance > 0 then lastDistance = panels.distance end
    panels.distance = lastDistance; render(apLabel, setAPVisible, enabled.ap, panels.ap)
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
