-- [[ fullbright ]]
--!optimize 2
-- @modules fullbright

local Fullbright = {}
local controller, binding
local Lighting = game:GetService("Lighting")
local CONFIG = { schema = { UniversalFullbright = "boolean" }, defaults = { UniversalFullbright = false } }
function Fullbright.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function Fullbright.teardown()
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
function Fullbright.setup(deps)
  Fullbright.teardown()
  local values = {
    Brightness = 2,
    ClockTime = 14,
    Ambient = Color3.fromRGB(255, 255, 255),
    OutdoorAmbient = Color3.fromRGB(255, 255, 255),
    GlobalShadows = false,
    ExposureCompensation = 0,
  }
  binding = deps.Binding.create(function() return Lighting end, function() return values end)
  controller = deps.Controller.create(deps.Utils, deps.Lifetime, {
    key = "UniversalFullbright",
    start = function(scope) deps.Controller.connectPhysics(scope, binding.update) end,
    stop = binding.restore,
    update = binding.update,
  })
  return controller.sync()
end
Fullbright.__config = CONFIG
Fullbright.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Binding = "propertybinding" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
    Binding = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}
return Fullbright
