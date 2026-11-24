-- [[ gameui ]]
--!optimize 2

local GameUI = {}

GameUI.definition = {
  pageOrder = { "main" },
  pages = {
    {
      id = "main",
      title = "MCPVP",
      columns = 2,
      sections = {
        {
          title = "MCPVP",
          column = 1,
          components = {
            { kind = "label", title = "Template pronto para novos módulos." },
          },
        },
      },
    },
  },
}

function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }

return GameUI
