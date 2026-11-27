--!optimize 2
-- @modules status

local Status = {}
local active
function Status.setup() return true end
function Status.create(providers, reportError)
  local names, failures, reading = {}, {}, {}
  for name, provider in pairs(providers) do
    if type(provider) == "table" and type(provider.getStatus) == "function" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local reader = {}
  function reader.get(name)
    local provider = providers[name]
    if reading[name] or type(provider) ~= "table" or type(provider.getStatus) ~= "function" then
      return nil
    end
    reading[name] = true
    local ok, value = pcall(provider.getStatus)
    reading[name] = nil
    if ok and type(value) == "table" then
      failures[name] = nil
      return value
    end
    if not failures[name] then
      failures[name] = true
      if type(reportError) == "function" then
        pcall(reportError, "Status", name .. ": " .. tostring(ok and "invalid status" or value))
      end
    end
    return nil
  end
  function reader.collect(selected)
    local result = {}
    for _, name in ipairs(selected or names) do
      local value = reader.get(name)
      if value then
        result[name] = value
      end
    end
    return result
  end
  return reader
end
function Status.configure(providers, reportError)
  if type(providers) ~= "table" then
    return false, "provedores de status inválidos"
  end
  active = Status.create(providers, reportError)
  return true
end
function Status.get(name) return active and active.get(name) or nil end
function Status.collect(selected) return active and active.collect(selected) or {} end
Status.__contract = {
  access = {
    default = "internal.read",
    methods = { configure = "infrastructure.write" },
  },
  provides = { "setup", "create", "configure", "get", "collect" },
  requires = {},
}
return Status
