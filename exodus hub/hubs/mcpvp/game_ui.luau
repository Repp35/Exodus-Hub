-- [[ gameui ]]
--!optimize 2
local GameUI = {}
local miniControls = {
  { title = "Sword", key = "MCAutoSword", visibleKey = "MCMiniSwordVisible" },
  { title = "Auto Crit", key = "MCAutoCrit", visibleKey = "MCMiniCritVisible" },
  { title = "Auto Força", key = "MCAutoStrength", visibleKey = "MCMiniStrengthVisible" },
  { title = "Auto Pearl", key = "MCAutoPearl", visibleKey = "MCMiniPearlVisible" },
  { title = "Auto Totem", key = "MCAutoTotem", visibleKey = "MCMiniTotemVisible" },
  { title = "Reabastecer", key = "MCAutoRefill", visibleKey = "MCMiniRefillVisible" },
}
GameUI.definition = {
  miniControls = { title = "MCPvP", controls = miniControls, xKey = "MCMiniX", yKey = "MCMiniY" },
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
GameUI.__config = {
  schema = { MCMiniX = "position", MCMiniY = "position" },
  defaults = {},
}
for _, control in ipairs(miniControls) do
  GameUI.__config.schema[control.visibleKey] = "boolean"
  GameUI.__config.defaults[control.visibleKey] = false
  miniComponents[#miniComponents + 1] = {
    kind = "toggle",
    title = "Mini " .. control.title .. " UI",
    key = control.visibleKey,
    description = "Mostra ou oculta o botão flutuante sem alterar a função.",
  }
end
GameUI.definition.pages[#GameUI.definition.pages + 1] = {
  id = "mcpvp-mini",
  title = "Mini UI",
  columns = 1,
  sections = { { title = "Botões flutuantes", components = miniComponents } },
}
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
