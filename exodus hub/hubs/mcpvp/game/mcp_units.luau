-- [[ mcp units ]]
--!optimize 2
local Units = {}
local scale = 3.2
function Units.setup()
  local source = game:GetService("ReplicatedStorage"):FindFirstChild("VoxelWeapons")
  local ok, weapons = pcall(function() return source and require(source) end)
  local block = ok and type(weapons) == "table" and weapons.Block
  scale = type(block) == "number" and block == block and block > 0 and block < math.huge and block or 3.2
  return true
end
function Units.toBlocks(worldValue) return worldValue / scale end
function Units.toWorld(blockValue) return blockValue * scale end
function Units.offset(x, y, z) return Vector3.new(x, y, z) * scale end
function Units.distance(worldA, worldB) return (worldA - worldB).Magnitude / scale end
Units.__contract = { provides = { "setup", "toBlocks", "toWorld", "offset", "distance" }, requires = {} }
return Units
