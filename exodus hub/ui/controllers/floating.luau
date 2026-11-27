-- [[ floating ]]
--!optimize 2
-- @modules uifloating

-- module
local Controller = {}

-- configuration

-- setup
function Controller.setup() return true end

-- controller
function Controller.create(context)
  local Utils = context.deps.Utils
  local GameInfo = context.deps.Hub
  local Controls = context.deps.Controls
  local UIState = context.state
  local C = context.theme.COLORS
  local CLASH_SIZE = context.theme.CLASH_SIZE
  local OFFSCREEN_X = (-context.theme.CLASH_SIZE - 40)
  local MINI_W = context.theme.MINI_W
  local MINI_H = context.theme.MINI_H
  local inst = context.inst
  local corner = context.corner
  local stroke = context.stroke
  local twPlay = context.twPlay
  local safeCancel = context.safeCancel
  local viewport = context.viewport
  local setConfigValue = context.setConfigValue
  local trackConn = context.trackConn
  local untrackConn = context.untrackConn
  local safeDisconnect = context.safeDisconnect
  local makeDraggable = context.makeDraggable
  local setSpam
  local automaticVisibility = {}
  local function paintBall(ball, value, onText, offText, onColor, offColor, onSize, offSize)
    if not ball or not ball.Parent then
      return
    end
    ball.Text = value and onText or offText
    if onSize then
      ball.TextSize = value and onSize or offSize
    end
    twPlay(ball, "control", { BackgroundColor3 = value and onColor or offColor })
  end
  local function paintParryBall(value) paintBall(context.refs.parryBall, value, "PARRY\nON", "PARRY\nOFF", C.green, C.red, 14, 14) end
  local function showBall(ball, visible, visibleKey, xKey, yKey, defaultX, defaultY)
    local config = Utils.getConfig()
    local x = config[xKey] or defaultX
    local y = config[yKey] or defaultY
    local shouldShow = (visible or automaticVisibility[visibleKey] == true) and not UIState.desktop
    local ability = context.abilityKeys[visibleKey]
    if ability then
      shouldShow = shouldShow and GameInfo.getAbilityAvailability(ability)
    end
    if ball:GetAttribute("ExodusShown") == shouldShow then
      return
    end
    ball:SetAttribute("ExodusShown", shouldShow)
    local generation = (ball:GetAttribute("ExodusMotion") or 0) + 1
    ball:SetAttribute("ExodusMotion", generation)
    if shouldShow then
      if not ball.Visible then
        ball.TextTransparency, ball.BackgroundTransparency = 1, 1
      end
      ball.Visible = true
    end
    local tween = twPlay(ball, "panel", {
      Position = shouldShow and UDim2.fromOffset(x, y) or UDim2.fromOffset(OFFSCREEN_X, y),
      TextTransparency = shouldShow and 0 or 1,
      BackgroundTransparency = shouldShow and 0 or 1,
    })
    local outline = ball:FindFirstChildOfClass("UIStroke")
    if outline then
      twPlay(outline, "panel", { Transparency = shouldShow and 0 or 1 })
    end
    if tween then
      local connection
      connection = trackConn(tween.Completed:Connect(function(playbackState)
        safeDisconnect(connection)
        untrackConn(connection)
        if playbackState == Enum.PlaybackState.Completed and generation == ball:GetAttribute("ExodusMotion") and ball.Parent then
          ball.Visible = shouldShow
        end
      end))
    else
      ball.Visible = shouldShow
    end
  end
  local function pulseBall(ball)
    local shrink = twPlay(ball, "press", { Size = UDim2.new(0, CLASH_SIZE - 6, 0, CLASH_SIZE - 6) })
    if not shrink then
      return
    end
    local connection
    connection = trackConn(shrink.Completed:Connect(function(playbackState)
      safeDisconnect(connection)
      untrackConn(connection)
      if playbackState == Enum.PlaybackState.Completed and ball and ball.Parent then
        twPlay(ball, "feedback", { Size = UDim2.new(0, CLASH_SIZE, 0, CLASH_SIZE) })
      end
    end))
  end
  local config = Utils.getConfig()
  local function createMovementBall(name, text, color, xKey, yKey, yOffset, onClick)
    local x = config[xKey] or (CLASH_SIZE + 22)
    local y = config[yKey] or (viewport().Y / 2 + yOffset)
    local ball = inst("TextButton", {
      Name = name,
      Size = UDim2.new(0, CLASH_SIZE, 0, CLASH_SIZE),
      Position = UDim2.new(0, OFFSCREEN_X, 0, y),
      BackgroundColor3 = color,
      Text = text,
      TextColor3 = Color3.new(1, 1, 1),
      TextSize = 15,
      Font = Enum.Font.GothamBold,
      Active = true,
      ZIndex = 8,
      Parent = context.refs.screenGui,
    })
    corner(ball, 999)
    stroke(ball, nil, 2)
    local dragging = makeDraggable(ball, ball, function()
      setConfigValue(xKey, ball.Position.X.Offset)
      setConfigValue(yKey, ball.Position.Y.Offset)
    end)
    trackConn(ball.Activated:Connect(function()
      if not dragging() then
        onClick(ball)
      end
    end))
    return ball, x, y
  end
  if context.combatUI == false then
    local function inactive() end
    local buttons = {}
    context.miniBallRefs = {}
    for index, definition in ipairs(context.miniBalls or {}) do
      local prefix = definition.prefix
      local visibleKey, xKey, yKey = prefix .. "Visible", prefix .. "X", prefix .. "Y"
      local key, label = definition.key, definition.label
      local action = definition.action
      local reset = action == "resetState"
      local onColor, offColor = C.green, action and not reset and C.accent or C.red
      local onText, offText = label .. "\nON", label .. "\nOFF"
      if action then
        onText, offText = label, label
      end
      local value = key ~= nil and config[key] == true
      local ball = createMovementBall("Exodus" .. prefix, value and onText or offText, value and onColor or offColor, xKey, yKey, 0, function()
        if reset then
          GameInfo.resetState()
          if context.notifications.toast then
            context.notifications.toast("PvP encerrado.")
          end
          return
        end
        if action then
          local callback = Controls[action]
          if type(callback) == "function" then
            local accepted, reason = callback()
            if accepted then
              pulseBall(context.refs[prefix])
            elseif reason and context.notifications.toast then
              context.notifications.toast(reason)
            end
          end
          return
        end
        local enabled = Utils.getConfigValue(key) ~= true
        if setConfigValue(key, enabled) and context.notifications.toast then
          context.notifications.toast(definition.title .. (enabled and " On" or " Off"))
        end
      end)
      ball.Visible = false
      ball.TextTransparency, ball.BackgroundTransparency = 1, 1
      context.refs[prefix] = ball
      context.miniBallRefs[#context.miniBallRefs + 1] = prefix
      local function show(visible)
        local scale = math.max(context.refs.responsiveScale.Scale, 0.01)
        local view = viewport() / scale
        local gap = CLASH_SIZE + 8
        local x = math.min(14 + ((index - 1) % 2) * gap, math.max(0, view.X - CLASH_SIZE))
        local rows = math.ceil(#context.miniBalls / 2)
        local y = math.clamp((view.Y - rows * gap) / 2 + math.floor((index - 1) / 2) * gap, 0, math.max(0, view.Y - CLASH_SIZE))
        showBall(ball, visible, visibleKey, xKey, yKey, x, y)
      end
      buttons[#buttons + 1] = {
        key = key,
        visibleKey = visibleKey,
        show = show,
        paint = function(enabled) paintBall(ball, enabled, onText, offText, onColor, offColor, 14, 14) end,
      }
      paintBall(ball, value, onText, offText, onColor, offColor, 14, 14)
      show(config[visibleKey] == true)
    end
    return {
      setSpam = inactive,
      showMini = inactive,
      applyMiniScale = inactive,
      showClashBall = inactive,
      showParryBall = inactive,
      showDarkBall = inactive,
      showJumpBall = inactive,
      showUpDashBall = inactive,
      sync = function(changes)
        for _, button in ipairs(buttons) do
          if button.key and changes[button.key] ~= nil then
            button.paint(changes[button.key] == true)
          end
          if changes[button.visibleKey] ~= nil then
            button.show(changes[button.visibleKey] == true)
          end
        end
      end,
      applyVisibility = inactive,
      refreshAbilities = inactive,
    }
  end
  local function showParryBall(value)
    showBall(context.refs.parryBall, value, "ParryBallVisible", "ParryBallX", "ParryBallY", 14, viewport().Y / 2 - CLASH_SIZE - 40)
  end
  local function paintClashBall() paintBall(context.refs.clashBall, UIState.clashBallOn, "ON", "OFF", C.green, C.red, 18, 16) end
  local function setClashBall(v, silent)
    if setConfigValue("AutoSpam", v) == false then
      return
    end
    UIState.clashBallOn = v
    if silent then
      return
    end
    paintClashBall()
    pulseBall(context.refs.clashBall)
    if context.notifications.toast then
      context.notifications.toast("Auto Spam " .. (v and "On" or "Off"))
    end
  end
  local function showClashBall(v) showBall(context.refs.clashBall, v, "ClashBallVisible", "ClashBallX", "ClashBallY", 14, viewport().Y / 2 - CLASH_SIZE / 2) end
  local function paintDarkBall(v) paintBall(context.refs.darkBall, v, "ON", "OFF", C.darkOn, C.darkOff, 18, 16) end
  local function showDarkBall(v) showBall(context.refs.darkBall, v, "DarkBallVisible", "DarkBallX", "DarkBallY", 14, viewport().Y / 2 + CLASH_SIZE / 2 + 8) end
  local function setDarkBall(v)
    if not setConfigValue("AutoDark", v) then
      return
    end
    if type(Controls.onAutoDarkChanged) == "function" then
      Controls.onAutoDarkChanged()
    end
    paintDarkBall(v)
    pulseBall(context.refs.darkBall)
    if context.notifications.toast then
      context.notifications.toast("Auto Dark " .. (v and "On" or "Off"))
    end
  end
  local function showMovementBall(ball, visible, visibleKey, xKey, yKey, yOffset)
    showBall(ball, visible, visibleKey, xKey, yKey, CLASH_SIZE + 22, viewport().Y / 2 + yOffset)
  end
  local function showJumpBall(v) showMovementBall(context.refs.jumpBall, v, "JumpBallVisible", "JumpBallX", "JumpBallY", -CLASH_SIZE / 2) end
  local function showUpDashBall(v) showMovementBall(context.refs.upDashBall, v, "UpDashBallVisible", "UpDashBallX", "UpDashBallY", CLASH_SIZE / 2 + 8) end
  local function paintJumpBall(v) paintBall(context.refs.jumpBall, v, "JUMP\nON", "JUMP\nOFF", C.jumpOn, C.jumpOff) end
  local function setJumpBall(v)
    if not setConfigValue("AutoJump", v) then
      return
    end
    if type(Controls.onAutoJumpChanged) == "function" then
      Controls.onAutoJumpChanged()
    end
    paintJumpBall(v)
    if context.notifications.toast then
      context.notifications.toast("Auto Jump " .. (v and "On" or "Off"))
    end
  end
  local function miniScreenScale() return context.refs.responsiveScale and context.refs.responsiveScale.Scale or 1 end
  local function miniLayout(scale)
    local view, screenScale = viewport(), math.max(miniScreenScale(), 0.01)
    local screenWidth, screenHeight = view.X / screenScale, view.Y / screenScale
    local config = Utils.getConfig()
    local width = math.min(MINI_W * scale * (tonumber(config.MiniSpamWidth) or 1), screenWidth)
    local height = math.min(MINI_H * scale * (tonumber(config.MiniSpamHeight) or 1), screenHeight)
    local x = math.clamp(config.MiniX or (screenWidth - width - 14), 0, math.max(0, screenWidth - width))
    local y = math.clamp(config.MiniY or (screenHeight / 2 - height / 2), 0, math.max(0, screenHeight - height))
    return x, y, width, height, screenWidth
  end
  local function applyMiniScale(value)
    if not context.refs.miniGui or not context.refs.miniGui.Parent then
      return
    end
    local scale = math.clamp(tonumber(value) or 1, 0.5, 2)
    local x, y, width, height = miniLayout(scale)
    twPlay(context.refs.miniGui, "feedback", { Size = UDim2.fromOffset(width, height) })
    if context.refs.miniGui.Visible then
      twPlay(context.refs.miniGui, "feedback", { Position = UDim2.fromOffset(x, y) })
    end
  end
  local function showMini(v)
    v = (v or automaticVisibility.MiniSpamVisible == true) and not UIState.desktop
    local mini = context.refs.miniGui
    if not mini or not mini.Parent then
      return
    end
    local config = Utils.getConfig()
    local miniX, miniY, width, height, screenWidth = miniLayout(tonumber(config.MiniSpamScale) or 1)
    local targetPosition = UDim2.fromOffset(miniX, miniY)
    local hiddenPosition = UDim2.fromOffset(screenWidth + 30, miniY)
    UIState.miniGeneration += 1
    local generation = UIState.miniGeneration
    safeCancel(UIState.miniTween)
    safeCancel(UIState.miniFadeTween)
    UIState.miniTween, UIState.miniFadeTween = nil, nil
    mini.Size = UDim2.fromOffset(width, height)
    if v then
      if not mini.Visible then
        mini.Position = hiddenPosition
        mini.GroupTransparency = 1
        mini.Visible = true
      end
      UIState.miniTween = twPlay(mini, "panel", { Position = targetPosition })
      UIState.miniFadeTween = twPlay(mini, "panel", { GroupTransparency = 0 })
      return UIState.miniTween or UIState.miniFadeTween
    end
    if UIState.manualHoldInput then
      UIState.manualHoldInput = nil
      setSpam(false)
    end
    if not mini.Visible then
      return
    end
    UIState.miniTween = twPlay(mini, "panel", { Position = hiddenPosition })
    local fade = twPlay(mini, "panel", { GroupTransparency = 1 })
    UIState.miniFadeTween = fade
    if fade then
      local connection
      connection = trackConn(fade.Completed:Connect(function(playbackState)
        safeDisconnect(connection)
        untrackConn(connection)
        if playbackState == Enum.PlaybackState.Completed and generation == UIState.miniGeneration and mini.Parent then
          mini.Visible = false
        end
      end))
    else
      mini.Visible = false
    end
    return fade or UIState.miniTween
  end
  setSpam = function(v, silent)
    v = v == true
    local changed = UIState.spamOn ~= v
    UIState.spamOn = v
    if Utils.isManualSpamActive() ~= v then
      Utils.setManualSpamActive(v)
    end
    local spamButton = context.refs.miniGui and context.refs.miniGui:FindFirstChild("SpamButton")
    if not spamButton then
      return
    end
    spamButton.Text = v and "ON" or "OFF"
    local color = v and C.green or C.red
    if silent or not changed then
      spamButton.BackgroundColor3 = color
      spamButton.Size = UDim2.new(1, -12, 0.78, -8)
      return
    end
    twPlay(spamButton, "control", { BackgroundColor3 = color })
    local shrink = twPlay(spamButton, "press", { Size = UDim2.new(1, -14, 0.78, -12) })
    if shrink then
      local connection
      connection = trackConn(shrink.Completed:Connect(function(playbackState)
        safeDisconnect(connection)
        untrackConn(connection)
        if playbackState == Enum.PlaybackState.Completed and spamButton.Parent then
          twPlay(spamButton, "feedback", { Size = UDim2.new(1, -12, 0.78, -8) })
        end
      end))
    end
  end
  context.refs.clashBall = inst("TextButton", {
    Name = "ExodusClashBall",
    Size = UDim2.new(0, CLASH_SIZE, 0, CLASH_SIZE),
    Position = UDim2.new(0, OFFSCREEN_X, 0.5, -CLASH_SIZE / 2),
    BackgroundColor3 = C.red,
    Text = "OFF",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    Active = true,
    ZIndex = 8,
    Parent = context.refs.screenGui,
  })
  corner(context.refs.clashBall, 999)
  stroke(context.refs.clashBall, nil, 2)
  UIState.clashBallOn = config.AutoSpam or false
  context.refs.clashBall.Text = UIState.clashBallOn and "ON" or "OFF"
  context.refs.clashBall.TextSize = UIState.clashBallOn and 18 or 16
  context.refs.clashBall.BackgroundColor3 = UIState.clashBallOn and C.green or C.red
  paintClashBall()

  local parryY = config.ParryBallY or (viewport().Y / 2 - CLASH_SIZE - 40)
  context.refs.parryBall = inst("TextButton", {
    Name = "ExodusParryBall",
    Size = UDim2.new(0, CLASH_SIZE, 0, CLASH_SIZE),
    Position = UDim2.new(0, OFFSCREEN_X, 0, parryY),
    BackgroundColor3 = config.AutoParry and C.green or C.red,
    Text = config.AutoParry and "PARRY\nON" or "PARRY\nOFF",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 14,
    Font = Enum.Font.GothamBold,
    Active = true,
    ZIndex = 8,
    Parent = context.refs.screenGui,
  })
  corner(context.refs.parryBall, 999)
  stroke(context.refs.parryBall, nil, 2)
  paintParryBall(config.AutoParry == true)
  local isParryDragging = makeDraggable(context.refs.parryBall, context.refs.parryBall, function()
    setConfigValue("ParryBallX", context.refs.parryBall.Position.X.Offset)
    setConfigValue("ParryBallY", context.refs.parryBall.Position.Y.Offset)
  end)
  trackConn(context.refs.parryBall.Activated:Connect(function()
    if not isParryDragging() then
      local value = Utils.getConfigValue("AutoParry") ~= true
      if setConfigValue("AutoParry", value) and context.notifications.toast then
        context.notifications.toast("Auto Parry " .. (value and "On" or "Off"))
      end
    end
  end))
  local isClashDragging = makeDraggable(context.refs.clashBall, context.refs.clashBall, function()
    setConfigValue("ClashBallX", context.refs.clashBall.Position.X.Offset)
    setConfigValue("ClashBallY", context.refs.clashBall.Position.Y.Offset)
  end)
  trackConn(context.refs.clashBall.Activated:Connect(function()
    if not isClashDragging() then
      setClashBall(not UIState.clashBallOn)
    end
  end))

  local darkY = config.DarkBallY or (viewport().Y / 2 + CLASH_SIZE / 2 + 8)
  context.refs.darkBall = inst("TextButton", {
    Name = "ExodusDarkBall",
    Size = UDim2.new(0, CLASH_SIZE, 0, CLASH_SIZE),
    Position = UDim2.new(0, OFFSCREEN_X, 0, darkY),
    BackgroundColor3 = config.AutoDark and C.darkOn or C.darkOff,
    Text = config.AutoDark and "ON" or "OFF",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = config.AutoDark and 18 or 16,
    Font = Enum.Font.GothamBold,
    Active = true,
    ZIndex = 8,
    Parent = context.refs.screenGui,
  })
  corner(context.refs.darkBall, 999)
  stroke(context.refs.darkBall, nil, 2)
  paintDarkBall(config.AutoDark == true)
  local isDarkDragging = makeDraggable(context.refs.darkBall, context.refs.darkBall, function()
    setConfigValue("DarkBallX", context.refs.darkBall.Position.X.Offset)
    setConfigValue("DarkBallY", context.refs.darkBall.Position.Y.Offset)
  end)
  trackConn(context.refs.darkBall.Activated:Connect(function()
    if isDarkDragging() then
      return
    end
    setDarkBall(Utils.getConfigValue("AutoDark") ~= true)
  end))
  context.refs.jumpBall = createMovementBall(
    "ExodusJumpBall",
    config.AutoJump and "JUMP\nON" or "JUMP\nOFF",
    config.AutoJump and C.jumpOn or C.jumpOff,
    "JumpBallX",
    "JumpBallY",
    -CLASH_SIZE / 2,
    function() setJumpBall(Utils.getConfigValue("AutoJump") ~= true) end
  )
  context.refs.upDashBall = createMovementBall("ExodusUpDashBall", "DASH\n↑", C.upDash, "UpDashBallX", "UpDashBallY", CLASH_SIZE / 2 + 8, function(ball)
    if not context.canUseAbility("dash") then
      return
    end
    if type(Controls.onUpDash) == "function" then
      Controls.onUpDash()
    end
    pulseBall(ball)
    if context.notifications.toast then
      context.notifications.toast("Up Dash")
    end
  end)
  paintJumpBall(config.AutoJump == true)
  local _, miniY, miniWidth, miniHeight, miniScreenWidth = miniLayout(tonumber(config.MiniSpamScale) or 1)
  local MINI_OFF_X = miniScreenWidth + 30
  local miniComponent = context.kit.Components.mini(context.refs.screenGui, {
    name = "ExodusSpamMini",
    title = "Spam",
    size = UDim2.fromOffset(miniWidth, miniHeight),
    visible = false,
    buttonName = "SpamButton",
    draggable = false,
  })
  context.refs.miniGui = miniComponent.Root
  context.refs.miniGui.GroupTransparency = 1
  local miniTitleBar, spamButton = miniComponent.Header, miniComponent.Button
  miniComponent.setValue(UIState.spamOn)
  trackConn(spamButton.Activated:Connect(function()
    if Utils.getConfigValue("ManualSpamMode") ~= "Hold" then
      setSpam(not UIState.spamOn)
    end
  end))
  trackConn(spamButton.InputBegan:Connect(function(input)
    if Utils.getConfigValue("ManualSpamMode") ~= "Hold" or UIState.manualHoldInput then
      return
    end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
      UIState.manualHoldInput = input
      setSpam(true)
    end
  end))
  context.refs.miniGui.Position = UDim2.new(0, MINI_OFF_X, 0, miniY)
  local function saveMiniPosition() Utils.setConfig({ MiniX = context.refs.miniGui.Position.X.Offset, MiniY = context.refs.miniGui.Position.Y.Offset }) end
  makeDraggable(miniTitleBar, context.refs.miniGui, saveMiniPosition, false, miniScreenScale)
  local visibility = {
    ParryBallVisible = showParryBall,
    ClashBallVisible = showClashBall,
    DarkBallVisible = showDarkBall,
    JumpBallVisible = showJumpBall,
    UpDashBallVisible = showUpDashBall,
    MiniSpamVisible = showMini,
  }

  local function sync(changes)
    if changes.AutoSpam ~= nil then
      UIState.clashBallOn = changes.AutoSpam == true
      paintClashBall()
    end
    if changes.AutoParry ~= nil then
      paintParryBall(changes.AutoParry == true)
    end
    if changes.AutoDark ~= nil then
      paintDarkBall(changes.AutoDark == true)
    end
    if changes.AutoJump ~= nil then
      paintJumpBall(changes.AutoJump == true)
    end
    for key, show in pairs(visibility) do
      if changes[key] ~= nil then
        show(changes[key] == true)
      end
    end
    if changes.MiniSpamScale ~= nil or changes.MiniSpamWidth ~= nil or changes.MiniSpamHeight ~= nil then
      applyMiniScale(Utils.getConfigValue("MiniSpamScale"))
    end
    if changes.ManualSpamMode ~= nil then
      UIState.manualHoldInput = nil
      setSpam(false)
    end
  end
  local lastAbilityMode
  local lastDarkAvailable, lastDashAvailable
  local function updateAbilityVisibility()
    lastAbilityMode = GameInfo.areAbilitiesEnabled()
    lastDarkAvailable = GameInfo.getAbilityAvailability("dark")
    lastDashAvailable = GameInfo.getAbilityAvailability("dash")
    context.pages.refresh()
    showDarkBall(Utils.getConfigValue("DarkBallVisible") == true)
    showUpDashBall(Utils.getConfigValue("UpDashBallVisible") == true)
    showJumpBall(Utils.getConfigValue("JumpBallVisible") == true)
  end
  for _, ball in ipairs({ context.refs.parryBall, context.refs.clashBall, context.refs.darkBall, context.refs.jumpBall, context.refs.upDashBall }) do
    ball.Visible = false
    ball.TextTransparency, ball.BackgroundTransparency = 1, 1
  end
  for key, show in pairs(visibility) do
    show(config[key] == true)
  end
  setSpam(Utils.isManualSpamActive(), true)
  return {
    setSpam = setSpam,
    showMini = showMini,
    applyMiniScale = applyMiniScale,
    showClashBall = showClashBall,
    showParryBall = showParryBall,
    showDarkBall = showDarkBall,
    showJumpBall = showJumpBall,
    showUpDashBall = showUpDashBall,
    sync = sync,
    applyVisibility = function(rules)
      automaticVisibility = rules
      for key, show in pairs(visibility) do
        show(Utils.getConfigValue(key) == true)
      end
    end,
    refreshAbilities = function()
      updateAbilityVisibility()
      trackConn(GameInfo.observeAbilityMode(updateAbilityVisibility))
      local elapsed = 0
      trackConn(context.services.RunService.Heartbeat:Connect(function(delta)
        elapsed += delta
        if elapsed < 0.25 then
          return
        end
        elapsed = 0
        if
          GameInfo.areAbilitiesEnabled() ~= lastAbilityMode
          or GameInfo.getAbilityAvailability("dark") ~= lastDarkAvailable
          or GameInfo.getAbilityAvailability("dash") ~= lastDashAvailable
        then
          updateAbilityVisibility()
        end
      end))
    end,
  }
end

-- contract
Controller.__contract = { provides = { "setup", "create" }, requires = {} }

return Controller
