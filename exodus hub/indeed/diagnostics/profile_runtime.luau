-- [[ bounded runtime capture; execute during the same clash scenario on each revision ]]

-- code
local CONFIG = {
  DURATION = 30,
  FRAME_SAMPLES = 4096,
  OUTPUT = "exodus-runtime-profile.json",
}

local context = type(_G.Exodus) == "table" and _G.Exodus.Context
assert(type(context) == "table", "Start Exodus before profiling")
local revision = _G.Exodus.Revision
local profiler = context.profiler
local previous = profiler and profiler.isEnabled()
if profiler then
  profiler.setEnabled(true)
end
local services = game:GetService("RunService")
local stats = game:GetService("Stats")
local http = game:GetService("HttpService")
local function memory()
  local ok, value = pcall(stats.GetTotalMemoryUsageMb, stats)
  return ok and value or nil
end
local started, initialMemory = os.clock(), memory()
local samples, count, cursor = {}, 0, 0
local connection, finished
local function finish()
  if finished then
    return
  end
  finished = true
  if connection then
    connection:Disconnect()
  end
  local result = {
    revision = revision,
    elapsed = os.clock() - started,
    frameCount = count,
    retainedFrameSamples = #samples,
    memoryStartMb = initialMemory,
    memoryEndMb = memory(),
    modules = profiler and profiler.getStatus() or nil,
    cpuMs = {},
  }

  table.sort(samples)
  local function percentile(q) return #samples > 0 and samples[math.max(1, math.ceil(#samples * q))] * 1000 or nil end
  result.frameMs = { p50 = percentile(0.5), p95 = percentile(0.95), p99 = percentile(0.99) }
  for name, sample in pairs(result.modules and result.modules.samples or {}) do
    result.cpuMs[name] = { calls = sample.calls, total = sample.total * 1000, maximum = sample.maximum * 1000 }
  end
  if profiler then
    profiler.setEnabled(previous)
  end
  local body = http:JSONEncode(result)
  if type(writefile) == "function" then
    local ok, message = pcall(writefile, CONFIG.OUTPUT, body)
    if ok then
      print("[Exodus] Profile saved: " .. CONFIG.OUTPUT)
    else
      warn(message)
      print(body)
    end
  else
    print(body)
  end
end
connection = services.Heartbeat:Connect(function(dt)
  if not _G.Exodus or _G.Exodus.Context ~= context then
    finish()
    return
  end
  if dt > 0 and dt < math.huge then
    count += 1
    cursor = cursor % CONFIG.FRAME_SAMPLES + 1
    samples[cursor] = dt
  end
  if os.clock() - started >= CONFIG.DURATION then
    finish()
  end
end)
task.delay(CONFIG.DURATION + 1, finish)
