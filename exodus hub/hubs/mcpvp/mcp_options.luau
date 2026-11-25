-- [[ mcpoptions ]]
--!optimize 2
local Options = {}
Options.groups = {
  {
    id = "target",
    title = "Alvo e mira",
    items = {
      { key = "MCEnabled", title = "Assistentes ativos", default = false },
      { key = "MCAim", title = "Aim Lock de espada", default = false },
    },
  },
  {
    id = "sword",
    title = "Espada",
    items = {
      { key = "MCAttack", title = "Auto Attack", default = false },
      { key = "MCCrit", title = "Pular para crítico", default = false, parentKey = "MCAttack" },
      { key = "MCSwordPearl", title = "Auto Pearl na espada", default = false },
    },
  },
  {
    id = "crystal",
    title = "Cristais e D Tap",
    items = {
      { key = "MCCrystal", title = "Crystal Assist", default = false },
      { key = "MCCrystalPearl", title = "Permitir Pearl Follow", default = false, parentKey = "MCCrystal" },
      { key = "MCDTap", title = "D Tap após golpe", default = false },
      { key = "MCDTapPearl", title = "Permitir pérola no D Tap", default = false, parentKey = "MCDTap" },
    },
  },
  {
    id = "anchor",
    title = "Âncoras",
    items = {
      { key = "MCAnchor", title = "Anchor Assist", default = false },
      { key = "MCAnchorPearl", title = "Permitir Pearl Follow", default = false, parentKey = "MCAnchor" },
    },
  },
  {
    id = "survival",
    title = "Sobrevivência e inventário",
    items = {
      { key = "MCTotem", title = "Auto Totem", default = false },
      { key = "MCPotion", title = "Auto Potion", default = false },
      { key = "MCPotionSpeed", title = "Renovar velocidade", default = false, parentKey = "MCPotion" },
      { key = "MCApple", title = "Auto Golden Apple", default = false },
    },
  },
  {
    id = "safety",
    title = "Avaliação e proteção",
    items = {
      { key = "MCDefense", title = "Proteção contra explosões próximas", default = false },
    },
  },
}
Options.tuning = {
  MCTeamCheck = true,
  MCAcquireFov = 24,
  MCSwordLockRange = 5,
  MCTargetRange = 14,
  MCTargetMemory = 6,
  MCAimSpeed = 240,
  MCAimTolerance = 0.2,
  MCManualPause = 0.3,
  MCAttackCharge = 100,
  MCAttackRange = 3,
  MCSwordPearlGap = 5,
  MCSwordPearlMax = 12,
  MCPearlReserve = 0,
  MCPearlInterval = 2,
  MCPearlMinHealth = 45,
  MCPearlLead = 0.3,
  MCCrystalManual = true,
  MCCrystalDamage = 8,
  MCCrystalRadius = 4,
  MCDTapWindow = 3.5,
  MCComboLifetime = 8,
  MCAnchorRepeat = true,
  MCAnchorDamage = 7,
  MCAnchorRadius = 3.5,
  MCAnchorProtection = true,
  MCAnchorAlwaysProtect = false,
  MCTotemRefill = true,
  MCTotemSlots = 2,
  MCReactionMin = 0.12,
  MCReactionMax = 0.32,
  MCPotionStrength = true,
  MCPotionRefill = true,
  MCPotionCombat = true,
  MCPotionRetry = 1.2,
  MCAppleHealth = 55,
  MCAppleCombat = false,
  MCMaxSelfDamage = 8,
  MCDamageMargin = 2,
  MCHealthReserve = 25,
  MCDamageUncertainty = 30,
  MCDefenseDamage = 8,
  MCProtectionObsidian = true,
  MCProtectionGlowstone = true,
}
Options.__config = { defaults = {}, schema = {} }
for _, group in ipairs(Options.groups) do
  for _, item in ipairs(group.items) do
    Options.__config.defaults[item.key] = item.default
    Options.__config.schema[item.key] = type(item.default) == "boolean" and "boolean" or "rate"
  end
end
function Options.setup() return true end
Options.__contract = { provides = { "setup" }, data = { "groups", "tuning" }, requires = {} }
return Options
