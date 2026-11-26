-- [[ fly ]]
--!optimize 2
-- @modules fly

local Fly = {}

local Utils
local controller

-- configuration
local CONFIG = {
  schema = {
    UniversalFly = "boolean",
    UniversalFlySpeed = "rate",
  },
  defaults = {
    UniversalFly = false,
    UniversalFlySpeed = 1,
  },
}

local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local states = { Fly = false }
local epoch = 0
local flyCharacter
local flyHumanoid
local flyRoot
local flyVelocity
local flyGyro
local flyPlatformStand
local flyAutoRotate
local playerControls
local playerControlsModule
local pressedKeys = {}
local controls = { Forward = 0, Backward = 0, Left = 0, Right = 0, Up = 0, Down = 0 }
local bindings = {
  [Enum.KeyCode.W] = { "Forward", 1 },
  [Enum.KeyCode.S] = { "Backward", -1 },
  [Enum.KeyCode.A] = { "Left", -1 },
  [Enum.KeyCode.D] = { "Right", 1 },
  [Enum.KeyCode.E] = { "Up", 1 },
  [Enum.KeyCode.Q] = { "Down", -1 },
  [Enum.KeyCode.Space] = { "Up", 1 },
  [Enum.KeyCode.LeftControl] = { "Down", -1 },
}

local connections = {}
local connectionPool
local function disconnect(name)
  if connectionPool then
    connectionPool.disconnect(name)
  end
end
local function connect(name, signal, callback) return connectionPool.connect(name, signal, callback) end
local function disconnectPrefix(prefix)
  for name in pairs(connections) do
    if name:sub(1, #prefix) == prefix then
      disconnect(name)
    end
  end
end
local function destroy(object)
  if object then
    pcall(object.Destroy, object)
  end
end
local function clearControls()
  table.clear(pressedKeys)
  for key in pairs(controls) do
    controls[key] = 0
  end
end
local function detachFly()
  if flyRoot and flyRoot.Parent then
    pcall(function() flyRoot.AssemblyLinearVelocity = Vector3.zero end)
  end
  destroy(flyVelocity)
  destroy(flyGyro)
  if flyHumanoid and flyHumanoid.Parent then
    pcall(function()
      if flyPlatformStand ~= nil then
        flyHumanoid.PlatformStand = flyPlatformStand
      end
      if flyAutoRotate ~= nil then
        flyHumanoid.AutoRotate = flyAutoRotate
      end
    end)
  end
  flyCharacter, flyHumanoid, flyRoot, flyVelocity, flyGyro = nil, nil, nil, nil, nil
  flyPlatformStand, flyAutoRotate = nil, nil
end
local function flyCharacterReady()
  local player = Utils.getLocalPlayer()
  local character = player and player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not character or not humanoid or humanoid.Health <= 0 or not root then
    detachFly()
    return nil
  end
  if flyCharacter ~= character or flyHumanoid ~= humanoid or flyRoot ~= root then
    detachFly()
    flyCharacter, flyHumanoid, flyRoot = character, humanoid, root
    flyPlatformStand, flyAutoRotate = humanoid.PlatformStand, humanoid.AutoRotate
  end
  if not flyVelocity or not flyVelocity.Parent then
    flyVelocity = Instance.new("BodyVelocity")
    flyVelocity.Name = "ExodusFlyVelocity"
    flyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyVelocity.P = 9e4
    flyVelocity.Parent = root
  end
  if not flyGyro or not flyGyro.Parent then
    flyGyro = Instance.new("BodyGyro")
    flyGyro.Name = "ExodusFlyGyro"
    flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyGyro.P = 9e4
    flyGyro.D = 1000
    flyGyro.Parent = root
  end
  return humanoid
end
local function getPlayerControls()
  if playerControls and playerControlsModule and playerControlsModule.Parent then
    return playerControls
  end
  local player = Utils.getLocalPlayer()
  local scripts = player and player:FindFirstChild("PlayerScripts")
  local module = scripts and scripts:FindFirstChild("PlayerModule")
  if not module then
    return nil
  end
  local owner = epoch
  local ok, value = pcall(require, module)
  if owner ~= epoch or not Utils or not states.Fly then
    return nil
  end
  if ok and type(value) == "table" and type(value.GetControls) == "function" then
    local ready, result = pcall(value.GetControls, value)
    if owner == epoch and Utils and states.Fly and ready and result and type(result.GetMoveVector) == "function" then
      playerControls, playerControlsModule = result, module
    end
  end
  return playerControls
end
local function updateFly()
  if not Utils or not states.Fly then
    return
  end
  local owner = epoch
  local humanoid = flyCharacterReady()
  local camera = Workspace.CurrentCamera
  if not humanoid or not camera then
    return
  end
  local direction
  local typing = UIS:GetFocusedTextBox() ~= nil
  if typing then
    clearControls()
  end
  if typing then
    direction = Vector3.zero
  elseif UIS.TouchEnabled and UIS:GetLastInputType() == Enum.UserInputType.Touch then
    local controller = getPlayerControls()
    if controller then
      local movement = controller:GetMoveVector()
      direction = camera.CFrame.RightVector * movement.X - camera.CFrame.LookVector * movement.Z
    else
      direction = humanoid.MoveDirection
    end
  else
    direction = camera.CFrame.LookVector * (controls.Forward + controls.Backward)
      + camera.CFrame.RightVector * (controls.Left + controls.Right)
      + Vector3.new(0, controls.Up + controls.Down, 0)
  end
  if owner ~= epoch or not states.Fly or not Utils or humanoid ~= flyHumanoid or not flyRoot or not flyRoot.Parent then
    return
  end
  if direction.Magnitude > 1 then
    direction = direction.Unit
  end
  local speed = math.clamp(tonumber(Utils.getConfigValue("UniversalFlySpeed")) or 1, 0.1, 10)
  local velocity = direction * speed * 50
  if not flyVelocity or not flyVelocity.Parent or not flyGyro or not flyGyro.Parent then
    return
  end
  flyVelocity.Velocity = velocity
  flyRoot.AssemblyLinearVelocity = velocity
  flyGyro.CFrame = camera.CFrame
  humanoid.PlatformStand = true
  humanoid.AutoRotate = false
end
local function startFly(scope, connectPhysics)
  connect("FlyBegan", UIS.InputBegan, function(input, processed)
    if processed then
      return
    end
    local binding = bindings[input.KeyCode]
    if binding then
      pressedKeys[input.KeyCode] = true
      controls[binding[1]] = binding[2]
    end
  end)
  connect("FlyEnded", UIS.InputEnded, function(input)
    local binding = bindings[input.KeyCode]
    if binding then
      pressedKeys[input.KeyCode] = nil
      controls[binding[1]] = 0
      for key in pairs(pressedKeys) do
        local held = bindings[key]
        if held and held[1] == binding[1] then
          controls[held[1]] = held[2]
          break
        end
      end
    end
  end)
  connect("FlyFocus", UIS.WindowFocusReleased, clearControls)
  connectPhysics(scope, updateFly)
  updateFly()
  return true
end
local function stopFly()
  epoch += 1
  disconnectPrefix("Fly")
  clearControls()
  detachFly()
  playerControls, playerControlsModule = nil, nil
  return true
end
function Fly.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function Fly.setValue(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setValue(value)
end
function Fly.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  stopFly()
  states.Fly = false
  if connectionPool then
    connectionPool.destroy()
    connectionPool = nil
  end
  Utils = nil
  return true
end
function Fly.setup(deps)
  Fly.teardown()
  Utils = deps.Utils
  connectionPool = deps.Lifetime.connections(Utils)
  connections = connectionPool.connections
  controller = deps.Controller.create(Utils, deps.Lifetime, {
    key = "UniversalFly",
    valueKey = "UniversalFlySpeed",
    min = 0.1,
    max = 10,
    start = function(scope)
      states.Fly = true
      assert(startFly(scope, deps.Controller.connectPhysics), "sinal de física indisponível")
    end,
    stop = function()
      states.Fly = false
      stopFly()
    end,
    update = updateFly,
  })
  return controller.sync()
end
Fly.__config = CONFIG

-- contract
Fly.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Lifetime = { "connections", "scope" },
    Controller = { "create", "connectPhysics" },
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
  },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}

return Fly
