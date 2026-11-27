-- [[ infinitejump ]]
--!optimize 2
-- @modules infinitejump

local InfiniteJump = {}

local Utils
local hub
local controller
local requested = false

-- configuration
local CONFIG = {
  schema = { UniversalInfiniteJump = "boolean" },
  defaults = { UniversalInfiniteJump = false },
}

local UIS = game:GetService("UserInputService")
local states = { InfiniteJump = false }
local connectionPool
local function disconnect(name)
  if connectionPool then
    connectionPool.disconnect(name)
  end
end
local function connect(name, signal, callback) return connectionPool.connect(name, signal, callback) end
local jumpButton
local lastJump = 0
local function jumpInAir()
  if not Utils or not states.InfiniteJump or UIS:GetFocusedTextBox() then
    requested = false
    return
  end
  local player = Utils.getLocalPlayer()
  local character = player and player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  if not humanoid or humanoid.Health <= 0 or humanoid.Sit then
    requested = false
    return
  end
  local now = os.clock()
  if now - lastJump < 0.05 then
    return
  end
  requested = false
  lastJump = now
  humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end
local function requestJump() requested = true end
local function attachJumpButton()
  if not Utils or not states.InfiniteJump then
    return
  end
  local button = hub.getJumpButton()
  if not button then
    local player = Utils.getLocalPlayer()
    local gui = player and player:FindFirstChildOfClass("PlayerGui")
    local touch = gui and gui:FindFirstChild("TouchGui")
    local frame = touch and touch:FindFirstChild("TouchControlFrame")
    button = frame and frame:FindFirstChild("JumpButton")
  end
  if button == jumpButton then
    return
  end
  disconnect("GameJump")
  jumpButton = button
  if button and button:IsA("GuiButton") then
    connect("GameJump", button.MouseButton1Down, requestJump)
  end
end
local function startInfiniteJump()
  lastJump = 0
  connect("InfiniteJump", UIS.JumpRequest, requestJump)
  local player = Utils.getLocalPlayer()
  local gui = player and player:FindFirstChildOfClass("PlayerGui")
  if gui then
    local queued = false
    connect("JumpGuiAdded", gui.DescendantAdded, function()
      if queued then
        return
      end
      queued = true
      task.defer(function()
        queued = false
        attachJumpButton()
      end)
    end)
    connect("JumpGuiRemoving", gui.DescendantRemoving, function(object)
      if object == jumpButton then
        disconnect("GameJump")
        jumpButton = nil
      end
    end)
  end
  attachJumpButton()
  return true
end
local function stopInfiniteJump()
  disconnect("InfiniteJump")
  disconnect("GameJump")
  disconnect("JumpGuiAdded")
  disconnect("JumpGuiRemoving")
  jumpButton = nil
  return true
end
function InfiniteJump.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function InfiniteJump.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  stopInfiniteJump()
  states.InfiniteJump = false
  if connectionPool then
    connectionPool.destroy()
    connectionPool = nil
  end
  Utils, hub = nil, nil
  return true
end
function InfiniteJump.setup(deps)
  InfiniteJump.teardown()
  Utils, hub = deps.Utils, deps.Hub
  connectionPool = deps.Lifetime.connections(Utils)
  controller = deps.Controller.create(Utils, deps.Lifetime, {
    key = "UniversalInfiniteJump",
    start = function(scope)
      states.InfiniteJump = true
      deps.Controller.connectPhysics(scope, function()
        if requested then
          jumpInAir()
        end
      end)
      assert(startInfiniteJump())
    end,
    stop = function()
      requested = false
      states.InfiniteJump = false
      stopInfiniteJump()
    end,
  })
  return controller.sync()
end
InfiniteJump.__config = CONFIG

-- contract
InfiniteJump.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Hub = "hubapi", Controller = "universalcontroller" },
  requiresMethods = {
    Hub = { "getJumpButton" },
    Lifetime = { "connections", "scope" },
    Controller = { "create", "connectPhysics" },
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}

return InfiniteJump
