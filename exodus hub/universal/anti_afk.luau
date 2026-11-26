-- [[ anti afk ]]
--!optimize 2
-- @modules antiafk

local AntiAFK = {}
local controller
local CONFIG = { schema = { AntiAFK = "boolean" }, defaults = { AntiAFK = true } }
function AntiAFK.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function AntiAFK.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  return true
end
function AntiAFK.setup(deps)
  AntiAFK.teardown()
  local utils = deps.Utils
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "AntiAFK",
    start = function(scope)
      local player = assert(utils.getLocalPlayer(), "LocalPlayer indisponível")
      local lastError = -math.huge
      scope.connect(player.Idled, function()
        local ok, reason = pcall(function()
          local virtualUser = game:GetService("VirtualUser")
          virtualUser:CaptureController()
          virtualUser:ClickButton2(Vector2.zero)
        end)
        if ok then
          return
        end
        local fallback, detail = pcall(function()
          local input = game:GetService("VirtualInputManager")
          input:SendMouseButtonEvent(0, 0, 1, true, game, 0)
          input:SendMouseButtonEvent(0, 0, 1, false, game, 0)
        end)
        if not fallback and os.clock() - lastError >= 30 then
          lastError = os.clock()
          utils.recordError("AntiAFK", tostring(reason) .. " | " .. tostring(detail))
        end
      end)
    end,
  })
  return controller.sync()
end
AntiAFK.__config = CONFIG
AntiAFK.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}
return AntiAFK
