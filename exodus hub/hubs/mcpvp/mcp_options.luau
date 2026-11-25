-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.__config = {
  defaults = { MCAutoSword = true, MCAutoPearl = true, MCAutoTotem = true },
  schema = { MCAutoSword = "boolean", MCAutoPearl = "boolean", MCAutoTotem = "boolean" },
}
Options.tuning =
  { acquireAngle = 24, clickWindow = 0.65, clicksToStart = 2, targetMemory = 3, pearlDelay = 1.15, pearlMinGap = 16, pearlMaxGap = 48, pearlHitAge = 4, pearlGiveUp = 1.3, maxRange = 96, aimRange = 16, aimSpeed = 240, threatWindow = 3, pearlSpeed = 96, pearlGravity = 38.4 }
function Options.setup() return true end
Options.__contract = { provides = { "setup" }, data = { "tuning" }, requires = {} }
return Options
