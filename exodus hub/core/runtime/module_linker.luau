-- [[ module linker ]]
--!optimize 2
-- @modules modulelinker

local Linker = {}
function Linker.setup() return true end
function Linker.order(manifest, loaded)
  local MODULE_ORDER = {}
  for _, entry in ipairs(manifest) do
    if entry.name ~= "permissions" then
      MODULE_ORDER[#MODULE_ORDER + 1] = entry.name
    end
  end
  local positions, state, ordered = {}, {}, {}
  for index, name in ipairs(MODULE_ORDER) do
    positions[name] = index
  end
  local function visit(name)
    if state[name] == 2 then
      return
    end
    if state[name] == 1 then
      error("dependência circular entre módulos: " .. name, 2)
    end
    if not positions[name] or type(loaded[name]) ~= "table" then
      error("dependência não inicializável: " .. tostring(name), 2)
    end
    state[name] = 1
    local dependencies = {}
    for _, source in pairs(loaded[name].__contract.requires or {}) do
      if source ~= "permissions" then
        dependencies[#dependencies + 1] = source
      end
    end
    table.sort(dependencies, function(a, b)
      local left, right = positions[a] or math.huge, positions[b] or math.huge
      return left < right or left == right and a < b
    end)
    for _, source in ipairs(dependencies) do
      visit(source)
    end
    state[name] = 2
    ordered[#ordered + 1] = name
  end
  for _, name in ipairs(MODULE_ORDER) do
    visit(name)
  end
  table.clear(MODULE_ORDER)
  for _, name in ipairs(ordered) do
    if name ~= "character" then
      MODULE_ORDER[#MODULE_ORDER + 1] = name
    end
  end
  if loaded.character then
    MODULE_ORDER[#MODULE_ORDER + 1] = "character"
  end
  return MODULE_ORDER
end
Linker.__contract = { provides = { "setup", "order" }, requires = {} }
return Linker
