-- [[ Game modules consume owned settings and explicit shared services ]]
--!optimize 2
-- @modules gamescope
local GameScope = {}
local sharedServices = {
  utils = {
    setConfig = true,
    observeConfig = true,
    observeSpam = true,
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
    stopAllSpam = true,
    setManualSpamActive = true,
    setAutoSpamActive = true,
    setDynamicSpamActive = true,
  },
  lifetime = { scope = true, connections = true },
  profiler = { begin = true, finish = true, count = true },
  status = { collect = true },
  ui = { notify = true, notifyCorner = true, createMini = true },
  uinativeability = { create = true, reveal = true },
  propertybinding = { create = true, apply = true, release = true },
  noclip = { acquire = true, release = true },
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
local function isRead(method)
  for _, prefix in ipairs({ "get", "is", "has", "are", "uses", "normalize", "validate", "decode", "format", "should" }) do
    if method:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end
function GameScope.setup() return true end
function GameScope.create(loaded, profile)
  local owned, keys, protected, legacy, views = {}, {}, {}, {}, {}
  local root, uiRoot = "hubs/" .. profile.id .. "/", "ui/games/" .. profile.id .. "/"
  for name, module in pairs(loaded) do
    local path = loaded.permissions.getPath(name)
    owned[name] = path ~= nil and (path:sub(1, #root) == root or path:sub(1, #uiRoot) == uiRoot)
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
      if owned[source] or service or isRead(method) then
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
        elseif source == "ui" and method == "createMini" then
          result[method] = function(definition)
            for _, field in ipairs({ "key", "visibleKey", "xKey", "yKey", "bindingKey", "modeKey" }) do
              local key = definition[field]
              if key and not keys[key] then
                deny("mini.config." .. tostring(key))
              end
            end
            return callback(definition)
          end
        elseif not owned[source] and isRead(method) then
          result[method] = function(...)
            local values = table.pack(callback(...))
            for index = 1, values.n do
              values[index] = copy(values[index], true, nil, function() deny(source .. "." .. method .. " returned command") end)
            end
            return table.unpack(values, 1, values.n)
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
    local result = table.clone(context)
    result.scope = context.scope.child()
    result.utils = views.utils
    result.controls = copy(controls or {}, true)
    result.hub = views.hubapi
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
          )
          and type(item) == "string"
          and not keys[item]
          and not protected[item]
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
