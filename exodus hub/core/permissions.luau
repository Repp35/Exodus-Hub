-- [[ permissions ]]
--!optimize 2
-- @modules permissions

local Permissions = {}
local CONFIG = { RESERVED = { __contract = true, __config = true } }
local readonly
local POLICY = { base = {}, types = {}, rules = {}, modules = {}, defaults = {} }
local function contains(items, value)
  for _, item in ipairs(items or {}) do
    if item == value then
      return true
    end
  end
  return false
end
local function configure(policy)
  assert(type(policy) == "table" and type(policy.types) == "table", "Missing internal permission policy")
  POLICY =
    readonly({ base = policy.base or {}, types = policy.types, rules = policy.rules or {}, modules = policy.modules or {}, defaults = policy.defaults or {} })
  return true
end
local function familyFor(name, path)
  local kind = POLICY.modules[name]
  if not kind then
    for _, rule in ipairs(POLICY.rules) do
      if path and type(rule.prefix) == "string" and path:sub(1, #rule.prefix) == rule.prefix then
        kind = rule.type
        break
      end
    end
  end
  assert(kind and POLICY.types[kind], "Module has no authorized type: " .. name)
  return kind
end
local function hasFunctions(value, seen)
  if type(value) == "function" then
    return true
  end
  if type(value) ~= "table" then
    return false
  end
  seen = seen or {}
  if seen[value] then
    return false
  end
  seen[value] = true
  for _, item in pairs(value) do
    if hasFunctions(item, seen) then
      return true
    end
  end
  return false
end
local function capability(provider, method, data)
  if data then
    return provider.commandData[method] and (provider.access.default or POLICY.defaults[provider.family] or "internal.write") or "internal.read"
  end
  if provider.access.methods and provider.access.methods[method] then
    return provider.access.methods[method]
  end
  if method == "setup" or method == "teardown" or method == "bindCharacter" or method == "detachCharacter" then
    return "lifecycle.write"
  end
  for _, prefix in ipairs({ "get", "is", "has", "are", "uses", "normalize", "validate", "decode", "format", "should" }) do
    if method:sub(1, #prefix) == prefix then
      return "internal.read"
    end
  end
  for _, prefix in ipairs({ "observe", "track", "untrack" }) do
    if method:sub(1, #prefix) == prefix then
      return "lifetime.manage"
    end
  end
  return provider.access.default or POLICY.defaults[provider.family] or "internal.write"
end
local function allowed(entry, permission)
  local grants = POLICY.types[entry.family]
  return contains(grants, "*") or contains(grants, permission) or contains(POLICY.base, permission)
end
local function canConsume(entry, provider, method, data)
  local permission = capability(provider, method, data)
  if allowed(entry, permission) then
    return true, permission
  end
  if not data and contains(provider.access.scoped, method) and allowed(entry, "config.own") then
    return true, "config.own"
  end
  return false, permission
end

-- registry
local registry = {}

-- validation
local function deny(name, action) error(("Permissão negada: %s -> %s"):format(name, action), 3) end
local function namedSet(owner, field, items)
  if type(items) ~= "table" then
    error(owner .. ": " .. field .. " inválido", 3)
  end
  local result, count = {}, 0
  for index, name in pairs(items) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(name) ~= "string" or name == "" or result[name] then
      error(owner .. ": " .. field .. " contém entrada inválida ou duplicada", 3)
    end
    result[name] = true
    count += 1
  end
  if count ~= #items then
    error(owner .. ": " .. field .. " deve ser uma lista contínua", 3)
  end
  return result
end
local function validate(name, module, path)
  if type(name) ~= "string" or type(module) ~= "table" then
    error("Permissions: módulo inválido", 2)
  end
  local contract = module.__contract
  if type(contract) ~= "table" then
    error(name .. ": contrato ausente", 2)
  end
  local provides = namedSet(name, "provides", contract.provides)
  local data = namedSet(name, "data", contract.data or {})
  for field in pairs(data) do
    if provides[field] or type(module[field]) ~= "table" then
      error(name .. ": dado público inválido: " .. field, 2)
    end
  end
  for field in pairs(provides) do
    if type(module[field]) ~= "function" then
      error(name .. ": API declarada ausente: " .. field, 2)
    end
  end
  for field, value in pairs(module) do
    if type(value) == "function" and not provides[field] then
      error(name .. ": função não declarada no contrato: " .. tostring(field), 2)
    end
    if type(value) == "table" and not CONFIG.RESERVED[field] and not data[field] then
      error(name .. ": tabela pública não declarada: " .. tostring(field), 2)
    end
  end
  if contract.bindCharacter == true and (not provides.bindCharacter or not provides.detachCharacter) then
    error(name .. ": contrato bindCharacter incompleto", 2)
  end
  if contract.onBallSync == true and not provides.onBallSync then
    error(name .. ": contrato onBallSync incompleto", 2)
  end
  local requires = contract.requires or {}
  local methods = contract.requiresMethods or {}
  local fields = contract.requiresData or {}
  local versions = contract.requiresVersions or {}
  if type(requires) ~= "table" or type(methods) ~= "table" or type(fields) ~= "table" or type(versions) ~= "table" then
    error(name .. ": dependências inválidas", 2)
  end
  local uses, sources = {}, {}
  for alias, source in pairs(requires) do
    if type(alias) ~= "string" or type(source) ~= "string" or alias == "" or source == "" or sources[source] or source == name then
      error(name .. ": dependência inválida ou duplicada: " .. tostring(alias), 2)
    end
    sources[source] = true
    uses[alias] = {
      source = source,
      methods = namedSet(name, alias .. ".requiresMethods", methods[alias] or {}),
      data = namedSet(name, alias .. ".requiresData", fields[alias] or {}),
    }
    for field in pairs(uses[alias].methods) do
      if uses[alias].data[field] then
        error(name .. ": método e dado duplicados: " .. field, 2)
      end
    end
  end
  for alias in pairs(methods) do
    if not uses[alias] then
      error(name .. ": requiresMethods sem dependência: " .. tostring(alias), 2)
    end
  end
  for alias in pairs(fields) do
    if not uses[alias] then
      error(name .. ": requiresData sem dependência: " .. tostring(alias), 2)
    end
  end
  for alias, minimum in pairs(versions) do
    if not uses[alias] or type(minimum) ~= "number" or minimum < 0 or minimum ~= minimum or minimum == math.huge then
      error(name .. ": versão de dependência inválida: " .. tostring(alias), 2)
    end
    uses[alias].minimum = minimum
  end
  if
    contract.version ~= nil
    and (type(contract.version) ~= "number" or contract.version < 0 or contract.version ~= contract.version or contract.version == math.huge)
  then
    error(name .. ": versão do contrato inválida", 2)
  end
  local commandData = {}
  for field in pairs(data) do
    commandData[field] = hasFunctions(module[field])
  end
  registry[name] = {
    name = name,
    path = path,
    family = familyFor(name, path),
    module = module,
    provides = provides,
    data = data,
    commandData = commandData,
    uses = uses,
    version = contract.version,
    access = readonly(contract.access or {}),
    owned = readonly(module.__config and module.__config.schema or {}),
  }
  return true
end
readonly = function(value, visited)
  if type(value) ~= "table" then
    return value
  end
  visited = visited or {}
  if visited[value] then
    return visited[value]
  end
  local copy = {}
  visited[value] = copy
  for key, item in pairs(value) do
    copy[readonly(key, visited)] = readonly(item, visited)
  end
  return table.freeze(copy)
end
local function wrap(consumer, source, provider)
  local entry, exposed = registry[consumer], registry[source]
  if not entry or not exposed or exposed.module ~= provider then
    error("Permissions: módulo não validado: " .. tostring(source), 2)
  end
  local use
  for _, dependency in pairs(entry.uses) do
    if dependency.source == source then
      use = dependency
      break
    end
  end
  if not use then
    error("Dependência interna não declarada: " .. consumer .. " -> " .. source, 2)
  end
  for method in pairs(use.methods) do
    if not exposed.provides[method] then
      error(consumer .. ": API ausente: " .. source .. "." .. method, 2)
    end
    local ok, permission = canConsume(entry, exposed, method, false)
    if not ok then
      deny(consumer, entry.family .. " -> " .. permission)
    end
  end
  for field in pairs(use.data) do
    if not exposed.data[field] then
      error(consumer .. ": dado ausente: " .. source .. "." .. field, 2)
    end
    local ok, permission = canConsume(entry, exposed, field, true)
    if not ok then
      deny(consumer, entry.family .. " -> " .. permission)
    end
  end
  local members = {}
  for method in pairs(exposed.provides) do
    local ok, permission = canConsume(entry, exposed, method, false)
    if ok then
      local callback = provider[method]
      if permission == "config.own" then
        members[method] = function(patch)
          if type(patch) ~= "table" then
            error("Config patch inválido", 2)
          end
          for key in pairs(patch) do
            if not entry.owned[key] then
              deny(consumer, "config.write outside owned settings: " .. tostring(key))
            end
          end
          return callback(patch)
        end
      else
        members[method] = function(...)
          local result = table.pack(callback(...))
          if permission == "internal.read" and not contains(exposed.access.references, method) then
            for i = 1, result.n do
              if type(result[i]) == "table" then
                result[i] = readonly(result[i])
              end
            end
          end
          return table.unpack(result, 1, result.n)
        end
      end
    end
  end
  for field in pairs(exposed.data) do
    if canConsume(entry, exposed, field, true) then
      members[field] = readonly(provider[field])
    end
  end
  table.freeze(members)
  local view = {}
  setmetatable(view, {
    __index = function(_, field)
      local value = members[field]
      if value ~= nil then
        return value
      end
      if exposed.provides[field] or exposed.data[field] then
        local _, permission = canConsume(entry, exposed, field, exposed.data[field] == true)
        deny(consumer, entry.family .. " -> " .. permission)
      end
      error("API interna ausente: " .. source .. "." .. tostring(field), 2)
    end,
    __newindex = function(_, field) deny(consumer, "api.write." .. source .. "." .. tostring(field)) end,
  })
  local metatable = getmetatable(view)
  table.freeze(view)
  metatable.__metatable = "locked"
  table.freeze(metatable)
  return view
end

-- resolution
local function resolve(consumer, loaded)
  local entry = registry[consumer]
  if type(loaded) ~= "table" or not entry or entry.module ~= loaded[consumer] then
    error("Permissions: módulo não validado: " .. tostring(consumer), 2)
  end
  local dependencies = {}
  for alias, use in pairs(entry.uses) do
    local provider, source = loaded[use.source], registry[use.source]
    if not source or source.module ~= provider then
      error(("API interna ausente: dependência %s (%s)"):format(alias, use.source), 2)
    end
    if use.minimum and (type(source.version) ~= "number" or source.version < use.minimum) then
      error(("API incompatível: %s requer versão %s; encontrada %s"):format(alias, tostring(use.minimum), tostring(source.version)), 2)
    end
    dependencies[alias] = wrap(consumer, use.source, provider)
  end
  return dependencies
end

-- introspection
local function policy(name)
  local entry = registry[name]
  if not entry then
    error("Permissions: módulo não registrado: " .. tostring(name), 2)
  end
  local result = { family = entry.family, capabilities = table.clone(POLICY.base), provides = {}, dependencies = {} }
  for _, permission in ipairs(POLICY.types[entry.family]) do
    result.capabilities[#result.capabilities + 1] = permission
  end
  table.sort(result.capabilities)
  for method in pairs(entry.provides) do
    result.provides[#result.provides + 1] = method
  end
  table.sort(result.provides)
  for _, use in pairs(entry.uses) do
    result.dependencies[#result.dependencies + 1] = use.source
  end
  table.sort(result.dependencies)
  return result
end

-- public-api
Permissions.configure = configure
Permissions.validate = validate
Permissions.wrap = wrap
Permissions.resolve = resolve
Permissions.policy = policy

-- contract
Permissions.__contract = {
  provides = { "configure", "validate", "wrap", "resolve", "policy" },
  requires = {},
}

return Permissions
