-- [[ bounded, opt-in runtime instrumentation ]]

-- code
local Profiler = {}
local enabled = false
local samples = {}
local CONFIG = {
  LIMIT = 64,
}

local LIMIT = CONFIG.LIMIT
function Profiler.setup() return true end
function Profiler.setEnabled(value)
  enabled = value == true; table.clear(samples)
end
function Profiler.isEnabled() return enabled end
function Profiler.begin(name)
  if not enabled then return nil end
  if debug.profilebegin then debug.profilebegin(name) end
  return os.clock()
end
function Profiler.count(name, amount)
  if not enabled then return end
  local item = samples[name]
  if not item then
    local size = 0
    for _ in pairs(samples) do
      size += 1
    end
    if size >= LIMIT then return end
    item = { calls = 0, total = 0, maximum = 0 }; samples[name] = item
  end
  item.calls += amount or 1
end
function Profiler.finish(name, started)
  if not started then return end
  if debug.profileend then debug.profileend() end
  if not enabled then return end
  local item = samples[name]
  if not item then
    local count = 0
    for _ in pairs(samples) do
      count += 1
    end
    if count >= LIMIT then return end
    item = { calls = 0, total = 0, maximum = 0 }; samples[name] = item
  end
  local elapsed = os.clock() - started; item.calls += 1
  item.total += elapsed; item.maximum = math.max(item.maximum, elapsed)
end
function Profiler.getStatus()
  local result = {}
  for name, item in pairs(samples) do
    result[name] = table.clone(item)
  end
  return { enabled = enabled, samples = result }
end
function Profiler.teardown()
  enabled = false; table.clear(samples)
end
Profiler.__contract = { requires = {}, provides = { "setup", "teardown", "setEnabled", "isEnabled", "begin", "finish", "count", "getStatus" } }

return Profiler
