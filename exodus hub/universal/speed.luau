-- [[ speed ]]
--!optimize 2
-- @modules speed

local Speed = {}
local controller, binding
local CONFIG = {
  schema = { UniversalSpeedEnabled = "boolean", UniversalSpeed = "rate" },
  defaults = { UniversalSpeedEnabled = false },
  resolveDefaults = function(context)
    local player = context and context.player or game:GetService("Players").LocalPlayer
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local value = humanoid and humanoid.WalkSpeed or game:GetService("StarterPlayer").CharacterWalkSpeed
    return { UniversalSpeed = type(value) == "number" and value or 16 }
  end,
}
function Speed.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function Speed.setValue(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setValue(value)
end
function Speed.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  if binding then
    binding.restore()
    binding = nil
  end
  return true
end
function Speed.setup(deps)
  Speed.teardown()
  local utils = deps.Utils
  binding = deps.Properties.create(utils, function(humanoid)
    local value = math.clamp(tonumber(utils.getConfigValue("UniversalSpeed")) or 16, 0, 200)
    return { WalkSpeed = value }
  end)
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "UniversalSpeedEnabled",
    valueKey = "UniversalSpeed",
    min = 0,
    max = 200,
    start = function(scope) deps.Controller.connectPhysics(scope, binding.update) end,
    stop = binding.restore,
    update = binding.update,
  })
  return controller.sync()
end
Speed.__config = CONFIG
Speed.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Properties = "characterproperties" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
    Properties = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}
return Speed
