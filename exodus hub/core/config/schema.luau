-- [[ config ]]
--!optimize 2
-- @modules config

-- module
local Config = {}
local Registry = {}
local Keys = {}
local SessionOnly = {}
local Owners, Scopes, Constraints = {}, {}, {}
local ResolvedDefaults

-- configuration
local CONFIG = {
  RATE_MIN = 0,
  DELAY_MIN = 0,
  DELAY_MAX = 5,
  DELAY_MS_MAX = 400,
  POSITION_MIN = -10000,
  POSITION_MAX = 10000,
  ERRORS = {
    boolean = "flag inválida: %s",
    rate = "taxa inválida: %s",
    delay = "atraso inválido: %s",
    delayMs = "tempo inválido: %s",
    position = "posição inválida: %s",
    keyCode = "keybind inválido: %s",
    miniScale = "tamanho da Mini UI inválido",
  },
}

-- validation
local function isFiniteNumber(value) return type(value) == "number" and value == value and value < math.huge and value > -math.huge end
local function validKeyCode(value)
  return typeof(value) == "EnumItem"
    and (
      value.EnumType == Enum.KeyCode
      or value == Enum.UserInputType.MouseButton1
      or value == Enum.UserInputType.MouseButton2
      or value == Enum.UserInputType.MouseButton3
    )
end
local validationErrors = CONFIG.ERRORS
local validators = {
  text = function(value) return type(value) == "string" and #value <= 256 end,
  boolean = function(value) return type(value) == "boolean" end,
  rate = function(value) return isFiniteNumber(value) and value >= CONFIG.RATE_MIN end,
  delay = function(value) return isFiniteNumber(value) and value >= CONFIG.DELAY_MIN and value <= CONFIG.DELAY_MAX end,
  delayMs = function(value) return isFiniteNumber(value) and value >= CONFIG.DELAY_MIN and value <= CONFIG.DELAY_MS_MAX end,
  position = function(value) return isFiniteNumber(value) and value >= CONFIG.POSITION_MIN and value <= CONFIG.POSITION_MAX end,
  keyCode = validKeyCode,
  miniScale = function(value) return isFiniteNumber(value) and value >= 0.5 and value <= 2 end,

}

local function validateValue(key, kind, value, constraints)
  local validator = validators[kind]
  if validator and validator(value) then
    local bounds = constraints or Constraints[key]
    if not bounds then
      return true
    end
    if (bounds.min and value < bounds.min) or (bounds.max and value > bounds.max) then
      return false, "valor fora do intervalo: " .. key
    end
    if bounds.choices and not table.find(bounds.choices, value) then
      return false, "opção inválida: " .. key
    end
    return true
  end
  local message = validationErrors[kind] or "valor inválido: %s"
  return false, message:find("%s", 1, true) and message:format(key) or message
end
local function copy(source)
  local result = {}
  for key, value in pairs(source or {}) do
    result[key] = value
  end
  return result
end

-- registration
function Config.register(name, definition, scope)
  if type(name) ~= "string" or type(definition) ~= "table" or Registry[name] then
    return false
  end
  if definition.resolveDefaults ~= nil and type(definition.resolveDefaults) ~= "function" then
    return false
  end
  if definition.persistent ~= nil and type(definition.persistent) ~= "boolean" and type(definition.persistent) ~= "table" then
    return false
  end
  if definition.constraints ~= nil and type(definition.constraints) ~= "table" then
    return false
  end
  if definition.schema ~= nil and type(definition.schema) ~= "table" then
    return false
  end
  if definition.defaults ~= nil and type(definition.defaults) ~= "table" then
    return false
  end
  for field in pairs(definition) do
    if not ({ schema = true, defaults = true, persistent = true, constraints = true, resolveDefaults = true, legacy = true })[field] then
      return false
    end
  end
  local schema = type(definition.schema) == "table" and definition.schema or {}
  local defaults = type(definition.defaults) == "table" and definition.defaults or {}
  if type(definition.persistent) == "table" then
    for key, value in pairs(definition.persistent) do
      if not schema[key] or type(value) ~= "boolean" then
        return false
      end
    end
  end
  for key, kind in pairs(schema) do
    if type(key) ~= "string" or not validators[kind] or Keys[key] then
      return false
    end
  end
  for key, value in pairs(defaults) do
    local kind = schema[key]
    if not kind or not validateValue(key, kind, value) then
      return false
    end
  end
  local constraints = definition.constraints or {}
  for key, bounds in pairs(constraints) do
    if not schema[key] or type(bounds) ~= "table" then
      return false
    end
    if bounds.min ~= nil and not isFiniteNumber(bounds.min) then
      return false
    end
    if bounds.max ~= nil and not isFiniteNumber(bounds.max) then
      return false
    end
    if (bounds.min or bounds.max) and schema[key] ~= "rate" and schema[key] ~= "position" and schema[key] ~= "miniScale" then
      return false
    end
    if bounds.min and bounds.max and bounds.min > bounds.max then
      return false
    end
    if bounds.choices ~= nil then
      if type(bounds.choices) ~= "table" or #bounds.choices == 0 then
        return false
      end
      for _, value in ipairs(bounds.choices) do
        if not validateValue(key, schema[key], value) then
          return false
        end
      end
    end
  end
  for key, value in pairs(defaults) do
    if not validateValue(key, schema[key], value, constraints[key]) then
      return false
    end
  end
  for key, kind in pairs(schema) do
    local bounds = constraints[key]
    if bounds then
      Constraints[key] = { min = bounds.min, max = bounds.max, choices = bounds.choices and table.clone(bounds.choices) }
    end
    Keys[key], Owners[key], Scopes[key] = kind, name, scope or "hub"
    SessionOnly[key] = definition.persistent == false or type(definition.persistent) == "table" and definition.persistent[key] == false
  end
  ResolvedDefaults = nil
  Registry[name] = {
    schema = copy(schema),
    defaults = copy(defaults),
    resolveDefaults = definition.resolveDefaults,
    persistent = type(definition.persistent) == "table" and copy(definition.persistent) or definition.persistent ~= false,
  }
  return true
end

-- defaults
function Config.defaults(context)
  if ResolvedDefaults then
    return copy(ResolvedDefaults)
  end
  local result = {}
  for _, definition in pairs(Registry) do
    for key, value in pairs(definition.defaults) do
      result[key] = value
    end
    if definition.resolveDefaults then
      local values = definition.resolveDefaults(context)
      for key, value in pairs(values) do
        assert(definition.schema[key] and validateValue(key, definition.schema[key], value), "Invalid dynamic default: " .. key)
        result[key] = value
      end
    end
  end
  for key, value in pairs(context and context.profile and context.profile.defaults or {}) do
    assert(Keys[key] and validateValue(key, Keys[key], value), "Invalid game default: " .. tostring(key))
    result[key] = value
  end
  ResolvedDefaults = copy(result)
  return result
end

-- validation-api
function Config.validatePatch(patch)
  if type(patch) ~= "table" then
    return false, "configuração não é uma tabela"
  end
  for key, value in pairs(patch) do
    local kind = Keys[key]
    if not kind then
      return false, "chave de configuração desconhecida: " .. tostring(key)
    end
    local ok, reason = validateValue(key, kind, value)
    if not ok then
      return false, reason
    end
  end
  return true
end
function Config.normalizePatch(patch)
  local ok, reason = Config.validatePatch(patch)
  if not ok then
    return nil, reason
  end
  return copy(patch)
end
function Config.validate(config)
  if type(config) ~= "table" then
    return false, "configuração não é uma tabela"
  end
  local ok, reason = Config.validatePatch(config)
  if not ok then
    return false, reason
  end
  return true
end

-- public-api
function Config.hasKey(key) return Keys[key] ~= nil end
function Config.isPersistentKey(key) return Keys[key] ~= nil and not SessionOnly[key] end
function Config.describe(key)
  if not Keys[key] then
    return nil
  end
  return {
    kind = Keys[key],
    owner = Owners[key],
    scope = Scopes[key],
    persistent = not SessionOnly[key],
    default = ResolvedDefaults and ResolvedDefaults[key],
    constraints = Constraints[key]
      and { min = Constraints[key].min, max = Constraints[key].max, choices = Constraints[key].choices and table.clone(Constraints[key].choices) },
  }
end
function Config.getRegistry()
  local result = {}
  for name, definition in pairs(Registry) do
    result[name] = {
      schema = copy(definition.schema),
      defaults = copy(definition.defaults),
      persistent = type(definition.persistent) == "table" and copy(definition.persistent) or definition.persistent,
    }
  end
  return result
end

-- contract
Config.__contract = {
  access = {
    default = "internal.read",
    methods = { register = "infrastructure.write" },
  },
  provides = { "register", "defaults", "validate", "validatePatch", "normalizePatch", "getRegistry", "isPersistentKey", "describe", "hasKey" },
  requires = {},
}

return Config
