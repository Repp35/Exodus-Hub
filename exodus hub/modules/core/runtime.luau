-- [[ runtime ]]

-- code
local Runtime = {}
function Runtime.setup() return true end
local function contractOf(module) return type(module) == "table" and module.__contract or {} end
function Runtime.bind(loaded, MODULE_ORDER, HttpService, printRawError)
  local utils = loaded.utils; local gameInfo = loaded.gameinfo
  local remote = loaded.remote
  if
    type(gameInfo) ~= "table"
    or type(gameInfo.applySync) ~= "function"
    or type(gameInfo.installBallWatcher) ~= "function"
    or type(gameInfo.getSyncData) ~= "function"
    or type(remote) ~= "table"
    or type(gameInfo.bindBallSync) ~= "function"
    or type(gameInfo.startMaintenance) ~= "function"
    or type(gameInfo.stopMaintenance) ~= "function"
  then
    return nil, "contrato de runtime incompleto"
  end
  local ballSyncSubscribers = {}
  for _, name in ipairs(MODULE_ORDER) do
    local module = loaded[name]
    if name ~= "utils" and type(module) == "table" then
      local contract = contractOf(module)
      if contract.onBallSync == true and type(module.onBallSync) ~= "function" then return nil, "contrato BallSync incompleto: " .. name end
      if contract.onBallSync == true then
        ballSyncSubscribers[#ballSyncSubscribers + 1] = {
          name = name,
          handler = module.onBallSync,
        }
      end
    end
  end
  local syncPriority = { autospam = 1, autoparry = 2 }
  table.sort(ballSyncSubscribers, function(a, b)
    local left, right = syncPriority[a.name] or 3, syncPriority[b.name] or 3; return left == right and a.name < b.name or left < right
  end)
  local syncErrors = {}
  local function notifyBallSync(decodedData)
    if not utils.isActive() or type(decodedData) ~= "table" then return end
    for _, sub in ipairs(ballSyncSubscribers) do
      local ok, result, detail = pcall(sub.handler, decodedData)
      if not ok or result == false then
        local message = not ok and debug.traceback(tostring(result), 2) or tostring(detail or "handler retornou false"); local time = os.clock()
        if not syncErrors[sub.name] or time - syncErrors[sub.name] >= 1 then
          syncErrors[sub.name] = time; local reported, reportError = pcall(utils.recordError, sub.name .. ".onBallSync", message)
          if not reported then printRawError(sub.name, reportError) end
        end
      end
    end
  end
  local pendingSyncRefresh = false
  local function scheduleSyncRefresh()
    if pendingSyncRefresh then return end
    pendingSyncRefresh = true
    task.defer(function()
      pendingSyncRefresh = false
      if not utils.isActive() then return end
      local refreshed = gameInfo.applySync(nil)
      if type(refreshed) == "table" then notifyBallSync(refreshed) end
    end)
  end
  local function onBallSync(...)
    if not utils.isActive() then return end
    local argCount = select("#", ...)
    local data
    for index = 1, argCount do
      local value = select(index, ...)
      if typeof(value) == "buffer" then
        if type(gameInfo.decodeBallPacket) == "function" then
          local packet = gameInfo.decodeBallPacket(value)
          if type(packet) == "table" and type(packet.Sequence) == "number" then
            packet.Source = "packet"
            if gameInfo.applyPacket(packet) then notifyBallSync(packet) end
          end
        end
        scheduleSyncRefresh(); return
      end
      if type(value) == "table" then data = value; break end
      if type(value) == "string" then
        local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, value)
        if decodedOk and type(decoded) == "table" then data = decoded; break end
      end
    end
    local decodedData = gameInfo.applySync(data)
    if type(decodedData) ~= "table" then scheduleSyncRefresh(); return end
    decodedData = table.clone(decodedData); decodedData.Source = "packet"
    notifyBallSync(decodedData)
  end
  local watcherReady = gameInfo.installBallWatcher(utils.trackGlobal)
  if watcherReady ~= true then error("GameInfo.installBallWatcher falhou", 2) end
  local syncReady = gameInfo.bindBallSync(onBallSync)
  local maintenanceReady = gameInfo.startMaintenance({
    isActive = utils.isActive,
    onBallSync = onBallSync,
  })
  if maintenanceReady ~= true then error("GameInfo.startMaintenance falhou", 2) end
  local parryReady = gameInfo.getDeflectAbility() ~= nil
  return {
    parryRemote = parryReady,
    parryInitialized = parryReady,
    watcher = watcherReady == true,
    ballSync = syncReady == true,
    maintenance = maintenanceReady == true,
    ballSyncSubscribers = #ballSyncSubscribers,
  }
end
Runtime.__contract = { provides = { "setup", "bind" }, requires = {} }

return Runtime
