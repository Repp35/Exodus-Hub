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
          title = "Espada",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Auto Attack Sword",
              key = "MCAutoSword",
              description = "Inicie com dois ataques no alvo. Mantém mira e ritmo dos golpes.",
            },
          },
        },
        {
          title = "Pérola",
          column = 2,
          components = { { kind = "toggle", title = "Auto Pearl", key = "MCAutoPearl", description = "Acompanha o alvo da luta quando ele sai do alcance." } },
        },
      },
    },
  },
}
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
