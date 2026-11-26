-- [[ infinite zoom ]]
--!optimize 2
-- @modules infinitezoom

local InfiniteZoom = {}
local controller, player, original, writing
local CONFIG = { schema = { UniversalInfiniteZoom = "boolean" }, defaults = { UniversalInfiniteZoom = false } }
local function apply()
  if not player or writing then
    return
  end
  writing = true
  player.CameraMaxZoomDistance = 1000000
  writing = false
end
local function restore()
  if player and original ~= nil and player.CameraMaxZoomDistance == 1000000 then
    player.CameraMaxZoomDistance = original
  end
  player, original = nil, nil
end
function InfiniteZoom.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function InfiniteZoom.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  restore()
  return true
end
function InfiniteZoom.setup(deps)
  InfiniteZoom.teardown()
  controller = deps.Controller.create(deps.Utils, deps.Lifetime, {
    key = "UniversalInfiniteZoom",
    start = function(scope)
      player = assert(deps.Utils.getLocalPlayer(), "LocalPlayer indisponível")
      original = player.CameraMaxZoomDistance
      scope.connect(player:GetPropertyChangedSignal("CameraMaxZoomDistance"), function()
        if not writing and player.CameraMaxZoomDistance ~= 1000000 then
          original = player.CameraMaxZoomDistance
          apply()
        end
      end)
      apply()
    end,
    stop = restore,
  })
  return controller.sync()
end
InfiniteZoom.__config = CONFIG
InfiniteZoom.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}
return InfiniteZoom
