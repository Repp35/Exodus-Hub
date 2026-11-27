-- [[ mm2 util ]]
--!optimize 2

-- module
local Utility = {}
function Utility.setup() return true end

-- implementation
function Utility.create(deps)
  local Util = {}
  local MAX_WORLD_COORDINATE = 1000000
  function Util.IsFiniteVector3(value)
    if typeof(value) ~= "Vector3" then
      return false
    end
    return value.X == value.X
      and value.Y == value.Y
      and value.Z == value.Z
      and math.abs(value.X) < MAX_WORLD_COORDINATE
      and math.abs(value.Y) < MAX_WORLD_COORDINATE
      and math.abs(value.Z) < MAX_WORLD_COORDINATE
  end

  function Util.GetHost()
    if type(gethui) == "function" then
      local ok, host = pcall(gethui)
      if ok and typeof(host) == "Instance" then
        return host
      end
    end
    return deps.services.CoreGui
  end
  function Util.DestroySafely(instance)
    if instance then
      pcall(function() instance:Destroy() end)
    end
  end
  return Util
end

-- contract
Utility.__contract = { provides = { "setup", "create" }, requires = {} }
return Utility
