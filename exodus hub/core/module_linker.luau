-- [[ module linking ]]
--!optimize 2
-- @modules modulelinker

local Linker = {}
function Linker.setup() return true end
function Linker.order(manifest, loaded)
  local MODULE_ORDER = {}
  for _, entry in ipairs(manifest) do
    if entry.name ~= "ui" and entry.name ~= "permissions" then
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
    table.sort(dependencies, function(a, b) return (positions[a] or math.huge) < (positions[b] or math.huge) end)
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
function Linker.validate(name, module)
  assert(type(module.__contract) == "table", name .. ": missing API contract")
  for _, method in ipairs(module.__contract.provides or {}) do
    assert(type(module[method]) == "function", name .. ": missing " .. method)
  end
  for _, field in ipairs(module.__contract.data or {}) do
    assert(module[field] ~= nil, name .. ": missing data " .. field)
  end
  return true
end
function Linker.resolve(name, loaded)
  local dependencies = {}
  for alias, source in pairs(loaded[name].__contract.requires or {}) do
    local provider = assert(loaded[source], "Missing dependency: " .. source)
    for _, method in ipairs((loaded[name].__contract.requiresMethods or {})[alias] or {}) do
      assert(type(provider[method]) == "function", source .. ": missing " .. method)
    end
    for _, field in ipairs((loaded[name].__contract.requiresData or {})[alias] or {}) do
      assert(provider[field] ~= nil, source .. ": missing data " .. field)
    end
    dependencies[alias] = provider
  end
  return dependencies
end

Linker.__contract = { provides = { "setup", "order", "validate", "resolve" }, requires = {} }
return Linker
