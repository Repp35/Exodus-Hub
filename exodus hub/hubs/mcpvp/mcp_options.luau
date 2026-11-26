-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.__config = {
  defaults = {
    MCAimLock = true,
    MCAimAssist = true,
    MCAutoPotion = true,
    MCAutoStrength = true,
    MCAutoSpeed = true,
    MCAutoEscape = true,
    MCAutoCrit = true,
    MCAutoSword = true,
    MCAutoPearl = true,
    MCAutoRefill = true,
    MCAutoTotem = true,
  },
  schema = {
    MCAimLock = "boolean",
    MCAimAssist = "boolean",
    MCAutoPotion = "boolean",
    MCAutoStrength = "boolean",
    MCAutoSpeed = "boolean",
    MCAutoEscape = "boolean",
    MCAutoCrit = "boolean",
    MCAutoSword = "boolean",
    MCAutoPearl = "boolean",
    MCAutoRefill = "boolean",
    MCAutoTotem = "boolean",
  },
}
Options.tuning = {
  focusRangeBlocks = 5,
  assistRangeBlocks = 6,
  lookAwaySeconds = 1.25,
  retaliationSeconds = 2.5,
  pearlMaxFlight = 6,
  pearlLobRangeBlocks = 32,
  pearlLowPitchDegrees = 8,
}
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
