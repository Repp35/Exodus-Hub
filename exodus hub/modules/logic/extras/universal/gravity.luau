-- [[ gravity ]]

local Gravity = {}
local Utils

-- configuration
local CONFIG = {
  schema = { UniversalGravityEnabled = "boolean", UniversalGravity = "rate" },
  defaults = { UniversalGravityEnabled = false, UniversalGravity = 196.2 },
}

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local gravityDefault, gravityValue
local enabledState = false
local connection, gravityRoot, attachment, force
local function clearGravity()
  if force then force:Destroy(); force = nil end
  if attachment then attachment:Destroy(); attachment = nil end
  gravityRoot = nil
end
local function updateGravity()
  local player = Utils.getLocalPlayer(); local character = player and player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not humanoid or humanoid.Health <= 0 or not root or not root.Parent then clearGravity(); return end
  if gravityRoot ~= root or not force or not force.Parent or not attachment or not attachment.Parent then
    clearGravity(); gravityRoot = root
    attachment = Instance.new("Attachment"); attachment.Name = "ExodusGravityAttachment"; attachment.Parent = root
    force = Instance.new("VectorForce"); force.Name = "ExodusGravityForce"
    force.Attachment0 = attachment; force.RelativeTo = Enum.ActuatorRelativeTo.World; force.ApplyAtCenterOfMass = true; force.Parent = root
  end
  force.Force = Vector3.new(0, root.AssemblyMass * (Workspace.Gravity - gravityValue), 0)
end
local function startGravity()
  local signal = RunService.PreSimulation or RunService.Stepped or RunService.Heartbeat
  if not signal then return false end
  connection = signal:Connect(updateGravity); Utils.trackGlobal(connection); updateGravity(); return true
end
local function stopGravity()
  if connection then Utils.untrackGlobal(connection); connection:Disconnect(); connection = nil end
  clearGravity(); return true
end
function Gravity.setEnabled(enabled)
  if not Utils then return false, "recurso indisponível" end
  local value = enabled == true
  if not Utils.setConfig({ UniversalGravityEnabled = value }) then return false, "configuração rejeitada" end
  if enabledState == value then
    if value then updateGravity() end
    return true
  end
  enabledState = value; local ok, result = pcall(value and startGravity or stopGravity)
  if not ok or result == false then
    enabledState = not value; Utils.setConfig({ UniversalGravityEnabled = not value })
    return false, tostring(result)
  end
  return true
end
function Gravity.setValue(value)
  if not Utils then return false, "controle inválido" end
  local number = tonumber(value)
  if not number or number ~= number then return false, "valor inválido" end
  gravityValue = math.clamp(number, 0, 400)
  if not Utils.setConfig({ UniversalGravity = gravityValue }) then return false end
  if not enabledState then return Gravity.setEnabled(true) end
  updateGravity(); return true
end
function Gravity.teardown()
  if enabledState then stopGravity() end
  enabledState = false; Utils = nil
  return true
end
function Gravity.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then return false, "dependência ausente: Utils" end
  Gravity.teardown(); Utils = deps.Utils
  gravityDefault = Workspace.Gravity; gravityValue = tonumber(Utils.getConfigValue("UniversalGravity")) or gravityDefault
  if Utils.getConfigValue("UniversalGravityEnabled") == true then return Gravity.setEnabled(true) end
  return true
end
Gravity.__config = CONFIG

-- contract
Gravity.__contract = {
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getConfigValue", "setConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal" } },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}

return Gravity
