-- [[ gameui ]]
--!optimize 2
local GameUI = {}
local options = {
  attack = { title = "Auto Attack", key = "MCAutoSword", description = "Continua o PvP que você iniciar, usando sua arma." },
  critical = { title = "Auto Critical", key = "MCAutoCrit", description = "Automatiza o salto para críticos, inclusive nos seus cliques." },
  pearl = { title = "Auto Pearl", key = "MCAutoPearl", description = "Alcança o oponente com pearl e acompanha fugas." },
  lock = { title = "Aim Lock", key = "MCAimLock", description = "Mantém a mira no oponente próximo do PvP." },
  assist = { title = "Aim Assist", key = "MCAimAssist", description = "Ajuda a recuperar a mira no oponente próximo." },
  potion = { title = "Auto Potion", key = "MCAutoPotion", description = "Reaplica as poções escolhidas quando o efeito acaba." },
  strength = { title = "Strength", key = "MCAutoStrength", parentKey = "MCAutoPotion", description = "Joga força no seu pé." },
  speed = { title = "Speed", key = "MCAutoSpeed", parentKey = "MCAutoPotion", description = "Joga velocidade no seu pé." },
  escape = { title = "Auto Escape", key = "MCAutoEscape", description = "Foge com pouca vida e sem totem; antecipa a maçã no PvP." },
  totem = { title = "Auto Totem", key = "MCAutoTotem", description = "Mantém um totem na segunda mão." },
  refill = { title = "Auto Refill", key = "MCAutoRefill", description = "Repõe itens esgotados no mesmo slot da hotbar." },
}
for _, option in pairs(options) do
  option.kind = "toggle"
end
local combat = { options.attack, options.critical, options.pearl }
local aim = { options.lock, options.assist }
local inventory = { options.totem, options.refill }
local consumables = { options.potion, options.strength, options.speed, options.escape }
local miniBalls = {
  { option = options.lock, label = "LOCK", prefix = "MCAimLockBall" },
  { option = options.assist, label = "ASSIST", prefix = "MCAimAssistBall" },
  { option = options.attack, label = "ATTACK", prefix = "MCSwordBall" },
  { option = options.critical, label = "CRIT", prefix = "MCCritBall" },
  { option = options.pearl, label = "PEARL", prefix = "MCPearlBall" },
  { option = options.potion, label = "POTION", prefix = "MCStrengthBall" },
  { option = options.escape, label = "ESCAPE", prefix = "MCEscapeBall" },
  { option = options.totem, label = "TOTEM", prefix = "MCTotemBall" },
  { option = options.refill, label = "REFILL", prefix = "MCRefillBall" },
  { title = "Stop PvP", label = "STOP\nPVP", action = "resetState", prefix = "MCStopPvPBall" },
}
local quick = {}
GameUI.__config = { schema = {}, defaults = {} }
for _, ball in ipairs(miniBalls) do
  if ball.option then
    ball.title, ball.key = ball.option.title, ball.option.key
    ball.option = nil
  end
  local visibleKey = ball.prefix .. "Visible"
  GameUI.__config.schema[visibleKey] = "boolean"
  GameUI.__config.schema[ball.prefix .. "X"] = "position"
  GameUI.__config.schema[ball.prefix .. "Y"] = "position"
  GameUI.__config.defaults[visibleKey] = false
  quick[ball.key or ball.action] = {
    kind = "toggle",
    title = ball.title,
    key = visibleKey,
    description = ball.action and "Mostra o botão para encerrar o PvP atual." or "Mostra o botão flutuante de " .. ball.title .. ".",
    mobileOnly = true,
  }
end
GameUI.definition = {
  miniBalls = miniBalls,
  pageOrder = { "mcpvp", "mcpvp-survival", "mcpvp-mini", "indeed", "antilag", "config", "information" },
  pages = {
    {
      id = "mcpvp",
      title = "Combat",
      columns = 2,
      sections = {
        { title = "Attacks & Pursuit", column = 1, components = combat },
        { title = "Aim", column = 2, components = aim },
      },
    },
    {
      id = "mcpvp-survival",
      title = "Survival",
      columns = 2,
      sections = {
        { title = "Inventory", column = 1, components = inventory },
        { title = "Potions & Escape", column = 2, components = consumables },
      },
    },
    {
      id = "mcpvp-mini",
      title = "Quick Controls",
      mobileOnly = true,
      columns = 2,
      sections = {
        { title = "Combat Buttons", column = 1, components = { quick.MCAutoSword, quick.MCAutoCrit, quick.MCAutoPearl, quick.MCAimLock, quick.MCAimAssist } },
        { title = "Survival Buttons", column = 2, components = { quick.MCAutoPotion, quick.MCAutoEscape, quick.MCAutoTotem, quick.MCAutoRefill } },
        { title = "Session", column = 2, components = { quick.resetState } },
      },
    },
  },
}
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
