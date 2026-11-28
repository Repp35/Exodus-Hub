-- [[ Prison Life client clock ]]
--!optimize 2
local Clock = {}
local root, activation, deps
local lighting = game:GetService("Lighting")
local minutes, nativeMinutes, lastWritten
local writing = false
local DAY = 24 * 60

local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
function Clock.parseTime(value)
  local text = tostring(value):lower():gsub("%s+", ""):gsub("h$", "")
  local hour, minute = text:match("^(%d%d?):(%d%d)$")
  if hour then
    hour, minute = tonumber(hour), tonumber(minute)
  elseif text:match("^%d%d?$") then
    hour, minute = tonumber(text), 0
  else
    return nil
  end
  if hour > 24 or minute > 59 or hour == 24 and minute ~= 0 then
    return nil
  end
  return (hour % 24) + minute / 60
end
function Clock.formatTime(hour)
  if not finite(hour) then
    return "--:--"
  end
  local total = math.floor(hour * 60 + 0.0001) % DAY
  return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end
local function readNative()
  local hour = lighting.ClockTime
  return finite(hour) and (hour * 60) % DAY or nil
end
local function apply()
  if not activation or not activation.alive then
    return
  end
  -- Whole minutes keep the game's own Lighting.Changed clock formatter intact.
  lastWritten = math.floor(minutes + 0.0001) % DAY
  writing = true
  local ok, reason = deps.Binding.apply(Clock, lighting, "ClockTime", lastWritten / 60, 40)
  writing = false
  assert(ok, tostring(reason))
end
local function stop()
  if activation then
    local previous = activation
    activation = nil
    previous.destroy()
  end
end
local function synchronize(changes)
  if deps.Utils.getConfigValue("PrisonTimeEnabled") ~= true then
    stop()
    return
  end
  if not activation then
    nativeMinutes = nil
    if not deps.Options.isEnabled("UniversalFullbright") then
      nativeMinutes = readNative()
    end
    minutes = (deps.Utils.getConfigValue("PrisonTimeHour") * 60) % DAY
    activation = root.child()
    activation.add(function()
      writing = true
      deps.Binding.release(Clock, lighting, "ClockTime", nativeMinutes and nativeMinutes / 60)
      writing, lastWritten = false, nil
    end)
    deps.Scheduler.connectPhysics(activation, apply)
  elseif changes and changes.PrisonTimeHour ~= nil then
    minutes = (changes.PrisonTimeHour * 60) % DAY
  end
  apply()
end
function Clock.restart()
  if not deps or not activation then
    return false
  end
  minutes = (deps.Utils.getConfigValue("PrisonTimeHour") * 60) % DAY
  apply()
  return true
end
function Clock.setPreset(value)
  if not deps or (value ~= "day" and value ~= "night") then
    return false
  end
  return deps.Utils.setConfig({ PrisonTimeEnabled = true, PrisonTimeHour = value == "day" and 12 or 0, PrisonTimeFixed = true })
end
function Clock.teardown()
  if root then
    root.destroy()
    root = nil
  end
  deps, minutes, nativeMinutes, lastWritten, writing = nil, nil, nil, nil, false
  return true
end
function Clock.setup(services)
  Clock.teardown()
  deps, root = services, services.Lifetime.scope()
  root.add(stop)
  root.connect(lighting:GetPropertyChangedSignal("ClockTime"), function()
    if writing then
      return
    end
    local incoming = readNative()
    if not incoming or activation and lastWritten and math.abs(incoming - lastWritten) < 0.001 then
      return
    end
    if not activation and deps.Options.isEnabled("UniversalFullbright") then
      nativeMinutes = nil
      return
    end
    local previous = nativeMinutes
    nativeMinutes = incoming
    if activation then
      if previous and deps.Utils.getConfigValue("PrisonTimeFixed") ~= true then
        -- Follow the real game's ticks, including midnight, with a local offset.
        local delta = (incoming - previous + DAY / 2) % DAY - DAY / 2
        if math.abs(delta) <= 60 then
          minutes = (minutes + delta * deps.Utils.getConfigValue("PrisonTimeSpeed")) % DAY
        end
      end
      apply()
    end
  end)
  root.add(deps.Utils.observeConfig(function(changes)
    for _, key in ipairs({ "PrisonTimeEnabled", "PrisonTimeHour", "PrisonTimeFixed", "PrisonTimeSpeed" }) do
      if changes[key] ~= nil then
        synchronize(changes)
        return
      end
    end
  end))
  synchronize()
  return true
end
Clock.__config = {
  schema = { PrisonTimeEnabled = "boolean", PrisonTimeHour = "rate", PrisonTimeFixed = "boolean", PrisonTimeSpeed = "rate" },
  defaults = { PrisonTimeEnabled = false, PrisonTimeHour = 12, PrisonTimeFixed = true, PrisonTimeSpeed = 1 },
  constraints = { PrisonTimeHour = { min = 0, max = 24 }, PrisonTimeSpeed = { min = 0.1, max = 20 } },
}
Clock.__contract = {
  provides = { "setup", "teardown", "parseTime", "formatTime", "restart", "setPreset" },
  requires = { Utils = "utils", Lifetime = "lifetime", Binding = "propertybinding", Scheduler = "universalcontroller", Options = "options" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig" },
    Lifetime = { "scope" },
    Binding = { "apply", "release" },
    Scheduler = { "connectPhysics" },
    Options = { "isEnabled" },
  },
}
return Clock
