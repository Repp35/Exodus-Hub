-- [[ Phantom Ball input activation state ]]
--!optimize 2
local InputState = {}
local values = { manual = false, automatic = false, dynamic = false }
local observers = {}
local utils
local function notify()
  for connection, callback in pairs(table.clone(observers)) do
    if connection.Connected then
      local ok, reason = pcall(callback)
      if not ok then
        utils.recordError("Phantom.InputState", reason)
      end
    end
  end
end
local function set(key, value)
  value = value == true
  if values[key] == value then
    return false
  end
  values[key] = value
  notify()
  return true
end
function InputState.setup(deps)
  utils = deps.Utils
  return true
end
function InputState.teardown()
  for key in pairs(values) do
    values[key] = false
  end
  for connection in pairs(observers) do
    connection:Disconnect()
  end
  return true
end
function InputState.isManualSpamActive() return values.manual end
function InputState.isAutoSpamActive() return values.automatic end
function InputState.isDynamicSpamActive() return values.dynamic end
function InputState.isSpamActive() return values.manual or values.automatic or values.dynamic end
function InputState.setManualSpamActive(value) return set("manual", value) end
function InputState.setAutoSpamActive(value) return set("automatic", value) end
function InputState.setDynamicSpamActive(value) return set("dynamic", value) end
function InputState.stopAllSpam()
  local changed = InputState.isSpamActive()
  for key in pairs(values) do
    values[key] = false
  end
  if changed then
    notify()
  end
  return true
end
function InputState.observeSpam(callback)
  assert(type(callback) == "function", "Input state observer required")
  local connection = { Connected = true }
  function connection:Disconnect()
    self.Connected = false
    observers[self] = nil
  end
  observers[connection] = callback
  return connection
end
function InputState.normalizeSpamRate(value, fallback)
  local number = tonumber(value) or tonumber(fallback) or 0
  return number == number and number < math.huge and math.max(0, number) or 0
end
InputState.__contract = {
  access = {
    default = "internal.read",
    methods = {
      setManualSpamActive = "manual.input.write",
      setAutoSpamActive = "combat.runtime",
      setDynamicSpamActive = "combat.runtime",
      stopAllSpam = "input.stop",
    },
  },
  provides = {
    "setup",
    "teardown",
    "isManualSpamActive",
    "isAutoSpamActive",
    "isDynamicSpamActive",
    "isSpamActive",
    "setManualSpamActive",
    "setAutoSpamActive",
    "setDynamicSpamActive",
    "stopAllSpam",
    "observeSpam",
    "normalizeSpamRate",
  },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "recordError" } },
}
return InputState
