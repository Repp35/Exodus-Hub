-- [[ utils ]]

-- module
local Utils = {}
local players = game:GetService("Players")
local replicated = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local state
local stateModule
local persistence
local diagnostics
local refreshNamespace
local configModule, modules = nil, {}
local connectionIndexes = { global = {}, character = {} }
local observerIndexes = { spam = {}, config = {} }
local spamObservers, configObservers = {}, {}

-- configuration
local CONFIG = {
  API_VERSION = 1,
  VERSION = "3.3.0",
  NAME = "Exodus Hub",
  AUTHOR = "deltapolinha_2915",
  FOLDER = "Exodus Hub",
  HISTORY_LIMIT = 32,
  SESSION_ONLY_PREFIX = "Universal",
}

-- helpers
local function snapshot(value) return type(value) == "table" and stateModule.copy(value) or {} end
local function setValues(target, source)
  for key, value in pairs(source or {}) do
    target[key] = value
  end
end

-- observers
local function connectObserver(list, indexMap, observer)
  if type(observer) ~= "function" then error("Observer precisa ser uma função", 2) end
  local connection = { Connected = true, callback = observer }; list[#list + 1] = connection
  indexMap[connection] = #list
  function connection:Disconnect()
    if not self.Connected then return end
    self.Connected = false; local index = indexMap[self]
    if not index then return end
    local lastIndex = #list; local last = list[lastIndex]
    list[index] = last; list[lastIndex] = nil
    indexMap[self] = nil
    if last and last ~= self then indexMap[last] = index end
  end
  return connection
end
local function notify(list, value)
  if #list == 0 then return end
  for _, observer in ipairs(table.clone(list)) do
    if observer.Connected then
      local ok, err = pcall(observer.callback, value)
      if not ok and type(warn) == "function" then warn("Falha ao notificar observador: " .. tostring(err)) end
    end
  end
end
function Utils.observeSpam(observer) return connectObserver(spamObservers, observerIndexes.spam, observer) end
function Utils.observeConfig(observer) return connectObserver(configObservers, observerIndexes.config, observer) end
local function track(list, indexMap, connection)
  if not connection or type(connection.Disconnect) ~= "function" then error("Conexão inválida", 2) end
  if not indexMap[connection] then list[#list + 1] = connection; indexMap[connection] = #list end
  return connection
end
local function untrack(list, indexMap, connection)
  local index = indexMap[connection]
  if not index then return false end
  local lastIndex = #list; local last = list[lastIndex]
  list[index] = last; list[lastIndex] = nil
  indexMap[connection] = nil
  if last and last ~= connection then indexMap[last] = index end
  return true
end
local function disconnectAll(list, indexMap)
  while #list > 0 do
    local connection = list[#list]; untrack(list, indexMap, connection)
    local ok, err = pcall(connection.Disconnect, connection)
    if not ok and type(warn) == "function" then warn("Falha ao desconectar: " .. tostring(err)) end
  end
end

-- snapshots
local function lifecycleSnapshot()
  local result = snapshot(state.lifecycle); result.schema, result.generatedAt = CONFIG.API_VERSION, os.clock()
  return result
end
local function stateSnapshot()
  return {
    schema = CONFIG.API_VERSION,
    generatedAt = os.clock(),
    active = state.active,
    manualSpamActive = state.manualSpam,
    autoSpamActive = state.autoSpam,
    lifecycle = snapshot(state.lifecycle),
    config = snapshot(state.config),
    moduleURLs = snapshot(state.urls),
    connectionCounts = {
      global = #state.globalConnections,
      character = #state.characterConnections,
    },
  }
end
local function diagnosticsSnapshot() return diagnostics.snapshot() end

-- environment
refreshNamespace = function()
  if not state then return end
  local namespace = type(_G.Exodus) == "table" and _G.Exodus or {}
  namespace.Name, namespace.InternalName, namespace.Version, namespace.ApiVersion, namespace.Author =
    CONFIG.NAME, "Exodus", CONFIG.VERSION, CONFIG.API_VERSION, CONFIG.AUTHOR
  namespace.State, namespace.Config, namespace.ModuleURLs, namespace.Diagnostics =
    stateSnapshot(), snapshot(state.config), snapshot(state.urls), diagnostics.snapshot(false)
  _G.Exodus = namespace
end
local function recordTransition(...) return diagnostics.recordTransition(...) end
function Utils.ensureDataFolder() return persistence.ensureDataFolder() end
function Utils.loadConfig() return persistence.load() end
function Utils.configure(deps)
  stateModule = deps.State; state = stateModule.create()
  diagnostics = deps.Diagnostics.create({
    state = state,
    config = CONFIG,
    snapshot = snapshot,
    lifecycleSnapshot = lifecycleSnapshot,
    getModules = function() return modules end,
    refresh = function() refreshNamespace() end,
  })
  persistence = deps.Persistence.create({ state = state, config = CONFIG, getConfigModule = function() return configModule end, setConfig = Utils.setConfig })
  return true
end

-- lifecycle
function Utils.start()
  local previous = state.lifecycle.phase; state.active = true
  state.lifecycle.generation += 1; state.lifecycle.startedAt, state.lifecycle.stoppedAt, state.lifecycle.phase = os.clock(), 0, "starting"
  recordTransition("Utils", previous, "starting", "start")
  if _G.ExodusOnBurst == nil then
    _G.ExodusOnBurst = function() end
  end
  refreshNamespace(); return stateSnapshot()
end
function Utils.stop()
  local previous = state.lifecycle.phase; local wasActive = state.active
  local shutdownReason = _G.ExodusShutdownReason; local stopUpdateChannel = _G.ExodusUpdateStop
  if type(_G.ExodusUIFadeOut) == "function" then
    local ok, err = pcall(_G.ExodusUIFadeOut, shutdownReason == "update" or shutdownReason == "reload")
    if not ok then warn("Falha ao animar fechamento: " .. tostring(err)) end
  end
  _G.ExodusUpdateStop = nil
  if type(stopUpdateChannel) == "function" then pcall(stopUpdateChannel) end
  state.lifecycle.generation += 1; state.active, state.manualSpam, state.autoSpam, state.dynamicSpam = false, false, false, false
  local notified, notifyError = pcall(notify, spamObservers)
  if not notified then warn("Failed to notify observers: " .. tostring(notifyError)) end
  local saved, saveError = pcall(persistence.stop)
  if not saved then warn("Failed to save configuration: " .. tostring(saveError)) end
  state.lifecycle.stoppedAt = os.clock()
  _G.ExodusOnBurst = function() end
  if type(_G.ExodusUICleanup) == "function" then
    local cleaned, cleanupError = pcall(_G.ExodusUICleanup)
    if not cleaned then warn("Falha ao limpar interface: " .. tostring(cleanupError)) end
  end
  disconnectAll(state.characterConnections, connectionIndexes.character); disconnectAll(state.globalConnections, connectionIndexes.global)
  state.config, state.urls, modules = {}, {}, {}; disconnectAll(spamObservers, observerIndexes.spam)
  disconnectAll(configObservers, observerIndexes.config)
  if type(_G.Exodus) == "table" then
    local exodus = _G.Exodus; exodus.Started, exodus.UIReady, exodus.Runtime, exodus.UI, exodus.Context = false, false, nil, nil, nil
    if type(exodus.RemoteHooks) == "table" then exodus.RemoteHooks.register = nil end
    if type(exodus.AutoParryHitbox) == "table" then
      local hitbox = exodus.AutoParryHitbox
      if hitbox.connection then hitbox.connection:Disconnect() end
      hitbox.connection, hitbox.handler = nil, nil
    end
  end
  state.lifecycle.phase = "stopped"; recordTransition("Utils", previous, "stopped", "stop")
  if wasActive and shutdownReason ~= "update" and shutdownReason ~= "restart" and type(print) == "function" then print("[Exodus] Closed.") end
  refreshNamespace(); return true
end

-- state-api
function Utils.isActive() return state.active end
function Utils.getStateSnapshot() return stateSnapshot() end
function Utils.getConfig() return snapshot(state.config) end
function Utils.getConfigValue(key) return state.config[key] end
function Utils.getConfigSnapshot() return snapshot(state.config) end
function Utils.getModuleURLsSnapshot() return snapshot(state.urls) end
function Utils.getLifecycle() return lifecycleSnapshot() end
function Utils.getDiagnostics() return diagnosticsSnapshot() end
function Utils.setDiagnosticsModules(value)
  if type(value) ~= "table" then error("Módulos de diagnóstico inválidos", 2) end
  modules = table.clone(value); refreshNamespace()
  return true
end
function Utils.setLifecyclePhase(value)
  if type(value) ~= "string" or value == "" then return false end
  local previous = state.lifecycle.phase
  if previous ~= value then state.lifecycle.phase = value; recordTransition("Lifecycle", previous, value, "phase_change") end
  return true
end
function Utils.recordTransition(source, fromState, toState, reason) recordTransition(source, fromState, toState, reason) end
function Utils.recordError(source, message) return diagnostics.recordError(source, message) end
function Utils.isManualSpamActive() return state.manualSpam end
function Utils.isAutoSpamActive() return state.autoSpam end
function Utils.isDynamicSpamActive() return state.dynamicSpam end
function Utils.isSpamActive() return state.manualSpam or state.autoSpam or state.dynamicSpam end
local function setSpam(key, value, source, reason)
  value = value == true
  if state[key] == value then return false end
  local previous = state[key]; state[key] = value
  notify(spamObservers); recordTransition(source, previous and "active" or "inactive", value and "active" or "inactive", reason)
  return true
end
function Utils.setManualSpamActive(value) return setSpam("manualSpam", value, "Spam", "manual_toggle") end
function Utils.setDynamicSpamActive(value) return setSpam("dynamicSpam", value, "DynamicParry", "manual_gesture") end
function Utils.setAutoSpamActive(value) return setSpam("autoSpam", value, "AutoSpam", "automatic_toggle") end
function Utils.stopAllSpam()
  local changed = state.manualSpam or state.autoSpam or state.dynamicSpam; state.manualSpam, state.autoSpam, state.dynamicSpam = false, false, false
  if changed then notify(spamObservers) end
  return true
end
function Utils.isFiniteNumber(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
function Utils.isNonNegativeFiniteNumber(value) return Utils.isFiniteNumber(value) and value >= 0 end

-- configuration-api
function Utils.normalizeSpamRate(value, fallback)
  local rate = tonumber(value)
  if not Utils.isFiniteNumber(rate) then rate = tonumber(fallback) end
  if not Utils.isFiniteNumber(rate) then rate = 0 end
  return math.max(rate, 0)
end

-- public-api
function Utils.setConfig(patch)
  if type(patch) ~= "table" then error("Config patch inválido: esperado table", 2) end
  local normalized
  if configModule then
    local result, reason = configModule.normalizePatch(patch)
    if type(result) ~= "table" then error("Config inválida: " .. tostring(reason), 2) end
    normalized = result
  else
    normalized = snapshot(patch)
  end
  local changes, persistentChanged = {}, false
  for key, value in pairs(normalized) do
    if state.config[key] ~= value then
      state.config[key], changes[key] = value, value
      if persistence.isPersistentKey(key) then persistentChanged = true end
    end
  end
  if next(changes) == nil then return true end
  notify(configObservers, changes)
  if changes.SpamRateMode ~= nil or changes.CPS ~= nil or changes.CPF ~= nil or changes.MS ~= nil then notify(spamObservers) end
  refreshNamespace()
  if persistentChanged then persistence.queue() end
  return true
end
function Utils.resetConfig()
  if not configModule or type(configModule.defaults) ~= "function" then error("Config defaults indisponíveis", 2) end
  local defaults = configModule.defaults(); local normalized, reason = configModule.normalizePatch(defaults)
  if type(normalized) ~= "table" then error("Config defaults inválidos: " .. tostring(reason), 2) end
  state.config = normalized; notify(configObservers, snapshot(normalized))
  notify(spamObservers); refreshNamespace()
  persistence.queue(); persistence.flush()
  return true
end
function Utils.setConfigModule(module)
  if
    type(module) ~= "table"
    or type(module.normalizePatch) ~= "function"
    or type(module.validate) ~= "function"
    or type(module.validatePatch) ~= "function"
    or type(module.defaults) ~= "function"
  then
    error("API interna ausente: Config.normalizePatch/validate/validatePatch/defaults", 2)
  end
  configModule = module; return true
end
function Utils.setModuleURLs(urls)
  if type(urls) ~= "table" then error("URLs de módulos inválidas", 2) end
  setValues(state.urls, urls); refreshNamespace()
  return true
end
function Utils.trackGlobal(connection) return track(state.globalConnections, connectionIndexes.global, connection) end
function Utils.untrackGlobal(connection) return untrack(state.globalConnections, connectionIndexes.global, connection) end
function Utils.trackCharacter(connection) return track(state.characterConnections, connectionIndexes.character, connection) end
function Utils.untrackCharacter(connection) return untrack(state.characterConnections, connectionIndexes.character, connection) end
function Utils.disconnectCharacterConnections() disconnectAll(state.characterConnections, connectionIndexes.character) end
function Utils.getPlayers() return players end
function Utils.getReplicatedStorage() return replicated end
function Utils.getRunService() return runService end
function Utils.getWorkspace() return workspace end
function Utils.getLocalPlayer() return players.LocalPlayer end
function Utils.now() return os.clock() end
function Utils.name() return CONFIG.NAME end
function Utils.version() return CONFIG.VERSION end
function Utils.apiVersion() return CONFIG.API_VERSION end
function Utils.author() return CONFIG.AUTHOR end
_G.ExodusStop = Utils.stop

-- contract
Utils.__contract = {
  requires = {
    State = "state",
    Persistence = "persistence",
    Diagnostics = "diagnostics",
  },
  requiresMethods = {
    State = { "create", "copy" },
    Persistence = { "create" },
    Diagnostics = { "create" },
  },
  provides = {
    "configure",
    "start",
    "stop",
    "ensureDataFolder",
    "loadConfig",
    "getDiagnostics",
    "getLifecycle",
    "isFiniteNumber",
    "isNonNegativeFiniteNumber",
    "isActive",
    "getConfig",
    "getConfigValue",
    "setConfig",
    "resetConfig",
    "setConfigModule",
    "setModuleURLs",
    "setDiagnosticsModules",
    "setLifecyclePhase",
    "getStateSnapshot",
    "getConfigSnapshot",
    "getModuleURLsSnapshot",
    "getPlayers",
    "getLocalPlayer",
    "getRunService",
    "getReplicatedStorage",
    "getWorkspace",
    "now",
    "apiVersion",
    "name",
    "author",
    "version",
    "trackGlobal",
    "untrackGlobal",
    "trackCharacter",
    "untrackCharacter",
    "disconnectCharacterConnections",
    "recordError",
    "recordTransition",
    "isSpamActive",
    "isDynamicSpamActive",
    "setDynamicSpamActive",
    "isManualSpamActive",
    "isAutoSpamActive",
    "setManualSpamActive",
    "setAutoSpamActive",
    "stopAllSpam",
    "observeConfig",
    "observeSpam",
    "normalizeSpamRate",
  },
}

return Utils
