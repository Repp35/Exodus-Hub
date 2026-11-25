-- [[ gameui ]]
--!optimize 2
local GameUI = {}
local miniBalls = {
  { title = "Sword", label = "SWORD", key = "MCAutoSword", prefix = "MCSwordBall" },
  { title = "Auto Crit", label = "CRIT", key = "MCAutoCrit", prefix = "MCCritBall" },
  { title = "Auto Força", label = "FORÇA", key = "MCAutoStrength", prefix = "MCStrengthBall" },
  { title = "Auto Pearl", label = "PEARL", key = "MCAutoPearl", prefix = "MCPearlBall" },
  { title = "Auto Totem", label = "TOTEM", key = "MCAutoTotem", prefix = "MCTotemBall" },
  { title = "Reabastecer", label = "REFILL", key = "MCAutoRefill", prefix = "MCRefillBall" },
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
          title = "Combate",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Sword + Aim Assist / Aim Lock",
              key = "MCAutoSword",
              description = "Inicie com dois ataques no alvo. Mantém mira e ritmo dos golpes.",
            },
            {
              kind = "toggle",
              title = "Auto Crit",
              key = "MCAutoCrit",
              parentKey = "MCAutoSword",
              description = "Sincroniza o pulo com o cooldown e prioriza golpes durante a descida.",
            },
          },
        },
        {
          title = "Assistência",
          column = 2,
          components = {
            { kind = "toggle", title = "Auto Força", key = "MCAutoStrength", description = "Prioriza poções de força na hotbar e joga no pé quando o efeito termina." },
            {
              kind = "toggle",
              title = "Auto Pearl",
              key = "MCAutoPearl",
              description = "Usa pérola para voltar ao alcance quando houver linha livre até o alvo.",
            },
            {
              kind = "toggle",
              title = "Auto Totem",
              key = "MCAutoTotem",
              description = "Prioriza a hotbar, abre o inventário para acessar reservas e preenche espaços vazios.",
            },
          },
        },
        {
          title = "Inventário",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Reabastecer hotbar",
              key = "MCAutoRefill",
              description = "Abre o inventário e repõe cada item esgotado no mesmo slot.",
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
    title = "Mini " .. ball.title .. " UI",
    key = visibleKey,
    description = "Mostra o botão de " .. ball.title .. ".",
    mobileOnly = true,
  }
end
GameUI.definition.pages[#GameUI.definition.pages + 1] = {
  id = "mcpvp-mini",
  title = "Mini UI",
  columns = 2,
  sections = { { title = "Mini UI", components = miniComponents } },
}
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
