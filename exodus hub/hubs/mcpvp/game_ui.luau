-- [[ gameui ]]
--!optimize 2
local GameUI = { definition = {} }
function GameUI.setup(deps)
  local pages, order = {}, {}
  for _, group in ipairs(deps.Options.groups) do
    local components = {}
    for _, item in ipairs(group.items) do
      local numeric = type(item.default) == "number"
      components[#components + 1] = {
        kind = numeric and "slider" or "toggle",
        title = item.title,
        key = item.key,
        min = item.min,
        max = item.max,
        increment = numeric and (item.max <= 3 and 0.01 or (item.max <= 20 and 0.1 or 1)) or nil,
      }
    end
    order[#order + 1] = group.id
    pages[#pages + 1] = { id = group.id, title = group.title, columns = 1, sections = { { title = group.title, column = 1, components = components } } }
  end
  GameUI.definition = { pageOrder = order, pages = pages }
  return true
end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = { Options = "mcpoptions" }, requiresData = { Options = { "groups" } } }
return GameUI
