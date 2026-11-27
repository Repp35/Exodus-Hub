-- [[ infinite zoom ]]
--!optimize 2
-- @modules infinitezoom
local InfiniteZoom = {}
local controller, binding, player, originalMin, originalMax
local CONFIG = { schema = { UniversalInfiniteZoom = "boolean" }, defaults = { UniversalInfiniteZoom = false } }
local function restore()
  if player and originalMax ~= nil then
    if player.CameraMinZoomDistance > originalMax then
      player.CameraMinZoomDistance = math.min(originalMin, originalMax)
    end
  end
  if binding then binding.restore() end
  player, originalMin, originalMax = nil, nil, nil
end
function InfiniteZoom.setEnabled(value)
  if not controller then return false, "recurso indisponível" end
  return controller.setEnabled(value)
end
function InfiniteZoom.teardown()
  if controller then controller.destroy(); controller = nil end
  restore()
  binding = nil
  return true
end
function InfiniteZoom.setup(deps)
  InfiniteZoom.teardown()
  binding = deps.Binding.create(function() return player end, function() return { CameraMaxZoomDistance = 1000000 } end)
  controller = deps.Controller.create(deps.Utils, deps.Lifetime, {
    key = "UniversalInfiniteZoom",
    start = function(scope)
      player = assert(deps.Utils.getLocalPlayer(), "LocalPlayer indisponível")
      originalMin, originalMax = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
      deps.Controller.connectPhysics(scope, binding.update)
      binding.update()
    end,
    stop = restore,
  })
  return controller.sync()
end
InfiniteZoom.__config = CONFIG
InfiniteZoom.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Binding = "propertybinding" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
    Binding = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}
return InfiniteZoom
