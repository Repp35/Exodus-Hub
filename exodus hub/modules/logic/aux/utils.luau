-- [[ utils ]]

-- module
local Utils = {}
local players = game:GetService("Players")
local replicated = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local http = game:GetService("HttpService")
local state = {
  active = false,
  config = {},
  urls = {},
  globalConnections = {},
  characterConnections = {},
  manualSpam = false,
  autoSpam = false,
  lifecycle = {
    phase = "stopped",
    generation = 0,
    startedAt = 0,
    stoppedAt = 0,
  },
  diagnostics = { errors = {}, transitions = {}, lastTransitionAt = 0 },
}

local configModule, modules, persistenceReady = nil, {}, false
local connectionIndexes = { global = {}, character = {} }
local observerIndexes = { spam = {}, config = {} }
local savePending, saveToken, saveDirty, saveRevision = false, 0, false, 0
local refreshPending, refreshing = false, false
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
local function copy(value, visited)
  if type(value) ~= "table" then return value end
  visited = visited or {}
  if visited[value] then return visited[value] end
  local result = {}; visited[value] = result
  for key, item in pairs(value) do
    result[copy(key, visited)] = copy(item, visited)
  end
  return result
end
local function snapshot(value) return type(value) == "table" and copy(value) or {} end
local function append(list, value)
  list[#list + 1] = value
  if #list > CONFIG.HISTORY_LIMIT then table.remove(list, 1) end
end
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
local function diagnosticsSnapshot()
  local statuses = {}; local names = {}
  for name in pairs(modules) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local module = modules[name]
    if type(module) == "table" and type(module.getStatus) == "function" then
      local ok, status = pcall(module.getStatus)
      if ok and type(status) == "table" then statuses[name] = snapshot(status) end
    end
  end
  local diagnostics = state.diagnostics
  return {
    schema = CONFIG.API_VERSION,
    generatedAt = os.clock(),
    lastError = snapshot(diagnostics.lastError),
    lastTransition = snapshot(diagnostics.lastTransition),
    lastTransitionAt = diagnostics.lastTransitionAt,
    errors = snapshot(diagnostics.errors),
    transitions = snapshot(diagnostics.transitions),
    lifecycle = lifecycleSnapshot(),
    runtime = {
      active = state.active,
      manualSpamActive = state.manualSpam,
      autoSpamActive = state.autoSpam,
    },
    modules = statuses,
  }
end

-- environment
local function refreshNamespace()
  if refreshing then return end
  refreshing = true; local namespace = type(_G.Exodus) == "table" and _G.Exodus or {}
  namespace.Name, namespace.InternalName, namespace.Version, namespace.ApiVersion, namespace.Author =
    CONFIG.NAME, "Exodus", CONFIG.VERSION, CONFIG.API_VERSION, CONFIG.AUTHOR
  namespace.State, namespace.Config, namespace.ModuleURLs, namespace.Diagnostics =
    stateSnapshot(), snapshot(state.config), snapshot(state.urls), diagnosticsSnapshot()
  _G.Exodus = namespace; refreshing = false
end

-- diagnostics
local function recordTransition(source, fromState, toState, reason)
  local item = {
    source = tostring(source or "Unknown"),
    from = tostring(fromState or ""),
    to = tostring(toState or ""),
    reason = tostring(reason or ""),
    at = os.clock(),
  }

  state.diagnostics.lastTransition, state.diagnostics.lastTransitionAt = item, item.at; append(state.diagnostics.transitions, item)
  if state.active and not refreshPending then
    refreshPending = true; local generation = state.lifecycle.generation
    task.delay(0.1, function()
      refreshPending = false
      if state.active and state.lifecycle.generation == generation then refreshNamespace() end
    end)
  end
end

-- persistence
function Utils.ensureDataFolder()
  if type(makefolder) ~= "function" then error("API externa ausente: makefolder", 2) end
  if type(isfolder) ~= "function" then error("API externa ausente: isfolder", 2) end
  if not isfolder(CONFIG.FOLDER) then makefolder(CONFIG.FOLDER) end
  return true, CONFIG.FOLDER
end
local function isPersistentConfigKey(key) return type(key) == "string" and key:sub(1, #CONFIG.SESSION_ONLY_PREFIX) ~= CONFIG.SESSION_ONLY_PREFIX end
local function serializeConfig(config)
  local data = {}
  for key, value in pairs(config) do
    if isPersistentConfigKey(key) then
      if typeof(value) == "EnumItem" then data[key] = value.EnumType == Enum.KeyCode and { keyCode = value.Name } or { mouseButton = value.Name } else data[key] = value end
    end
  end
  return http:JSONEncode(data)
end
local function persistenceAvailable()
  return type(isfile) == "function"
    and type(readfile) == "function"
    and type(writefile) == "function"
    and type(isfolder) == "function"
    and type(makefolder) == "function"
end
local function decodeKeyCode(value)
  if type(value) == "table" and type(value.mouseButton) == "string" then
    local buttons = {
      MouseButton1 = Enum.UserInputType.MouseButton1,
      MouseButton2 = Enum.UserInputType.MouseButton2,
      MouseButton3 = Enum.UserInputType.MouseButton3,
    }

    return buttons[value.mouseButton]
  end
  if type(value) ~= "table" or type(value.keyCode) ~= "string" then return value end
  local name = value.keyCode
  local ok, keyCode = pcall(function() return Enum.KeyCode[name] end)
  if ok and keyCode then return keyCode end
  warn("Config ignorada: KeyCode inválido " .. tostring(name)); return nil
end
local function migrateConfig(data)
  local migrated = data.AutoClash ~= nil or data.AutoClashActivationMs ~= nil or data.AutoClashDeactivationMs ~= nil
  if data.AutoSpam == nil and type(data.AutoClash) == "boolean" then data.AutoSpam, migrated = data.AutoClash, true end
  if data.AutoParryFactor08Applied ~= true then data.AutoParryWindowFactor, data.AutoParryFactor08Applied, migrated = 0.25, true, true
  elseif tonumber(data.AutoParryWindowFactor) == 0.8 then data.AutoParryWindowFactor, migrated = 0.25, true end
  if data.AutoParryFactor03Applied ~= true then
    if tonumber(data.AutoParryWindowFactor) == 0.25 then data.AutoParryWindowFactor = 0.3 end
    data.AutoParryFactor03Applied, migrated = true, true
  end
  if data.ClickMethod == "Game" then data.ClickMethod, migrated = "Deflect", true end
  local patch = {}
  for key, value in pairs(data) do
    if not isPersistentConfigKey(key) then
      migrated = true
    elseif key ~= "AutoClash" and key ~= "AutoClashActivationMs" and key ~= "AutoClashDeactivationMs" then
      value = decodeKeyCode(value)
      if value ~= nil then
        local valid, reason = configModule.validatePatch({ [key] = value })
        if valid then patch[key] = value else warn("Config ignorada: " .. tostring(reason)) end
      end
    end
  end
  return patch, migrated
end
local function readSavedConfig(path)
  local checked, exists = pcall(isfile, path)
  if not checked then return nil, nil, "inaccessible" end
  if not exists then return nil, nil, "missing" end
  local readOk, raw = pcall(readfile, path)
  if not readOk or type(raw) ~= "string" then return nil, nil, "inaccessible" end
  local decoded, data = pcall(function() return http:JSONDecode(raw) end)
  if not decoded or type(data) ~= "table" or next(data) == nil then return nil, nil, "invalid" end
  return raw, data, "valid"
end
local function writeVerified(path, body)
  local ok = pcall(writefile, path, body)
  if not ok then return false end
  local raw = readSavedConfig(path); return raw == body
end
local function backupPath(folder, index) return folder .. "/config_backup_" .. index .. ".json" end
local function backupAtStartup(folder, body)
  for index = 5, 2, -1 do
    local old = readSavedConfig(backupPath(folder, index - 1))
    if old and not writeVerified(backupPath(folder, index), old) then return false end
  end
  return writeVerified(backupPath(folder, 1), body)
end
local function writeConfig()
  if not persistenceReady or not saveDirty then return end
  local revision = saveRevision; local _, folder = Utils.ensureDataFolder()
  local path = folder .. "/config.json"; local body = serializeConfig(state.config)
  local decoded, data = pcall(function() return http:JSONDecode(body) end)
  if not decoded or type(data) ~= "table" or next(data) == nil then warn("Configuração vazia ou inválida; arquivo anterior preservado"); return end
  local previous, _, status = readSavedConfig(path)
  if status == "inaccessible" then warn("Configuração inacessível; salvamento suspenso"); return end
  if status == "invalid" then warn("Configuração inválida; salvamento suspenso para evitar perda"); return end
  if previous and not writeVerified(folder .. "/config_recovery.json", previous) then warn("Falha ao proteger configuração anterior; salvamento suspenso"); return end
  if not previous then
    local recovery, _, recoveryStatus = readSavedConfig(folder .. "/config_recovery.json")
    if not recovery and recoveryStatus ~= "missing" then warn("Backup de recuperação inacessível ou inválido; salvamento suspenso"); return end
    if not recovery and not writeVerified(folder .. "/config_recovery.json", body) then warn("Falha ao criar proteção inicial; salvamento suspenso"); return end
  end
  if not writeVerified(path, body) then warn("Falha ao salvar configuração; cópia anterior preservada"); return end
  if saveRevision == revision then saveDirty = false end
end
local saveRunning = false
local queueSave
local function saveConfig()
  if saveRunning then return end
  saveRunning = true; local revision = saveRevision
  local ok, reason = pcall(writeConfig); saveRunning = false
  if not ok then warn("Falha ao salvar configuração: " .. tostring(reason)) end
  if saveDirty and saveRevision ~= revision and persistenceReady then queueSave() end
end
queueSave = function()
  if not persistenceReady then return end
  saveDirty = true; saveRevision += 1
  if savePending then return end
  savePending = true; saveToken += 1
  local token = saveToken
  task.delay(0.25, function()
    if token ~= saveToken then return end
    savePending = false; saveConfig()
  end)
end
local function flushSave()
  saveToken += 1; savePending = false
  saveConfig()
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
  state.lifecycle.generation += 1; state.active, state.manualSpam, state.autoSpam = false, false, false
  local notified, notifyError = pcall(notify, spamObservers)
  if not notified then warn("Failed to notify observers: " .. tostring(notifyError)) end
  local saved, saveError = pcall(flushSave)
  if not saved then warn("Failed to save configuration: " .. tostring(saveError)) end
  state.lifecycle.stoppedAt = os.clock()
  _G.ExodusOnBurst = function() end
  if type(_G.ExodusUICleanup) == "function" then
    local cleaned, cleanupError = pcall(_G.ExodusUICleanup)
    if not cleaned then warn("Falha ao limpar interface: " .. tostring(cleanupError)) end
  end
  disconnectAll(state.characterConnections, connectionIndexes.character); disconnectAll(state.globalConnections, connectionIndexes.global)
  state.config, state.urls, modules = {}, {}, {}; persistenceReady, saveDirty = false, false
  disconnectAll(spamObservers, observerIndexes.spam); disconnectAll(configObservers, observerIndexes.config)
  if type(_G.Exodus) == "table" then
    local exodus = _G.Exodus; exodus.Started, exodus.UIReady, exodus.Runtime, exodus.UI = false, false, nil, nil
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
function Utils.recordError(source, message)
  source, message = tostring(source or "Unknown"), tostring(message or "")
  local previous = state.diagnostics.lastError
  if previous and previous.source == source and previous.message == message and os.clock() - previous.at < 1 then previous.count = (previous.count or 1) + 1; return true end
  local item = { source = tostring(source or "Unknown"), message = tostring(message or ""), at = os.clock() }; state.diagnostics.lastError = item
  append(state.diagnostics.errors, item); warn(("[%s] %s"):format(item.source, item.message))
  refreshNamespace(); return true
end
function Utils.isManualSpamActive() return state.manualSpam end
function Utils.isAutoSpamActive() return state.autoSpam end
function Utils.isSpamActive() return state.manualSpam or state.autoSpam end
local function setSpam(key, value, source, reason)
  value = value == true
  if state[key] == value then return false end
  local previous = state[key]; state[key] = value
  notify(spamObservers); recordTransition(source, previous and "active" or "inactive", value and "active" or "inactive", reason)
  return true
end
function Utils.setManualSpamActive(value) return setSpam("manualSpam", value, "Spam", "manual_toggle") end
function Utils.setAutoSpamActive(value) return setSpam("autoSpam", value, "AutoSpam", "automatic_toggle") end
function Utils.stopAllSpam()
  local changed = state.manualSpam or state.autoSpam; state.manualSpam, state.autoSpam = false, false
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
      if isPersistentConfigKey(key) then persistentChanged = true end
    end
  end
  if next(changes) == nil then return true end
  notify(configObservers, changes)
  if changes.SpamRateMode ~= nil or changes.CPS ~= nil or changes.CPF ~= nil or changes.MS ~= nil then notify(spamObservers) end
  refreshNamespace()
  if persistentChanged then queueSave() end
  return true
end
function Utils.resetConfig()
  if not configModule or type(configModule.defaults) ~= "function" then error("Config defaults indisponíveis", 2) end
  local defaults = configModule.defaults(); local normalized, reason = configModule.normalizePatch(defaults)
  if type(normalized) ~= "table" then error("Config defaults inválidos: " .. tostring(reason), 2) end
  state.config = normalized; notify(configObservers, snapshot(normalized))
  notify(spamObservers); refreshNamespace()
  queueSave(); flushSave()
  return true
end
function Utils.loadConfig()
  if not persistenceAvailable() then warn("Persistência indisponível; usando configuração da sessão"); return true end
  local ok, folder = pcall(function()
    local _, path = Utils.ensureDataFolder(); return path
  end)
  if not ok then warn("Persistência indisponível: " .. tostring(folder)); return true end
  local path = folder .. "/config.json"; local raw, data, status = readSavedConfig(path)
  local recovered, anyStored = false, status ~= "missing"
  if not raw then
    for index = 0, 5 do
      local backup = index == 0 and (folder .. "/config_recovery.json") or backupPath(folder, index); local saved, value, backupStatus = readSavedConfig(backup)
      if backupStatus ~= "missing" then anyStored = true end
      if saved then raw, data, recovered = saved, value, true; break end
    end
  end
  if not raw then
    if anyStored then warn("Nenhuma configuração válida pôde ser recuperada; salvamento suspenso para preservar os arquivos"); return true end
    persistenceReady = true; return true
  end
  if recovered then
    if status == "inaccessible" then
      warn("Configuração recuperada em memória; arquivo principal inacessível, salvamento suspenso"); local patch = migrateConfig(data)
      Utils.setConfig(patch); return true
    end
    if not writeVerified(path, raw) then
      warn("Configuração recuperada em memória; falha ao restaurar arquivo, salvamento suspenso"); local patch = migrateConfig(data)
      Utils.setConfig(patch); return true
    end
    warn("Configuração restaurada de um backup")
  end
  if not backupAtStartup(folder, raw) then
    warn("Falha ao criar backup de entrada; salvamento suspenso"); local patch = migrateConfig(data)
    Utils.setConfig(patch); return true
  end
  if not writeVerified(folder .. "/config_recovery.json", raw) then
    warn("Falha ao preparar recuperação; salvamento suspenso"); local patch = migrateConfig(data)
    Utils.setConfig(patch); return true
  end
  local patch, migrated = migrateConfig(data); Utils.setConfig(patch)
  persistenceReady = true
  if migrated then queueSave() end
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
  requires = {},
  provides = {
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
