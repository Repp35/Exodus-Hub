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
      local available, virtualUser = pcall(game.GetService, game, "VirtualUser")
      virtualUser = available and virtualUser or nil
      local pending, releaseThread
      local idle, lastInput, lastError = false, -math.huge, -math.huge
      local function release()
        local value = pending
        pending = nil
        if value then
          pcall(value.User.Button2Up, value.User, value.Position, value.Frame)
        end
      end
      scope.add(function()
        if releaseThread then
          pcall(task.cancel, releaseThread)
          releaseThread = nil
        end
        release()
      end)
      local function sendUser()
        assert(virtualUser, "VirtualUser indisponível")
        virtualUser:CaptureController()
        if type(virtualUser.ClickButton2) == "function" then
          local ok = pcall(virtualUser.ClickButton2, virtualUser, Vector2.zero)
          if ok then
            return
          end
        end
        local camera = workspace.CurrentCamera
        release()
        local value = { User = virtualUser, Position = Vector2.zero, Frame = camera and camera.CFrame or CFrame.new() }
        virtualUser:Button2Down(value.Position, value.Frame)
        pending = value
        releaseThread = task.delay(0.15, function()
          releaseThread = nil
          if pending == value then
            release()
          end
        end)
      end
      scope.connect(player.Idled, function() idle = true end)
      deps.Controller.connectPhysics(scope, function()
        if not idle or os.clock() - lastInput < 30 then
          return
        end
        idle, lastInput = false, os.clock()
        local ok, reason = pcall(sendUser)
        if ok then
          return
        end
        release()
        local fallback, detail = pcall(function()
          local input = game:GetService("VirtualInputManager")
          local down, downError = pcall(input.SendMouseButtonEvent, input, 0, 0, 0, true, game, 0)
          local up, upError = pcall(input.SendMouseButtonEvent, input, 0, 0, 0, false, game, 0)
          assert(down and up, tostring(downError) .. " | " .. tostring(upError))
        end)
        if not fallback and os.clock() - lastError >= 5 then
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
    Controller = { "create", "connectPhysics" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}
return AntiAFK
