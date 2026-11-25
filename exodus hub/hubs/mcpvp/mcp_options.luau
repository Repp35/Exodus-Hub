-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.__config = {
  defaults = {
    MCAimDefaultsRevision = 0,
    MCAimLock = true,
    MCAimAssist = true,

    MCAimStrength = 45,
    MCAutoStrength = true,
    MCAutoCrit = true,
    MCAutoSword = true,
    MCAutoPearl = true,
    MCAutoRefill = true,
    MCAutoTotem = true,
  },
  schema = {
    MCAimDefaultsRevision = "rate",
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
Options.tuning = { acquireAngle = 45, clickWindow = 0.65, clicksToStart = 1, targetMemory = 3, maxRange = 96, aimRange = 16, assistRange = 16, lockRange = 24, assistCone = 12, lockCone = 55, maxChase = 6, threatWindow = 10 }
function Options.setup(deps)
  if (tonumber(deps.Utils.getConfigValue("MCAimDefaultsRevision")) or 0) < 3 then
    deps.Utils.setConfig({ MCAimDefaultsRevision = 3 })
  end
  return true
end
Options.__contract =
  { provides = { "setup" }, data = { "tuning" }, requires = { Utils = "utils" }, requiresMethods = { Utils = { "getConfigValue", "setConfig" } } }
return Options
