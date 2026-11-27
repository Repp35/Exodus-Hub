-- [[ autojump ]]
--!optimize 2
-- @modules autojump

local AutoJump = {}
local controller
function AutoJump.sync() return controller and controller.sync() or false end
function AutoJump.setEnabled(value) return controller and controller.setEnabled(value) or false end
function AutoJump.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  return true
end
function AutoJump.setup(deps)
  AutoJump.teardown()
  local utils = deps.Utils
  local function jump()
    local player = utils.getLocalPlayer()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand or humanoid.FloorMaterial == Enum.Material.Air then
      return
    end
    if humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
      humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
  end
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "AutoJump",
    start = function(scope) deps.Controller.connectPhysics(scope, jump) end,
    update = jump,
  })
  return controller.sync()
end
AutoJump.__config = { persistent = { AutoJump = false }, schema = { AutoJump = "boolean" }, defaults = { AutoJump = false } }
AutoJump.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
  },
  provides = { "setup", "teardown", "sync", "setEnabled" },
}
return AutoJump
