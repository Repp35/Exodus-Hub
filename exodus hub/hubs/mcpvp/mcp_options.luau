-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.__config = {
  defaults = {
    MCAimLock = true,
    MCAimAssist = true,
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
    MCAutoStrength = "boolean",
    MCAutoCrit = "boolean",
    MCAutoSword = "boolean",
    MCAutoPearl = "boolean",
    MCAutoRefill = "boolean",
    MCAutoTotem = "boolean",
  },
}
Options.tuning = { focusRangeBlocks = 5, assistRangeBlocks = 32, pearlRangeBlocks = 24, pursuitSeconds = 15, pearlMaxFlight = 2.5 }
function Options.setup() return true end
function Options.migrateConfig(data)
  if data.MCAimStrength == nil then
    return false
  end
  data.MCAimStrength = nil
  return true
end
Options.__contract = { provides = { "setup", "migrateConfig" }, data = { "tuning" }, requires = {} }
return Options
