--!optimize 2
-- @modules gamecontext

local GameContext = {}
local profile = { id = "universal", title = "Universal", author = "deltapolinha_2915" }
function GameContext.setup() return true end
function GameContext.configure(value)
  profile = table.clone(value)
  return true
end
function GameContext.getProfile() return table.clone(profile) end
function GameContext.supportsModule() return true end
GameContext.__contract = { provides = { "setup", "configure", "getProfile", "supportsModule" }, requires = {} }
return GameContext
