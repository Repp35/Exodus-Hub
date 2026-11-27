-- [[ gravity ]]
--!optimize 2
-- @modules gravity

local Gravity = {}
local controller, binding
local Workspace = game:GetService("Workspace")
local CONFIG = {
  persistent = { UniversalGravityEnabled = false },
  schema = { UniversalGravityEnabled = "boolean", UniversalGravity = "rate" },
  defaults = { UniversalGravityEnabled = false },
  resolveDefaults = function() return { UniversalGravity = Workspace.Gravity or 196.2 } end,
}
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
  if binding then
    binding.restore()
    binding = nil
  end
  return true
end
function Gravity.setup(deps)
  Gravity.teardown()
  local utils = deps.Utils
  local values = {}
  binding = deps.Binding.create(function() return Workspace end, function()
    values.Gravity = math.clamp(tonumber(utils.getConfigValue("UniversalGravity")) or 196.2, 0, 400)
    return values
  end)
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "UniversalGravityEnabled",
    valueKey = "UniversalGravity",
    min = 0,
    max = 400,
    start = function(scope) deps.Controller.connectPhysics(scope, binding.update) end,
    stop = binding.restore,
    update = binding.update,
  })
  return controller.sync()
end
Gravity.__config = CONFIG
Gravity.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Binding = "propertybinding" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
    Binding = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled", "setValue" },
}
return Gravity
