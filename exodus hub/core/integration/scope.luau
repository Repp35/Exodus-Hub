-- [[ Game modules consume owned settings and explicit shared services ]]
--!optimize 2
-- @modules gamescope
local GameScope = {}
local sharedServices = {
  utils = {
    getLocalPlayer = true,
    getPlayers = true,
    getRunService = true,
    getWorkspace = true,
    getReplicatedStorage = true,
    getConfigValue = true,
    getConfig = true,
    isActive = true,

    isFiniteNumber = true,
    isNonNegativeFiniteNumber = true,

    getLifecycle = true,
    getDiagnostics = true,
    setConfig = true,
    observeConfig = true,

    trackGlobal = true,
    untrackGlobal = true,
    trackCharacter = true,
    untrackCharacter = true,
    recordError = true,
    recordTransition = true,
    now = true,
    apiVersion = true,
    name = true,
    version = true,
    author = true,

  },
  hubapi = { getAbilityAvailability = true },
  universalcontroller = { connectPhysics = true },
  options = { get = true, isEnabled = true, describe = true, observe = true },
  lifetime = { scope = true, connections = true },
  profiler = { begin = true, finish = true, count = true },
  status = { get = true, collect = true },
  ui = {
    notify = true,
    notifyCorner = true,
    createMini = true,
    addPage = true,
    createWorldLabel = true,
    createWorldBillboard = true,
    createWorldHighlight = true,
    destroyWorldMarker = true,
  },
  uinativeability = { create = true, reveal = true },
  propertybinding = { create = true, apply = true, release = true, getOriginal = true },
  noclip = { acquire = true, release = true, isEnabled = true },
  invisicam = { setSource = true },
}
local function copy(value, freeze, seen, blockCommands)
  if type(value) == "function" and blockCommands then
    return blockCommands
  end
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do
    result[key] = copy(item, freeze, seen, blockCommands)
  end
  return freeze and table.freeze(result) or result
end
function GameScope.setup() return true end
function GameScope.create(loaded, profile)
  local owned, keys, protected, legacy, views = {}, {}, {}, {}, {}
  local root = "hubs/" .. profile.id .. "/"
  for name, module in pairs(loaded) do
    local path = loaded.permissions.getPath(name)
    owned[name] = path ~= nil and path:sub(1, #root) == root
    for key in pairs(module.__config and module.__config.schema or {}) do
      if owned[name] then
        keys[key] = true
      else
        protected[key] = true
      end
    end
    if owned[name] then
      for _, key in ipairs(module.__config and module.__config.legacy or {}) do
        assert(type(key) == "string", name .. ": legacy config key inválida")
        legacy[key] = true
      end
    end
  end
  for key in pairs(legacy) do
    assert(not protected[key], "Game " .. profile.id .. ": legacy config pertence a outro módulo: " .. key)
  end
  local boundary = { modules = {}, profile = copy(profile, true) }
  local function deny(action) error("Game " .. profile.id .. ": acesso fora dos próprios módulos: " .. action, 3) end
  local function validatePatch(patch)
    assert(type(patch) == "table", "Config patch inválido")
    for key in pairs(patch) do
      if not keys[key] then
        deny("config." .. tostring(key))
      end
    end
  end
  local function view(source, provider)
    local result = { __contract = copy(loaded[source].__contract, true) }
    local contract = loaded[source].__contract
    for _, method in ipairs(contract.provides or {}) do
      local service = sharedServices[source] and sharedServices[source][method]
      if owned[source] or service then
        local available, callback = pcall(function() return provider[method] end)
        if not available or type(callback) ~= "function" then
          continue
        end
        if source == "utils" and method == "setConfig" then
          result[method] = function(patch)
            validatePatch(patch)
            return callback(patch)
          end
        elseif source == "utils" and method == "observeConfig" then
          result[method] = function(observer)
            return callback(function(changes)
              local own = {}
              for key, value in pairs(changes) do
                if keys[key] then
                  own[key] = value
                end
              end
              if next(own) then
                observer(table.freeze(own))
              end
            end)
          end
        elseif source == "invisicam" and method == "setSource" then
          result[method] = function(name, value) return callback(profile.id .. "." .. tostring(name), value) end
        elseif source == "ui" and method == "addPage" then
          result[method] = function(definition)
            local valid = boundary.definition({ pages = { definition } })
            local page = callback(valid.pages[1])
            return {
              addSection = function(section)
                local check = boundary.definition({
                  pages = {
                    {
                      id = definition.id,
                      title = definition.title,
                      columns = definition.columns or 1,
                      sections = {
                        section,
                      },
                    },
                  },
                })
                local target = page.addSection(check.pages[1].sections[1])
                local proxy = {}
                function proxy.add(kind, component)
                  component = table.clone(component or {})
                  component.kind = kind
                  local verified = boundary.definition({
                    pages = {
                      { id = definition.id, title = definition.title, columns = definition.columns or 1, sections = { { components = { component } } } },
                    },
                  })
                  return target.add(kind, verified.pages[1].sections[1].components[1])
                end
                return setmetatable(proxy, {
                  __index = function(_, kind)
                    return function(component) return proxy.add(kind, component) end
                  end,
                })
              end,
            }
          end
        elseif source == "ui" and method == "createMini" then
          result[method] = function(definition)
            for _, field in ipairs({
              "key",
              "visibleKey",
              "invisibleKey",
              "xKey",
              "yKey",
              "bindingKey",
              "modeKey",
              "scaleKey",
              "squareKey",
              "widthKey",
              "heightKey",
            }) do
              local key = definition[field]
              if key and not keys[key] then
                deny("mini.config." .. tostring(key))
              end
            end
            return callback(definition)
          end
        else
          result[method] = callback
        end
      end
    end
    for _, field in ipairs(contract.data or {}) do
      if owned[source] then
        result[field] = copy(provider[field], true)
      end
    end
    local metatable = {
      __index = function(_, field)
        if provider[field] ~= nil then
          deny(source .. "." .. tostring(field))
        end
        return nil
      end,
    }
    setmetatable(result, metatable)
    table.freeze(result)
    metatable.__metatable = "locked"
    table.freeze(metatable)
    return result
  end
  for source, provider in pairs(loaded) do
    views[source] = view(source, provider)
  end
  boundary.modules = table.freeze(views)
  function boundary.dependencies(name, dependencies)
    if not owned[name] then
      return dependencies
    end
    local result = {}
    for alias, source in pairs(loaded[name].__contract.requires or {}) do
      result[alias] = view(source, dependencies[alias])
      for _, method in ipairs((loaded[name].__contract.requiresMethods or {})[alias] or {}) do
        assert(type(result[alias][method]) == "function", name .. ": API não autorizada: " .. source .. "." .. method)
      end
    end
    return result
  end
  function boundary.configScope(name) return owned[name] and profile.id or "hub" end
  function boundary.validateKeys(patch) validatePatch(patch) end
  function boundary.validateDefaults(defaults) validatePatch(defaults or {}) end
  function boundary.migrate(data, migrate)
    local input = {}
    for key, value in pairs(data) do
      if keys[key] or legacy[key] then
        input[key] = copy(value)
      end
    end
    local changed = migrate(input) == true
    for key in pairs(input) do
      if not keys[key] and not legacy[key] then
        deny("migration." .. tostring(key))
      end
    end
    for key, value in pairs(data) do
      if (keys[key] or legacy[key]) and input[key] == nil then
        data[key], changed = nil, true
      end
    end
    for key, value in pairs(input) do
      if data[key] ~= value then
        data[key], changed = value, true
      end
    end
    return changed
  end
  function boundary.context(context, controls)
    local result = {}
    for _, field in ipairs({ "desktop", "notify", "persistent", "abilitiesEnabled" }) do
      result[field] = context[field]
    end
    result.scope = context.scope.child()
    for _, field in ipairs({ "setPrimaryActive", "showPrimary" }) do
      if context[field] then
        result[field] = context[field]
      end
    end
    result.utils = views.utils
    result.controls = copy(controls or {}, true)
    result.hub = table.freeze({ getAbilityAvailability = views.hubapi.getAbilityAvailability })
    return table.freeze(result)
  end
  function boundary.actions(actions, controls)
    actions = table.clone(actions or {})
    local function owns(definition)
      local action = definition.action
      return keys[definition.key] or action and ((actions.callbacks or {})[action] or (actions.states or {})[action] or (controls or {})[action])
    end
    for _, method in ipairs({ "resolve", "attach" }) do
      local callback = actions[method]
      if callback then
        actions[method] = function(definition, ...)
          if owns(definition) then
            return callback(definition, ...)
          end
        end
      end
    end
    return actions
  end
  function boundary.definition(definition, controls)
    local result = copy(definition)
    for field in pairs(result) do
      assert(
        ({ pages = true, pageOrder = true, miniBalls = true, additions = true, createActions = true, input = true, abilityKeys = true, combatUI = true })[field],
        "Unknown game UI field: " .. tostring(field)
      )
    end
    local ownPages = {}
    for _, page in ipairs(result.pages or {}) do
      assert(type(page.id) == "string" and not ownPages[page.id], "Duplicate game page")
      assert(page.utility ~= true, "Game pages use game navigation")
      ownPages[page.id] = true
    end
    for _, id in ipairs(result.pageOrder or {}) do
      assert(ownPages[id], "Games can only order their own pages: " .. tostring(id))
    end
    for _, mini in ipairs(result.miniBalls or {}) do
      if mini.option then
        assert(
          protected[mini.option] and not mini.key and not mini.action and not mini.onActivate,
          "Universal Mini UI references may only bind an existing option"
        )
      end
    end
    for _, addition in ipairs(result.additions or {}) do
      assert(addition.page == "indeed" and addition.sectionTitle, "Game extensions require a named universal section")
    end
    local visited = {}
    local function validate(value)
      if type(value) ~= "table" or visited[value] then
        return
      end
      visited[value] = true
      for field, item in pairs(value) do
        if
          (
            field == "key"
            or field == "shortcutKey"
            or field == "visibleKey"
            or field == "bindingKey"
            or field == "modeKey"
            or field == "xKey"
            or field == "yKey"
            or field == "scaleKey"
            or field == "squareKey"
            or field == "widthKey"
            or field == "heightKey"
            or field == "invisibleKey"
            or field == "enabledKey"
            or field == "visibleWhen"
            or field == "valueKey"
          )
          and type(item) == "string"
          and not keys[item]
        then
          deny("ui.config." .. item)
        end
        validate(item)
      end
    end
    validate(result)
    if result.createActions then
      local factory = result.createActions
      result.createActions = function(context) return boundary.actions(factory(boundary.context(context, controls)), controls) end
    end
    return result
  end
  return boundary
end
GameScope.__contract = { provides = { "setup", "create" }, requires = {} }
return GameScope
