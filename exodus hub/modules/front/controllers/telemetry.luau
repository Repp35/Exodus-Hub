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
  local GameInfo = context.deps.GameInfo; local AutoSpam = context.deps.AutoSpam
  local AutoParry = context.deps.AutoParry; local C = context.theme.COLORS
  local RunService = context.services.RunService; local Players = context.services.Players
  local inst = context.inst; local corner = context.corner
  local twPlay = context.twPlay; local setTextIfChanged = context.setTextIfChanged
  local trackConn = context.trackConn; local untrackConn = context.untrackConn
  local safeDisconnect = context.safeDisconnect
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
  local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
  local function positive(value) return finite(value) and value > 0 end
  local reasons = {
    lethal_deadline = "Incoming deadline",
    parry_margin_shrinking = "AP losing margin",
    return_demand_exceeds_ap = "Return faster than AP",
    ap_unavailable = "AP unavailable",
    return_target = "Fast target return",
    close_target = "Close exchange",
    consistent_self_return = "Repeated return",
    dash_incoming = "Incoming dash",
    dash_self = "Approaching dash",
    haunter = "Haunter",
    haunter_self = "Haunter",
  }

  local function updateInformation()
    if not context.refs.informationGui.Parent then return end
    local time = os.clock(); local apEnabled = Utils.getConfigValue("APMaxCpsVisible") == true
    local apStatus = apEnabled and AutoParry.getStatus() or nil; local peak = apStatus and apStatus.maxObservedCps
    local apText = positive(peak) and string.format("AP max: %.2f CPS", peak) or ""
    if apText == "" then apLabel.Visible = false end
    setTextIfChanged(apLabel, apText); setAPVisible(apEnabled and apText ~= "")
    local gateEnabled = Utils.getConfigValue("ClashGateInfoVisible") == true; local travelEnabled = Utils.getConfigValue("ClashTravelTimeVisible") == true
    local distanceEnabled = Utils.getConfigValue("ClashDistanceVisible") == true
    if not gateEnabled and not travelEnabled and not distanceEnabled then
      setTextIfChanged(gateLabel, ""); setTextIfChanged(travelLabel, "")
      setTextIfChanged(distanceLabel, ""); gateLabel.Visible, travelLabel.Visible, distanceLabel.Visible = false, false, false
      setGateVisible(false); setTravelVisible(false)
      setDistanceVisible(false); return
    end
    local status, snapshot = AutoSpam.getStatus(), GameInfo.getSnapshotAt(time); local valid = GameInfo.isSnapshotValid(snapshot)
      and not snapshot.teleported
      and not snapshot.resetting
      and not snapshot.locked
      and not snapshot.targetUncertain
      and snapshot.valid ~= false
      and snapshot.ballValid ~= false
      and snapshot.mode ~= "training"
      and snapshot.ballCanMove ~= false
      and (snapshot.syncAt == nil or (finite(snapshot.syncAt) and time >= snapshot.syncAt and time - snapshot.syncAt <= 0.5))
    local active = status and status.active == true; local stats = status and status.clashStats
    local live = valid and stats and not stats.frozen and (active or Utils.isManualSpamActive()); local risk = valid and status and status.risk
    local gateLines = {}
    if gateEnabled and valid then
      if active then local activation = status.activationReason or status.lastActivationReason; gateLines[#gateLines + 1] = "Auto Spam: " .. (reasons[activation] or "Active") end
      if risk and risk.exchangeEvidence == true then
        if positive(risk.observedCycle) then gateLines[#gateLines + 1] = string.format("Return: %.0f ms", risk.observedCycle * 1000) end
        if positive(risk.nextCycle) and (not positive(risk.observedCycle) or math.abs(risk.nextCycle - risk.observedCycle) > 0.001) then
          gateLines[#gateLines + 1] = string.format("Next return: %.0f ms", risk.nextCycle * 1000)
        end
        if #gateLines > 0 and positive(risk.response) then gateLines[#gateLines + 1] = string.format("AP budget: %.0f ms", risk.response * 1000) end
        if finite(risk.nextHeadroom) then gateLines[#gateLines + 1] = string.format("AP margin: %.0f ms", risk.nextHeadroom * 1000) end
      end
    end
    local travelLines, distanceLines = {}, {}
    if live then
      if travelEnabled then
        local me = Players.LocalPlayer and Players.LocalPlayer.UserId
        if positive(stats.travelStartedAt) and positive(stats.travelTarget) and time >= stats.travelStartedAt then
          local who = stats.travelTarget == me and "You" or "Opponent"; travelLines[#travelLines + 1] = string.format("%s: %.0f ms", who, (time - stats.travelStartedAt) * 1000)
        end
        if positive(stats.lastTravelTime) then travelLines[#travelLines + 1] = string.format("Last return: %.0f ms", stats.lastTravelTime * 1000) end
      end
      if distanceEnabled then
        local sample = stats.endSample
        if sample and finite(sample.distance) and sample.distance >= 0 then distanceLines[#distanceLines + 1] = string.format("Distance: %.1f studs", sample.distance) end
        local speed = snapshot.syncSpeed
        if not positive(speed) then speed = snapshot.speed end
        if positive(speed) then distanceLines[#distanceLines + 1] = string.format("Speed: %.0f", speed) end
        if positive(stats.currentCps) then distanceLines[#distanceLines + 1] = string.format("Clash: %.2f CPS", stats.currentCps) end
      end
    end
    local function render(label, show, enabled, lines)
      local text = table.concat(lines, "\n")
      if text == "" then label.Visible = false end
      setTextIfChanged(label, text); show(enabled and text ~= "")
    end
    render(gateLabel, setGateVisible, gateEnabled, gateLines); render(travelLabel, setTravelVisible, travelEnabled, travelLines)
    render(distanceLabel, setDistanceVisible, distanceEnabled, distanceLines)
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
