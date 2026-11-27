-- [[ reversible character properties ]]
--!optimize 2
-- @modules characterproperties
local Properties = {}
local binding
function Properties.setup(deps) binding = deps.Binding; return true end
function Properties.create(utils, desired)
  return binding.create(function()
    local player = utils.getLocalPlayer()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Parent and humanoid.Health > 0 then return humanoid end
    return nil
  end, desired)
end
Properties.__contract = {
  access = { default = "lifetime.manage" },
  provides = { "setup", "create" },
  requires = { Binding = "propertybinding" },
  requiresMethods = { Binding = { "create" } },
}
return Properties
