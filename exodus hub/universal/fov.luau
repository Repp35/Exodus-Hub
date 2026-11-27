-- [[ fov ]]
--!optimize 2
-- @modules fov

local FOV = {}
local controller, binding
local Workspace = game:GetService("Workspace")
local CONFIG = {
  schema = { UniversalFOVEnabled = "boolean", UniversalFOV = "rate" },
  defaults = { UniversalFOVEnabled = false },
  resolveDefaults = function()
    local camera = Workspace.CurrentCamera
    return { UniversalFOV = camera and camera.FieldOfView or 70 }
  end,
}
function FOV.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function FOV.setValue(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setValue(value)
end
function FOV.teardown()
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
function FOV.setup(deps)
  FOV.teardown()
  local utils = deps.Utils
  local values = {}
  binding = deps.Binding.create(function() return Workspace.CurrentCamera end, function()
    values.FieldOfView = math.clamp(tonumber(utils.getConfigValue("UniversalFOV")) or 70, 1, 120)
    return values
  end)
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "UniversalFOVEnabled",
    valueKey = "UniversalFOV",
    min = 1,
    max = 120,
    start = function(scope) deps.Controller.connectPhysics(scope, binding.update) end,
    stop = binding.restore,
    update = binding.update,
  })
  return controller.sync()
end
FOV.__config = CONFIG
FOV.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Binding = "propertybinding" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
    Binding = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}
return FOV
