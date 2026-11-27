-- [[ no fog ]]
--!optimize 2
-- @modules nofog

local NoFog = {}
local controller, binding
local Lighting = game:GetService("Lighting")
local CONFIG = { schema = { UniversalNoFog = "boolean" }, defaults = { UniversalNoFog = false } }
function NoFog.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function NoFog.teardown()
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
function NoFog.setup(deps)
  NoFog.teardown()
  local fogValues = { FogStart = 0, FogEnd = 1000000 }
  local atmosphereValues = { Density = 0, Haze = 0 }
  binding = deps.Binding.create(function() return Lighting end, function() return fogValues end)
  controller = deps.Controller.create(deps.Utils, deps.Lifetime, {
    key = "UniversalNoFog",
    start = function(scope)
      local atmospheres = {}
      local function remove(object)
        local entry = atmospheres[object]
        if entry then
          entry.restore()
          atmospheres[object] = nil
        end
      end
      local function add(object)
        if not object:IsA("Atmosphere") or atmospheres[object] then
          return
        end
        local entry = deps.Binding.create(function() return object.Parent == Lighting and object or nil end, function() return atmosphereValues end)
        atmospheres[object] = entry
        entry.update()
      end
      scope.add(function()
        for _, entry in pairs(atmospheres) do
          entry.restore()
        end
        table.clear(atmospheres)
      end)
      scope.connect(Lighting.ChildAdded, add)
      scope.connect(Lighting.ChildRemoved, remove)
      for _, object in ipairs(Lighting:GetChildren()) do
        add(object)
      end
      deps.Controller.connectPhysics(scope, function()
        binding.update()
        for _, entry in pairs(atmospheres) do
          entry.update()
        end
      end)
    end,
    stop = binding.restore,
    update = binding.update,
  })
  return controller.sync()
end
NoFog.__config = CONFIG
NoFog.__contract = {
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Binding = "propertybinding" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
    Binding = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled" },
}
return NoFog
