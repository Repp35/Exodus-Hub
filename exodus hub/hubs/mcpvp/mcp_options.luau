-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.__config = {
  defaults = {
    MCAimLock = false,
    MCAimAssist = true,
    MCAimLegit = true,
    MCAimStrength = 45,
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
    MCAimLegit = "boolean",
    MCAimStrength = "rate",
    MCAutoStrength = "boolean",
    MCAutoCrit = "boolean",
    MCAutoSword = "boolean",
    MCAutoPearl = "boolean",
    MCAutoRefill = "boolean",
    MCAutoTotem = "boolean",
  },
}
Options.tuning = { acquireAngle = 24, clickWindow = 0.65, clicksToStart = 2, targetMemory = 3, maxRange = 96, aimRange = 16, threatWindow = 10 }
function Options.setup() return true end
Options.__contract = { provides = { "setup" }, data = { "tuning" }, requires = {} }
return Options
