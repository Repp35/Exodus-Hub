-- [[ dumper retries with a deterministic task scheduler ]]

-- code
local now, queue, sequence = 0, {}, 0
local stopped = {}
local task = {}
local os = { clock = function() return now end, time = function() return 1700000000 end }
local function enqueue(thread, due)
  sequence += 1; queue[#queue + 1] = { thread = thread, due = due, sequence = sequence }
end
function task.defer(callback)
  local thread = coroutine.create(callback); enqueue(thread, now)
  return thread
end
task.spawn = task.defer
function task.wait(delay) return coroutine.yield(delay and math.max(delay, 0.001) or 0.02) end
function task.cancel(thread) stopped[thread] = true end
local function drain()
  local steps = 0
  while #queue > 0 do
    table.sort(queue, function(a, b) return a.due == b.due and a.sequence < b.sequence or a.due < b.due end)
    local item = table.remove(queue, 1)
    if not stopped[item.thread] then
      now = math.max(now, item.due); local ok, delay = coroutine.resume(item.thread)
      assert(ok, tostring(delay))
      if coroutine.status(item.thread) ~= "dead" then enqueue(item.thread, now + delay) end
    end
    steps += 1; assert(steps < 100000, "Dumper never completed")
  end
end
local nativeTypeof = typeof
local function typeof(value) return type(value) == "table" and value.instance and "Instance" or nativeTypeof(value) end
local files, folders, writes, apis = {}, {}, {}, {}
local failWrite
local function isfolder(path) return folders[path] == true end
local function makefolder(path) folders[path] = true end
local function writefile(path, content)
  writes[path] = (writes[path] or 0) + 1
  if failWrite and failWrite(path, writes[path]) then error("temporary disk failure") end
  files[path] = content
end
local function getfenv() return apis end
local function object(name, class, parent, source)
  return {
    instance = true,
    Name = name,
    ClassName = class,
    Parent = parent,
    Source = source,
    GetFullName = function(self) return self.Name end,
    GetAttributes = function() return {} end,
  }
end
local game = object("Game", "DataModel")
game.PlaceId, game.GameId = 42, 7
local objects = {}
local productName, productFailure, productHang = "Phantom Ball", false, false
function game:GetDescendants() return objects end
function game:GetService(name)
  if name == "CollectionService" then
    return { GetTags = function() return {} end }
  end
  if name == "MarketplaceService" then
    return {
      GetProductInfo = function()
        if productHang then task.wait(1000) end
        if productFailure then error("offline") end
        return { Name = productName }
      end,
    }
  end
end
local Dumper
local function execute()
  local result, errors, messages = nil, {}, {}
  assert(Dumper.start({
    onComplete = function(value) result = value end,
    onError = function(err) errors[#errors + 1] = err end,
    onStatus = function(message) messages[#messages + 1] = message end,
  }))
  drain(); assert(#errors == 0, table.concat(errors, "\n"))
  assert(result and not Dumper.isRunning(), "Dump did not finish"); return result, messages
end
local calls, callTimes, target = {}, {}, {}
for i = 1, 19 do
  local script = object("Retry" .. i, "ModuleScript", game); objects[#objects + 1] = script
  target[script] = i <= 17 and 2 + i % 3 or math.huge
end
objects[#objects + 1] = object("WriteRetry", "LocalScript", game, "return 'disk'")
objects[#objects + 1] = object("Stable", "LocalScript", game, "return 'stable'")
apis.decompile = function(script)
  calls[script] = (calls[script] or 0) + 1; callTimes[script] = callTimes[script] or {}
  table.insert(callTimes[script], now)
  if calls[script] >= target[script] then return "return 'recovered'" end
  return "failed to decompile"
end
failWrite = function(path, count) return path:find("/scripts/WriteRetry", 1, true) ~= nil and count <= 2 end
local result, messages = execute()
assert(result.total == 21 and result.saved == 19 and result.failed == 2)
assert(result.initialFailed == 20 and result.recovered == 18 and result.retryRounds == 10)
assert(result.folder == "SrcDump_Phantom_Ball_1")
assert(files[result.folder .. "/summary.txt"]:find("recovered_on_retry=18", 1, true))
assert(not files[result.folder .. "/manifest.txt"]:find("[PENDING]", 1, true))
local failureLog = files[result.folder .. "/errors.txt"]
assert(failureLog:find("Retry18", 1, true) and failureLog:find("Retry19", 1, true))
assert(not failureLog:find("WriteRetry", 1, true))
for script, threshold in pairs(target) do
  assert(calls[script] == math.min(threshold, 11), "Successful scripts retried or attempts exceeded"); assert(callTimes[script][2] - callTimes[script][1] >= 1, "No pause between passes")
end
assert(#messages >= 10)
objects = { object("Stable", "LocalScript", game, "return 1") }
apis = {}
failWrite = nil
local nextResult = execute()
assert(nextResult.folder == "SrcDump_Phantom_Ball_2")
assert(nextResult.retryRounds == 0 and nextResult.failed == 0)
productName = "A/B: Game?"
assert(execute().folder == "SrcDump_A_B_Game__1")
productFailure = true
assert(execute().folder == "SrcDump_Place_42_1")
productHang = true
local started = now
assert(execute().folder == "SrcDump_Place_42_2")
assert(now - started < 11, "Name lookup never timed out")
productFailure, productHang = false, false
objects = { object("FreshBytecode", "ModuleScript", game) }
local byteReads = 0
apis = {
  getscriptbytecode = function()
    byteReads += 1; return byteReads == 1 and "old bytes" or "new bytes"
  end,
  decompile = function(argument) return argument == "new bytes" and "return 'fresh'" or "failed to decompile" end,
}

local refreshed = execute()
assert(refreshed.saved == 1 and refreshed.failed == 0 and refreshed.recovered == 1)
assert(refreshed.bytecode == 1 and byteReads == 2, "Bytecode refresh counted the same script twice")
apis = {}
objects = { object("Hung", "ModuleScript", game) }
local hungCalls = 0
apis.decompile = function()
  hungCalls += 1; task.wait(1000)
  return "return 'too late'"
end
started = now
local timedOut = execute()
assert(timedOut.failed == 1 and timedOut.retryRounds <= 10 and hungCalls <= 11)
assert(now - started < 131, "Retry time budget was not enforced")
assert(not files[timedOut.folder .. "/manifest.txt"]:find("[OK]", 1, true))
apis.decompile = function() return "   \n" end
local completed, canceled = 0, 0
assert(Dumper.start({
  onComplete = function()
    completed += 1
  end,
  onCanceled = function()
    canceled += 1
  end,
}))
task.defer(function()
  task.wait(0.5); Dumper.stop()
end)
drain()
assert(completed == 0 and canceled == 1 and not Dumper.isRunning())
print("Dumper retries, recovery counts, limits, timeouts, cancellation and game folder names OK")
