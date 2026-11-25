-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.__config = {
  defaults = { MCAutoSword = true, MCAutoPearl = true },
  schema = { MCAutoSword = "boolean", MCAutoPearl = "boolean" },
}
Options.tuning =
  { acquireAngle = 24, clickWindow = 0.65, clicksToStart = 2, targetMemory = 3, pearlDelay = 0.8, maxRange = 96, aimRange = 16, aimPull = 10, aimMaxSpeed = 1.6, threatWindow = 1.1, pearlSpeed = 96, pearlGravity = 38.4 }
function Options.setup() return true end
Options.__contract = { provides = { "setup" }, data = { "tuning" }, requires = {} }
return Options
