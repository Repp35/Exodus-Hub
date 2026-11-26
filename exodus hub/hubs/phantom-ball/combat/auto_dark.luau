-- [[ auto dark ]]
--!optimize 2

-- module
local AutoDark = {}
local utils
local remote
local gameInfo
local world
local connection
local configObserver
local epoch = 0

-- configuration
local CONFIG = {
  ENABLED_KEY = "AutoDark",
}

-- connections
local function disconnect()
  epoch += 1
  if not connection then
    return
  end
  if utils then
    utils.untrackGlobal(connection)
  end
  connection:Disconnect()
  connection = nil
end

-- synchronization
function AutoDark.sync()
  if not utils or not remote or not utils.isActive() or utils.getConfigValue(CONFIG.ENABLED_KEY) ~= true then
    disconnect()
    return true
  end
  if connection and connection.Connected ~= false then
    return true
  end
  disconnect()
  local runService = utils.getRunService()
  if not runService or not runService.Heartbeat then
    return false, "Heartbeat indisponível"
  end
  local owner = epoch
  local lastErrorAt = -math.huge
  connection = runService.Heartbeat:Connect(function()
    if owner ~= epoch then
      return
    end
    if not utils.isActive() or utils.getConfigValue(CONFIG.ENABLED_KEY) ~= true then
      disconnect()
      return
    end
    if not gameInfo.areAbilitiesEnabled() then
      return
    end
    local camera = world.CurrentCamera
    if not camera then
      return
    end
    local ok, reason = pcall(remote.fireDark, gameInfo.getDarkSealEventId(), camera.CFrame)
    if owner ~= epoch then
      return
    end
    if not ok and os.clock() - lastErrorAt >= 1 then
      lastErrorAt = os.clock()
      warn("[AutoDark] " .. tostring(reason))
    end
  end)
  utils.trackGlobal(connection)
  return true
end

-- setup
function AutoDark.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" or type(deps.Remote) ~= "table" or type(deps.GameInfo) ~= "table" then
    return false, "dependências ausentes: Utils, GameInfo ou Remote"
  end
  AutoDark.teardown()
  utils, remote, gameInfo = deps.Utils, deps.Remote, deps.GameInfo
  configObserver = utils.observeConfig(function(changes)
    if changes.AutoDark ~= nil then
      AutoDark.sync()
    end
  end)
  utils.trackGlobal(configObserver)
  world = utils.getWorkspace()
  return AutoDark.sync()
end
function AutoDark.teardown()
  if configObserver then
    if utils then
      utils.untrackGlobal(configObserver)
    end
    configObserver:Disconnect()
    configObserver = nil
  end
  disconnect()
  utils, remote, gameInfo, world = nil, nil, nil, nil
end

-- contract
AutoDark.__contract = {
  requires = { Utils = "utils", Remote = "remote", GameInfo = "gameinfo" },
  requiresMethods = {
    Utils = { "getConfigValue", "getWorkspace", "getRunService", "trackGlobal", "untrackGlobal", "isActive", "observeConfig" },
    Remote = { "fireDark" },
    GameInfo = { "getDarkSealEventId", "areAbilitiesEnabled" },
  },
  provides = { "setup", "sync", "teardown" },
}

return AutoDark
