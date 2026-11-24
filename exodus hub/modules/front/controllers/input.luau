-- [[ input ]]

-- module
local Controller = {}

-- configuration
local CONFIG = {}

-- setup
function Controller.setup() return true end

-- controller
function Controller.create(context)
  local Utils = context.deps.Utils; local UIState = context.state
  local UIS = context.services.UIS; local trackConn = context.trackConn
  local function inputBinding(input)
    if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType.Name:match("^Gamepad") then return input.KeyCode end
    if
      input.UserInputType == Enum.UserInputType.MouseButton1
      or input.UserInputType == Enum.UserInputType.MouseButton2
      or input.UserInputType == Enum.UserInputType.MouseButton3
    then
      return input.UserInputType
    end
    return nil
  end
  local function isKey(input, binding) return input and binding and binding ~= Enum.KeyCode.Unknown and inputBinding(input) == binding end
  local function bindInput(actions)
    trackConn(UIS.InputBegan:Connect(function(input, gameProcessed)
      local gamepad = input.UserInputType.Name:match("^Gamepad") ~= nil
      if (input.KeyCode == Enum.KeyCode.ButtonSelect or input.KeyCode == Enum.KeyCode.Menu) and not UIState.keyCapture and not UIS:GetFocusedTextBox() then context.window.toggle(); return end
      if UIState.panelOpen and gamepad and not UIState.keyCapture then return end
      if
        gameProcessed
        or UIState.keyCapture
        or context.kit.isCapturing(input)
        or UIS:GetFocusedTextBox()
        or (not UIState.desktop and not gamepad)
        or not inputBinding(input)
      then
        return
      end
      if UIState.closing then return end
      local config = Utils.getConfig() or {}
      if context.phantomBall ~= false and config.DynamicParry == true and isKey(input, config.DynamicParryKey) then return end
      if isKey(input, config.Keybind) then
        actions.triggerShortcut(inputBinding(input))
      elseif context.phantomBall ~= false and isKey(input, config.SpamKeybind) then
        if config.ManualSpamMode == "Hold" then
          if not UIState.manualHoldInput then UIState.manualHoldInput = input; context.floating.setSpam(true) end
        else
          context.floating.setSpam(not UIState.spamOn)
        end
      else
        actions.triggerShortcut(inputBinding(input))
      end
    end))
    trackConn(UIS.InputEnded:Connect(function(input)
      local held = UIState.manualHoldInput
      if held and (held == input or (inputBinding(held) and inputBinding(held) == inputBinding(input))) then UIState.manualHoldInput = nil; context.floating.setSpam(false) end
    end))
    trackConn(UIS.WindowFocusReleased:Connect(function()
      if UIState.manualHoldInput then UIState.manualHoldInput = nil; context.floating.setSpam(false) end
    end))
  end
  local gui = game:GetService("GuiService"); local previousSelection = gui.SelectedObject
  local function visible(object)
    if not object or not object.Parent then return false end
    local parent = object
    while parent and parent ~= context.refs.screenGui do
      if parent:IsA("GuiObject") and not parent.Visible then return false end
      parent = parent.Parent
    end
    return parent == context.refs.screenGui
  end
  local savedNavigation = {}
  for _, property in ipairs({ "GuiNavigationEnabled", "AutoSelectGuiEnabled" }) do
    local ok, value = pcall(function() return gui[property] end)
    if ok then savedNavigation[property] = value end
  end
  local navigationOwned = false
  local function setNavigation(value)
    if value == navigationOwned then return end
    navigationOwned = value
    for property, previous in pairs(savedNavigation) do
      pcall(function() gui[property] = value and true or previous end)
    end
  end
  local controllerNavigation = UIS.GamepadEnabled
  local function focusFirst()
    local panel = context.refs.configPanel
    if not panel then return end
    for _, item in ipairs(panel:GetDescendants()) do
      if item:IsA("GuiButton") and item.Selectable and item.Active and visible(item) then gui.SelectedObject = item; return end
    end
  end
  trackConn(
    UIS.LastInputTypeChanged:Connect(function(kind) controllerNavigation = kind.Name:match("^Gamepad") ~= nil or kind == Enum.UserInputType.Keyboard end)
  )
  trackConn(context.services.RunService.Heartbeat:Connect(function()
    local selected = gui.SelectedObject; setNavigation(UIState.panelOpen and controllerNavigation)
    if UIState.panelOpen and controllerNavigation then
      if not visible(selected) then focusFirst() end
    elseif selected and selected:IsDescendantOf(context.refs.screenGui) then
      gui.SelectedObject = nil
    end
  end))
  context.scope.add(function()
    setNavigation(false); local selected = gui.SelectedObject
    if selected and selected:IsDescendantOf(context.refs.screenGui) then gui.SelectedObject = previousSelection and previousSelection.Parent and previousSelection or nil end
  end)
  bindInput(context.actions); return {}
end

-- contract
Controller.__contract = { provides = { "setup", "create" }, requires = {} }

return Controller
