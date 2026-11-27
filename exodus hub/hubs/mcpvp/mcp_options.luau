-- [[ mcp options ]]
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
  assistRangeBlocks = 5,
  assistMemorySeconds = 0.35,
  aimInputGraceSeconds = 0.15,
  aimLockMultiplier = 1.75,
  pearlAttackMarginBlocks = 0.65,
  pursuitAwayRangeBlocks = 10,
  lookAwaySeconds = 6,
  manualTurnSeconds = 0.75,
  pursuitScreenMargin = 0.15,
  pearlTargetHeightBlocks = 2,
  pearlExitHeightBlocks = 8,
  pearlLandingRadiusBlocks = 1.25,
  pearlMaxFlight = 6,
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
