-- [[ Prison Life native local clock ]]
--!optimize 2
local Runtime = {}
local scope, loaded, enabled, writing, publishing
local lighting = game:GetService("Lighting")
local nativeMinutes, nativeAt, nativeRate, sampled = 0, 0, 0, false
local current, lastApplied, lastFrame, nextPublish = 0, nil, 0, 0
local mode, speed = "Fixed", 10
local PREFIX = "UniversalPrisonTime"
Runtime.__config = {
  schema = {
    UniversalPrisonTimeEnabled = "boolean",
    UniversalPrisonTimeMinutes = "rate",
    UniversalPrisonTimeMode = "text",
    UniversalPrisonTimeSpeed = "rate",
  },
  defaults = { UniversalPrisonTimeEnabled = false, UniversalPrisonTimeMode = "Fixed", UniversalPrisonTimeSpeed = 10 },
  resolveDefaults = function() return { UniversalPrisonTimeMinutes = math.floor(lighting:GetMinutesAfterMidnight()) % 1440 } end,
}
function Runtime.setup() return true end
local function write(minutes)
  -- The native HUD reads GetMinutesAfterMidnight directly; keep whole minutes
  -- so its own formatter never displays fractional minutes.
  local value = math.floor(minutes) % 1440
  if math.abs(lighting:GetMinutesAfterMidnight() - value) < 0.001 then
    return
  end
  writing, lastApplied = true, value
  lighting:SetMinutesAfterMidnight(value)
  writing = false
end
local function observeNative()
  if writing then
    return
  end
  local value, now = lighting:GetMinutesAfterMidnight() % 1440, os.clock()
  if lastApplied and math.abs(value - lastApplied) < 0.001 then
    return
  end
  local delta = (value - nativeMinutes + 720) % 1440 - 720
  local elapsed = now - nativeAt
  if math.abs(delta) < 0.001 then
    return
  end
  if elapsed > 0.05 and delta > 0 then
    local rate = delta / elapsed
    if rate <= 120 then
      nativeRate = sampled and nativeRate * 0.7 + rate * 0.3 or rate
      sampled = true
    end
  end
  nativeMinutes, nativeAt = value, now
  if enabled then
    write(current)
  end
end
local function stop()
  if not enabled then
    return
  end
  enabled = false
  -- Latest replicated game time plus the observed native progression, rather
  -- than the old time from when the override was first enabled.
  write((nativeMinutes + (os.clock() - nativeAt) * nativeRate) % 1440)
end
function Runtime.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  stop()
  loaded = nil
  return true
end
function Runtime.bind(modules)
  Runtime.teardown()
  loaded, scope = modules, modules.lifetime.scope()
  enabled, writing, publishing = false, false, false
  lastApplied, nextPublish = nil, 0
  nativeMinutes, nativeAt, nativeRate, sampled = lighting:GetMinutesAfterMidnight() % 1440, os.clock(), 0, false
  current, lastFrame = nativeMinutes, os.clock()
  scope.connect(lighting:GetPropertyChangedSignal("ClockTime"), observeNative)
  scope.connect(lighting:GetPropertyChangedSignal("TimeOfDay"), observeNative)
  local function reconcile(changes)
    if publishing then
      return
    end
    local get = modules.utils.getConfigValue
    local requested = get(PREFIX .. "Enabled") == true
    if requested and not enabled then
      observeNative()
      current = (tonumber(get(PREFIX .. "Minutes")) or nativeMinutes) % 1440
      enabled, lastFrame = true, os.clock()
    elseif not requested and enabled then
      stop()
    end
    if changes and changes[PREFIX .. "Minutes"] ~= nil then
      current = (tonumber(get(PREFIX .. "Minutes")) or current) % 1440
    end
    mode = get(PREFIX .. "Mode")
    speed = math.clamp(tonumber(get(PREFIX .. "Speed")) or 10, 1, 120)
    if enabled then
      write(current)
    end
  end
  scope.add(modules.utils.observeConfig(function(changes)
    for key in pairs(changes) do
      if key:sub(1, #PREFIX) == PREFIX then
        reconcile(changes)
        return
      end
    end
  end))
  scope.connect(game:GetService("RunService").Heartbeat, function()
    local now = os.clock()
    local elapsed = now - lastFrame
    lastFrame = now
    if not enabled then
      return
    end
    local multiplier = mode == "Fast" and speed or mode == "Normal" and 1 or 0
    current = (current + elapsed * nativeRate * multiplier) % 1440
    write(current)
    if now >= nextPublish then
      nextPublish = now + 0.2
      local value = math.floor(current) % 1440
      if modules.utils.getConfigValue(PREFIX .. "Minutes") ~= value then
        publishing = true
        modules.utils.setConfig({ UniversalPrisonTimeMinutes = value })
        publishing = false
      end
    end
  end)
  reconcile()
  return { mode = "prison-life" }
end
function Runtime.createAPI(modules)
  return { getUIConfig = function() return modules.gameui.definition end }
end
Runtime.__contract = { provides = { "setup", "teardown", "bind", "createAPI" }, requires = {} }
return Runtime
