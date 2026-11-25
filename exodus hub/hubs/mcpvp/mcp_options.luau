-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.__config = {
  defaults = {
    MCAimLock = true,
    MCAimAssist = true,
    MCAimStrength = 100,
    MCAutoStrength = true,
    MCAutoCrit = true,
    MCAutoSword = true,
    MCAutoPearl = true,
    MCAutoRefill = true,
    MCAutoTotem = true,
  },
  schema = {
    MCAimLock = "boolean",
    MCAimAssist = "boolean",
    MCAimStrength = "rate",
    MCAutoStrength = "boolean",
    MCAutoCrit = "boolean",
    MCAutoSword = "boolean",
    MCAutoPearl = "boolean",
    MCAutoRefill = "boolean",
    MCAutoTotem = "boolean",
  },
}
Options.tuning = { acquireAngle = 24, clickWindow = 0.65, clicksToStart = 2, targetMemory = 4, maxRange = 96, chaseRange = 205, threatWindow = 3 }
function Options.setup() return true end
Options.__contract = { provides = { "setup" }, data = { "tuning" }, requires = {} }
return Options
