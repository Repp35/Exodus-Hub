-- [[ game context ]]

-- code
local GameContext = {}
local CONFIG = {
  PHANTOM_PLACE_ID = 12979690461,
  PHANTOM_UNIVERSE_ID = 4538598064,
}

local PHANTOM_PLACE_ID = CONFIG.PHANTOM_PLACE_ID
local PHANTOM_UNIVERSE_ID = CONFIG.PHANTOM_UNIVERSE_ID
function GameContext.setup() return true end
function GameContext.isPhantomBall() return game.PlaceId == PHANTOM_PLACE_ID or game.GameId == PHANTOM_UNIVERSE_ID end
function GameContext.supportsModule(name, path)
  if GameContext.isPhantomBall() then return true end
  if name == "combatloop" or name == "autojump" or name == "camera" then return false end
  return path:sub(1, 15) ~= "modules/combat/" and path:sub(1, 13) ~= "modules/game/"
end
GameContext.__contract = { provides = { "setup", "isPhantomBall", "supportsModule" }, requires = {} }

return GameContext
