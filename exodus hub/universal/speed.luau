-- [[ speed ]]
--!optimize 2
-- @modules speed

local Speed = {}
local controller, binding, defaultsScope
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
  if defaultsScope then
    defaultsScope.destroy()
    defaultsScope = nil
  end
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
  local selected, writing, characterScope = false, false, nil
  defaultsScope = deps.Lifetime.scope()
  local cleanup = { Disconnect = defaultsScope.destroy }
  utils.trackGlobal(cleanup)
  defaultsScope.add(function() utils.untrackGlobal(cleanup) end)
  defaultsScope.add(utils.observeConfig(function(changes)
    if changes.UniversalSpeed ~= nil and not writing then
      selected = true
    end
  end))
  local function watch(character)
    if characterScope then
      characterScope.destroy()
    end
    characterScope = defaultsScope.child()
    if not character then
      return
    end
    local humanoid
    local function attach()
      local found = character:FindFirstChildOfClass("Humanoid")
      if not found or found == humanoid then
        return
      end
      humanoid = found
      local function baseline()
        if not selected and not utils.getConfigValue("UniversalSpeedEnabled") and humanoid.Parent then
          writing = true
          utils.setConfig({ UniversalSpeed = humanoid.WalkSpeed })
          writing = false
        end
      end
      characterScope.connect(humanoid:GetPropertyChangedSignal("WalkSpeed"), baseline)
      baseline()
    end
    characterScope.connect(character.ChildAdded, attach)
    attach()
  end
  local player = utils.getLocalPlayer()
  if player then
    defaultsScope.connect(player.CharacterAdded, watch)
    defaultsScope.connect(player.CharacterRemoving, function() watch(nil) end)
    watch(player.Character)
  end
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
