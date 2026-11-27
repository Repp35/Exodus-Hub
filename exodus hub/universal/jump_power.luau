-- [[ jump power ]]
--!optimize 2
-- @modules jumppower

local JumpPower = {}
local controller, binding
local CONFIG = {
  persistent = { UniversalJumpPowerEnabled = false },
  schema = { UniversalJumpPowerEnabled = "boolean", UniversalJumpPower = "rate" },
  defaults = { UniversalJumpPowerEnabled = false },
  resolveDefaults = function(context)
    local player = context and context.player or game:GetService("Players").LocalPlayer
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local workspace = game:GetService("Workspace")
    local starter = game:GetService("StarterPlayer")
    local power = humanoid and humanoid.JumpPower or starter.CharacterJumpPower
    local usePower = humanoid and humanoid.UseJumpPower
    if not humanoid then
      usePower = starter.CharacterUseJumpPower
    end
    if usePower == false then
      local height = humanoid and humanoid.JumpHeight or starter.CharacterJumpHeight
      power = math.sqrt(math.max(0, 2 * workspace.Gravity * height))
    end
    return { UniversalJumpPower = type(power) == "number" and power or 50 }
  end,
}
function JumpPower.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function JumpPower.setValue(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setValue(value)
end
function JumpPower.teardown()
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
function JumpPower.setup(deps)
  JumpPower.teardown()
  local utils = deps.Utils
  binding = deps.Properties.create(utils, function(humanoid, originals)
    local value = math.clamp(tonumber(utils.getConfigValue("UniversalJumpPower")) or 50, 0, 300)
    local usePower = originals.UseJumpPower
    if usePower == nil then
      usePower = humanoid.UseJumpPower
    end
    if usePower then
      return { JumpPower = value }
    end
    local gravity = game:GetService("Workspace").Gravity
    if gravity <= 0 then
      return { UseJumpPower = true, JumpPower = value }
    end
    return { JumpHeight = value * value / (2 * gravity) }
  end)
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "UniversalJumpPowerEnabled",
    valueKey = "UniversalJumpPower",
    min = 0,
    max = 300,
    start = function(scope) deps.Controller.connectPhysics(scope, binding.update) end,
    stop = binding.restore,
    update = binding.update,
  })
  return controller.sync()
end
JumpPower.__config = CONFIG
JumpPower.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Properties = "characterproperties" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
    Properties = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}
return JumpPower
