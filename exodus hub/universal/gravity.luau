-- [[ gravity ]]
--!optimize 2
-- @modules gravity

local Gravity = {}

local Utils
local controller

-- configuration
local CONFIG = {
  schema = {
    UniversalGravityEnabled = "boolean",
    UniversalGravity = "rate",
  },
  defaults = { UniversalGravityEnabled = false },
  resolveDefaults = function() return { UniversalGravity = game:GetService("Workspace").Gravity or 196.2 } end,
}

local Workspace = game:GetService("Workspace")
local gravityValue
local enabledState = false
local gravityRoot
local attachment
local force
local function clearGravity()
  if force then
    force:Destroy()
    force = nil
  end
  if attachment then
    attachment:Destroy()
    attachment = nil
  end
  gravityRoot = nil
end
local function updateGravity()
  if not Utils or not enabledState then
    return
  end
  local player = Utils.getLocalPlayer()
  local character = player and player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not humanoid or humanoid.Health <= 0 or not root or not root.Parent then
    clearGravity()
    return
  end
  if gravityRoot ~= root or not force or not force.Parent or not attachment or not attachment.Parent then
    clearGravity()
    gravityRoot = root
    attachment = Instance.new("Attachment")
    attachment.Name = "ExodusGravityAttachment"
    attachment.Parent = root
    force = Instance.new("VectorForce")
    force.Name = "ExodusGravityForce"
    force.Attachment0 = attachment
    force.RelativeTo = Enum.ActuatorRelativeTo.World
    force.ApplyAtCenterOfMass = true
    force.Parent = root
  end
  local mass = root.AssemblyMass
  local compensation = (not root.Anchored and mass == mass and mass < math.huge) and mass * (Workspace.Gravity - gravityValue) or 0
  local desired = Vector3.new(0, compensation, 0)
  if force.Force ~= desired then
    force.Force = desired
  end
end
function Gravity.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function Gravity.setValue(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setValue(value)
end
function Gravity.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  clearGravity()
  enabledState, Utils = false, nil
  return true
end
function Gravity.setup(deps)
  Gravity.teardown()
  Utils = deps.Utils
  gravityValue = tonumber(Utils.getConfigValue("UniversalGravity")) or Workspace.Gravity
  controller = deps.Controller.create(Utils, deps.Lifetime, {
    key = "UniversalGravityEnabled",
    valueKey = "UniversalGravity",
    min = 0,
    max = 400,
    start = function(scope)
      enabledState = true
      deps.Controller.connectPhysics(scope, updateGravity)
    end,
    stop = function()
      enabledState = false
      clearGravity()
    end,
    update = function()
      gravityValue = math.clamp(tonumber(Utils.getConfigValue("UniversalGravity")) or Workspace.Gravity, 0, 400)
      updateGravity()
    end,
  })
  return controller.sync()
end
Gravity.__config = CONFIG

-- contract
Gravity.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
  },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}

return Gravity
