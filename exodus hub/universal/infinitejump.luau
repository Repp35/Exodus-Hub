-- [[ infinitejump ]]
--!optimize 2
-- @modules infinitejump

local InfiniteJump = {}

local Utils
local hub
local configObserver

-- configuration
local CONFIG = {
  schema = { UniversalInfiniteJump = "boolean" },
  defaults = { UniversalInfiniteJump = false },
}

local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
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
    return
  end
  local player = Utils.getLocalPlayer()
  local character = player and player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not humanoid or humanoid.Health <= 0 or humanoid.Sit or not root or humanoid.FloorMaterial ~= Enum.Material.Air then
    return
  end
  local now = os.clock()
  if now - lastJump < 0.08 then
    return
  end
  local power = humanoid.UseJumpPower and humanoid.JumpPower or math.sqrt(math.max(0, 2 * Workspace.Gravity * humanoid.JumpHeight))
  if power ~= power or power <= 0 or power == math.huge or root.Anchored then
    return
  end
  lastJump = now
  local velocity = root.AssemblyLinearVelocity
  root.AssemblyLinearVelocity = Vector3.new(velocity.X, power, velocity.Z)
  humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end
local function attachJumpButton()
  if not Utils or not states.InfiniteJump then
    return
  end
  local button = hub.getJumpButton()
  if button == jumpButton then
    return
  end
  disconnect("GameJump")
  jumpButton = button
  if button and button:IsA("GuiButton") then
    connect("GameJump", button.MouseButton1Down, jumpInAir)
  end
end
local function startInfiniteJump()
  lastJump = 0
  connect("InfiniteJump", UIS.JumpRequest, jumpInAir)
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
function InfiniteJump.setEnabled(enabled)
  if not Utils then
    return false, "recurso indisponível"
  end
  local value = enabled == true
  if not Utils.setConfig({ UniversalInfiniteJump = value }) then
    return false, "configuração rejeitada"
  end
  if states.InfiniteJump == value then
    return true
  end
  states.InfiniteJump = value
  local ok, result, detail = pcall(value and startInfiniteJump or stopInfiniteJump)
  if not ok or result == false then
    pcall(stopInfiniteJump)
    states.InfiniteJump = false
    Utils.setConfig({ UniversalInfiniteJump = false })
    return false, tostring(ok and (detail or "falha ao alterar recurso") or result)
  end
  return true
end
function InfiniteJump.teardown()
  if configObserver then
    configObserver:Disconnect()
    configObserver = nil
  end
  stopInfiniteJump()
  states.InfiniteJump = false
  if connectionPool then
    connectionPool.destroy()
    connectionPool = nil
  end
  Utils = nil
  return true
end
function InfiniteJump.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then
    return false, "dependência ausente: Utils"
  end
  InfiniteJump.teardown()
  Utils, hub = deps.Utils, deps.Hub
  connectionPool = deps.Lifetime.connections(Utils)
  configObserver = Utils.observeConfig(function(changes)
    if changes.UniversalInfiniteJump ~= nil then
      InfiniteJump.setEnabled(changes.UniversalInfiniteJump == true)
    end
  end)
  if Utils.getConfigValue("UniversalInfiniteJump") == true then
    return InfiniteJump.setEnabled(true)
  end
  return true
end
InfiniteJump.__config = CONFIG

-- contract
InfiniteJump.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Hub = "hubapi" },
  requiresMethods = {
    Hub = { "getJumpButton" },
    Lifetime = { "connections" },
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}

return InfiniteJump
