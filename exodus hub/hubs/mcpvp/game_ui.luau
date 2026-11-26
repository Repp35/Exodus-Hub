-- [[ gameui ]]
--!optimize 2
local GameUI = {}
local miniBalls = {
  { title = "Aim Lock", label = "LOCK", key = "MCAimLock", prefix = "MCAimLockBall" },
  { title = "Aim Assist", label = "ASSIST", key = "MCAimAssist", prefix = "MCAimAssistBall" },
  { title = "Auto Attack", label = "ATTACK", key = "MCAutoSword", prefix = "MCSwordBall" },
  { title = "Auto Crit", label = "CRIT", key = "MCAutoCrit", prefix = "MCCritBall" },
  { title = "Auto Potion", label = "POTION", key = "MCAutoPotion", prefix = "MCStrengthBall" },
  { title = "Auto Escape", label = "ESCAPE", key = "MCAutoEscape", prefix = "MCEscapeBall" },
  { title = "Auto Pearl", label = "PEARL", key = "MCAutoPearl", prefix = "MCPearlBall" },
  { title = "Auto Totem", label = "TOTEM", key = "MCAutoTotem", prefix = "MCTotemBall" },
  { title = "Auto Refill", label = "REFILL", key = "MCAutoRefill", prefix = "MCRefillBall" },
  {
    title = "Throw Pearl",
    label = "THROW\nPEARL",
    action = "onThrowPearl",
    prefix = "MCThrowPearlBall",
    description = "Lança na sua mira e volta ao item anterior.",
  },
  { title = "Stop PvP", label = "STOP\nPVP", action = "resetState", prefix = "MCStopPvPBall" },
}
GameUI.definition = {
  miniBalls = miniBalls,
  pageOrder = { "mcpvp", "mcpvp-mini" },
  pages = {
    {
      id = "mcpvp",
      title = "MCPvP",
      columns = 2,
      sections = {
        {
          title = "Combat",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Auto Attack",
              key = "MCAutoSword",
              description = "Continua o PvP que você iniciar, usando sua arma.",
            },
            {
              kind = "toggle",
              title = "Auto Crit",
              key = "MCAutoCrit",
              description = "Tenta críticos nos ataques automáticos e manuais.",
            },
            {
              kind = "toggle",
              title = "Auto Pearl",
              key = "MCAutoPearl",
              description = "Persegue o alvo sem mover a câmera; respeita sua intenção de parar.",
            },
          },
        },
        {
          title = "Aim",
          column = 2,
          components = {
            {
              kind = "toggle",
              title = "Aim Lock",
              key = "MCAimLock",
              description = "Mira instantaneamente no alvo do PvP, inclusive atrás de você.",
            },
            {
              kind = "toggle",
              title = "Aim Assist",
              key = "MCAimAssist",
              description = "Segue o alvo a longa distância, em todas as direções.",
            },
          },
        },
        {
          title = "Inventory",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Auto Totem",
              key = "MCAutoTotem",
              description = "Mantém um totem na segunda mão.",
            },
            {
              kind = "toggle",
              title = "Auto Refill",
              key = "MCAutoRefill",
              description = "Repõe itens esgotados no mesmo slot da hotbar.",
            },
          },
        },
        {
          title = "Survival",
          column = 2,
          components = {
            {
              kind = "toggle",
              title = "Auto Potion",
              key = "MCAutoPotion",
              description = "Reaplica as poções escolhidas quando o efeito acaba.",
            },
            {
              kind = "toggle",
              title = "Strength",
              key = "MCAutoStrength",
              parentKey = "MCAutoPotion",
              description = "Joga uma poção de força no seu pé.",
            },
            {
              kind = "toggle",
              title = "Speed",
              key = "MCAutoSpeed",
              parentKey = "MCAutoPotion",
              description = "Joga uma poção de velocidade no seu pé.",
            },
            {
              kind = "toggle",
              title = "Auto Escape",
              key = "MCAutoEscape",
              description = "Foge com pouca vida e sem totem; antecipa a maçã no PvP.",
            },
          },
        },
      },
    },
  },
}
local miniComponents = {}
GameUI.__config = { schema = {}, defaults = {} }
for _, ball in ipairs(miniBalls) do
  local visibleKey = ball.prefix .. "Visible"
  GameUI.__config.schema[visibleKey] = "boolean"
  GameUI.__config.schema[ball.prefix .. "X"] = "position"
  GameUI.__config.schema[ball.prefix .. "Y"] = "position"
  GameUI.__config.defaults[visibleKey] = false
  miniComponents[#miniComponents + 1] = {
    kind = "toggle",
    title = "Show " .. ball.title .. " Button",
    key = visibleKey,
    description = ball.description or (ball.action == "resetState" and "Mostra o botão para encerrar o PvP." or "Mostra o botão flutuante desta função."),
    mobileOnly = true,
  }
end
GameUI.definition.pages[#GameUI.definition.pages + 1] = {
  id = "mcpvp-mini",
  title = "Mini UI",
  columns = 2,
  sections = { { title = "Floating Buttons", components = miniComponents } },
}
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
