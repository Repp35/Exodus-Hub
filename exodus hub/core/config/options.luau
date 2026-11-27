-- [[ read-only option state ]]
--!optimize 2
-- @modules options
local Options = {}
local utils, config
function Options.setup(deps)
  utils, config = deps.Utils, deps.Config
  return true
end
function Options.get(key)
  assert(config.hasKey(key), "Unknown option: " .. tostring(key))
  return utils.getConfigValue(key)
end
function Options.isEnabled(key) return Options.get(key) == true end
function Options.describe(key)
  local descriptor = config.describe(key)
  if not descriptor then
    return nil
  end
  if table.isfrozen(descriptor) then
    return descriptor
  end
  if descriptor.constraints then
    if descriptor.constraints.choices and not table.isfrozen(descriptor.constraints.choices) then
      table.freeze(descriptor.constraints.choices)
    end
    if not table.isfrozen(descriptor.constraints) then
      table.freeze(descriptor.constraints)
    end
  end
  return table.freeze(descriptor)
end
function Options.observe(keys, callback)
  assert(type(callback) == "function", "Option observer required")
  keys = type(keys) == "string" and { keys } or keys
  assert(type(keys) == "table" and #keys > 0, "Option keys required")
  local selected = {}
  for _, key in ipairs(keys) do
    assert(config.hasKey(key), "Unknown option: " .. tostring(key))
    selected[key] = true
  end
  return utils.observeConfig(function(changes)
    local result = {}
    for key, value in pairs(changes) do
      if selected[key] then
        result[key] = value
      end
    end
    if next(result) then
      callback(table.freeze(result))
    end
  end)
end
Options.__contract = {
  access = { default = "internal.read" },
  provides = { "setup", "get", "isEnabled", "describe", "observe" },
  requires = { Utils = "utils", Config = "config" },
  requiresMethods = { Utils = { "getConfigValue", "observeConfig" }, Config = { "describe", "hasKey" } },
}
return Options
