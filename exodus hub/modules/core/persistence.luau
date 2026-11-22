-- [[ configuration persistence and recovery ]]

-- code
local Persistence = {}
function Persistence.setup() return true end
function Persistence.create(deps)
  local store = {}; local state, CONFIG, http = deps.state, deps.config, game:GetService("HttpService")
  local savePending, saveToken, saveDirty, saveRevision, persistenceReady = false, 0, false, 0, false
  function store.ensureDataFolder()
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
    for _, key in ipairs({ "ClashMaxDistance", "AutoSpamClashPrediction", "AutoSpamPredictionMargin", "ClashGrace", "ClashMaxAge" }) do
      if data[key] ~= nil then data[key], migrated = nil, true end
    end
    local patch = {}
    for key, value in pairs(data) do
      if not isPersistentConfigKey(key) then
        migrated = true
      elseif key ~= "AutoClash" and key ~= "AutoClashActivationMs" and key ~= "AutoClashDeactivationMs" then
        value = decodeKeyCode(value)
        if value ~= nil then
          local valid, reason = deps.getConfigModule().validatePatch({ [key] = value })
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
    local revision = saveRevision; local _, folder = store.ensureDataFolder()
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
  function store.load()
    if not persistenceAvailable() then warn("Persistência indisponível; usando configuração da sessão"); return true end
    local ok, folder = pcall(function()
      local _, path = store.ensureDataFolder(); return path
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
        deps.setConfig(patch); return true
      end
      if not writeVerified(path, raw) then
        warn("Configuração recuperada em memória; falha ao restaurar arquivo, salvamento suspenso"); local patch = migrateConfig(data)
        deps.setConfig(patch); return true
      end
      warn("Configuração restaurada de um backup")
    end
    if not backupAtStartup(folder, raw) then
      warn("Falha ao criar backup de entrada; salvamento suspenso"); local patch = migrateConfig(data)
      deps.setConfig(patch); return true
    end
    if not writeVerified(folder .. "/config_recovery.json", raw) then
      warn("Falha ao preparar recuperação; salvamento suspenso"); local patch = migrateConfig(data)
      deps.setConfig(patch); return true
    end
    local patch, migrated = migrateConfig(data); deps.setConfig(patch)
    persistenceReady = true
    if migrated then queueSave() end
    return true
  end
  store.isPersistentKey = isPersistentConfigKey; store.queue = queueSave
  store.flush = flushSave
  function store.stop()
    flushSave(); persistenceReady, saveDirty = false, false
    saveToken += 1; savePending = false
  end
  return store
end
Persistence.__contract = { requires = {}, provides = { "setup", "create" } }

return Persistence
