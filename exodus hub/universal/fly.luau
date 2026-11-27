-- [[ fly ]]
--!optimize 2
-- @modules fly

local Fly = {}
local utils, controller, activation
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local enabled, generation = false, 0
local character, humanoid, root, velocity, gyro, saved
local attachThread, pendingCharacter, controlsThread, controlModule, controlSource
local retryAt, controlRetryAt, lastErrorAt = 0, 0, -math.huge
local pressed = {}
local directionKeys = { Forward = 0, Backward = 0, Left = 0, Right = 0, Up = 0, Down = 0 }
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
local CONFIG = {
  persistent = { UniversalFly = false },
  schema = { UniversalFly = "boolean", UniversalFlySpeed = "rate" },
  defaults = { UniversalFly = false, UniversalFlySpeed = 1 },
}
local function clearControls()
  table.clear(pressed)
  for key in pairs(directionKeys) do
    directionKeys[key] = 0
  end
end
local function destroy(object)
  if object then
    pcall(object.Destroy, object)
  end
end
local function cancelAttach()
  local thread = attachThread
  attachThread, pendingCharacter = nil, nil
  if thread then
    pcall(task.cancel, thread)
  end
end
local function detach()
  destroy(velocity)
  destroy(gyro)
  if root and root.Parent then
    pcall(function()
      root.AssemblyLinearVelocity = Vector3.zero
      root.AssemblyAngularVelocity = Vector3.zero
    end)
  end
  if humanoid and humanoid.Parent and saved then
    pcall(function()
      humanoid.PlatformStand = saved.PlatformStand
      humanoid.AutoRotate = saved.AutoRotate
    end)
  end
  character, humanoid, root, velocity, gyro, saved = nil, nil, nil, nil, nil, nil
end
local function report(reason)
  if utils and os.clock() - lastErrorAt >= 5 then
    lastErrorAt = os.clock()
    utils.recordError("Fly", tostring(reason))
  end
end
local function attach(model, human, part)
  detach()
  character, humanoid, root = model, human, part
  saved = { PlatformStand = human.PlatformStand, AutoRotate = human.AutoRotate }
  destroy(part:FindFirstChild("ExodusFlyVelocity"))
  destroy(part:FindFirstChild("ExodusFlyGyro"))
  velocity = Instance.new("BodyVelocity")
  velocity.Name = "ExodusFlyVelocity"
  velocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
  velocity.P = 9e4
  velocity.Velocity = Vector3.zero
  velocity.Parent = part
  gyro = Instance.new("BodyGyro")
  gyro.Name = "ExodusFlyGyro"
  gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
  gyro.P, gyro.D = 9e4, 1000
  gyro.CFrame = part.CFrame
  gyro.Parent = part
  human.PlatformStand, human.AutoRotate = true, false
end
local function queueAttach(model)
  if not enabled or not model or not activation or not activation.alive or pendingCharacter == model and attachThread then
    return
  end
  generation += 1
  local token, owner = generation, activation
  cancelAttach()
  pendingCharacter = model
  local thread
  thread = task.defer(function()
    local part = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 10)
    local human = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
    if attachThread == thread then
      attachThread, pendingCharacter = nil, nil
    end
    if not enabled or not owner.alive or generation ~= token or utils.getLocalPlayer().Character ~= model then
      return
    end
    if not part or not part:IsA("BasePart") or not human or not human:IsA("Humanoid") or human.Health <= 0 then
      return
    end
    local ok, reason = pcall(attach, model, human, part)
    if not ok then
      detach()
      retryAt = os.clock() + 0.5
      report(reason)
    end
  end)
  attachThread = thread
end
local function loadControls()
  if controlsThread or os.clock() < controlRetryAt or not activation or not activation.alive then
    return
  end
  if controlModule and controlSource and controlSource.Parent then
    return
  end
  controlModule, controlSource = nil, nil
  controlRetryAt = os.clock() + 0.5
  local owner = activation
  local thread
  thread = task.defer(function()
    local player = utils and utils.getLocalPlayer()
    local scripts = player and player:FindFirstChild("PlayerScripts")
    local module = scripts and scripts:FindFirstChild("PlayerModule")
    local source = module and module:FindFirstChild("ControlModule")
    local ok, result = false, nil
    if source and source:IsA("ModuleScript") then
      ok, result = pcall(require, source)
    elseif module and module:IsA("ModuleScript") then
      source = module
      local ready, api = pcall(require, module)
      if ready and type(api) == "table" and type(api.GetControls) == "function" then
        ok, result = pcall(api.GetControls, api)
      end
    end
    if controlsThread == thread then
      controlsThread = nil
    end
    if owner.alive and activation == owner and ok and source and source.Parent and type(result) == "table" and type(result.GetMoveVector) == "function" then
      controlModule, controlSource = result, source
    end
  end)
  controlsThread = thread
end
local function direction(camera)
  if UIS:GetFocusedTextBox() then
    clearControls()
    return Vector3.zero
  end
  local vertical = Vector3.new(0, directionKeys.Up + directionKeys.Down, 0)
  if UIS.TouchEnabled or UIS.GamepadEnabled then
    loadControls()
    if controlModule then
      local ok, move = pcall(controlModule.GetMoveVector, controlModule)
      if ok and typeof(move) == "Vector3" then
        return camera.CFrame.RightVector * move.X - camera.CFrame.LookVector * move.Z + vertical
      end
      controlModule, controlSource = nil, nil
    end
    if humanoid and humanoid.MoveDirection.Magnitude > 0 then
      return humanoid.MoveDirection + vertical
    end
  end
  return camera.CFrame.LookVector * (directionKeys.Forward + directionKeys.Backward)
    + camera.CFrame.RightVector * (directionKeys.Left + directionKeys.Right)
    + vertical
end
local function update()
  if not enabled or not utils then
    return
  end
  local model = utils.getLocalPlayer().Character
  if
    model ~= character
    or not root
    or root.Parent ~= model
    or not humanoid
    or humanoid.Parent ~= model
    or humanoid.Health <= 0
    or not velocity
    or not velocity.Parent
    or not gyro
    or not gyro.Parent
  then
    detach()
    if model and not attachThread and os.clock() >= retryAt then
      local human = model:FindFirstChildOfClass("Humanoid")
      if not human or human.Health > 0 then
        queueAttach(model)
      end
    end
    return
  end
  local camera = Workspace.CurrentCamera
  if not camera then
    velocity.Velocity = Vector3.zero
    return
  end
  local move = direction(camera)
  if move.Magnitude > 1 then
    move = move.Unit
  end
  local speed = math.clamp(tonumber(utils.getConfigValue("UniversalFlySpeed")) or 1, 0.1, 10)
  velocity.Velocity = move * speed * 50
  gyro.CFrame = camera.CFrame
  if not humanoid.PlatformStand then
    humanoid.PlatformStand = true
  end
  if humanoid.AutoRotate then
    humanoid.AutoRotate = false
  end
end
local function stop()
  enabled = false
  generation += 1
  cancelAttach()
  local thread = controlsThread
  controlsThread = nil
  if thread then
    pcall(task.cancel, thread)
  end
  detach()
  clearControls()
  activation, controlModule, controlSource = nil, nil, nil
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
  stop()
  utils = nil
  return true
end
function Fly.setup(deps)
  Fly.teardown()
  utils = deps.Utils
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "UniversalFly",
    valueKey = "UniversalFlySpeed",
    min = 0.1,
    max = 10,
    start = function(scope)
      activation, enabled = scope, true
      retryAt, controlRetryAt = 0, 0
      scope.connect(UIS.InputBegan, function(input, processed)
        local binding = bindings[input.KeyCode]
        if not processed and binding then
          pressed[input.KeyCode] = true
          directionKeys[binding[1]] = binding[2]
        end
      end)
      scope.connect(UIS.InputEnded, function(input)
        local binding = bindings[input.KeyCode]
        if binding then
          pressed[input.KeyCode] = nil
          directionKeys[binding[1]] = 0
          for key in pairs(pressed) do
            local held = bindings[key]
            if held and held[1] == binding[1] then
              directionKeys[held[1]] = held[2]
              break
            end
          end
        end
      end)
      scope.connect(UIS.WindowFocusReleased, clearControls)
      local player = utils.getLocalPlayer()
      scope.connect(player.CharacterAdded, queueAttach)
      scope.connect(player.CharacterRemoving, function(model)
        generation += 1
        cancelAttach()
        if model == character then
          detach()
        end
        clearControls()
      end)
      deps.Controller.connectPhysics(scope, function()
        local ok, reason = pcall(update)
        if not ok then
          detach()
          retryAt = os.clock() + 0.5
          report(reason)
        end
      end)
      queueAttach(player.Character)
      loadControls()
    end,
    stop = stop,
  })
  return controller.sync()
end
Fly.__config = CONFIG
Fly.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
  },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}
return Fly
