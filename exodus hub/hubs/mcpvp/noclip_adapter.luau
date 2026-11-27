-- [[ native voxel collision adapter ]]
--!optimize 2
local Adapter = {}
local native, original, replacement
function Adapter.teardown()
  if native and native.Resolve == replacement then
    pcall(function() native.Resolve = original end)
  end
  native, original, replacement = nil, nil, nil
  return true
end
function Adapter.setup(deps)
  Adapter.teardown()
  local source = game:GetService("ReplicatedStorage"):FindFirstChild("VoxelBlockCollision")
  if not source then return true end
  local ok, module = pcall(require, source)
  if not ok or type(module) ~= "table" or type(module.Resolve) ~= "function" then return true end
  local player = game:GetService("Players").LocalPlayer
  native, original = module, module.Resolve
  replacement = function(position, movement, ...)
    local model = player and player.Character
    local root = model and model:FindFirstChild("HumanoidRootPart")
    if deps.Noclip.isEnabled() and root and typeof(position) == "Vector3" and typeof(movement) == "Vector3"
      and (position - root.Position).Magnitude < 1 then
      return movement, { x = false, y = false, z = false, grounded = false }
    end
    return original(position, movement, ...)
  end
  local installed = pcall(function() native.Resolve = replacement end)
  if not installed then
    deps.Utils.recordError("MCPvP.Noclip", "O controlador nativo de colisão não permite adaptação neste executor.")
    Adapter.teardown()
  end
  return true
end
Adapter.__contract = {
  provides = { "setup", "teardown" },
  requires = { Noclip = "noclip", Utils = "utils" },
  requiresMethods = { Noclip = { "isEnabled" }, Utils = { "recordError" } },
}
return Adapter
