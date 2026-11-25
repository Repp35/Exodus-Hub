-- [[ gameui ]]
--!optimize 2
local GameUI = { definition = {} }
function GameUI.setup(deps)
  local sections = {}
  local columns = { target = 1, sword = 1, crystal = 2, anchor = 2, survival = 1, safety = 2 }
  for _, group in ipairs(deps.Options.groups) do
    local components = {}
    for _, item in ipairs(group.items) do
      components[#components + 1] = { kind = "toggle", title = item.title, key = item.key, parentKey = item.parentKey, compact = true }
    end
    sections[#sections + 1] = { title = group.title, column = columns[group.id] or 1, components = components }
  end
  GameUI.definition = { pageOrder = { "mcpvp" }, pages = { { id = "mcpvp", title = "MCPVP", columns = 2, sections = sections } } }
  return true
end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = { Options = "mcpoptions" }, requiresData = { Options = { "groups" } } }
return GameUI
