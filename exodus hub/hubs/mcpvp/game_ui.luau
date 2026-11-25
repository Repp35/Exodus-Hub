-- [[ gameui ]]
--!optimize 2
local GameUI = {}
GameUI.definition = {
  pageOrder = { "mcpvp" },
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
            {
              kind = "toggle",
              title = "Auto Pearl",
              key = "MCAutoPearl",
              description = "Segue fugas próximas e médias; reserva distâncias maiores para servidores com até quatro jogadores.",
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
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
