-- [[ runtime ]]
--!optimize 2

-- code
local Runtime = {}
local assistScope
function Runtime.setup() return true end
local function contractOf(module) return type(module) == "table" and module.__contract or {} end
function Runtime.bind(loaded, MODULE_ORDER, HttpService, printRawError)
  if assistScope then
    assistScope.destroy()
  end
  assistScope = loaded.lifetime.scope()
  local player, utils = loaded.utils.getLocalPlayer(), loaded.utils
  local characterScope
  local function watch(character)
    if characterScope then
      characterScope.destroy()
    end
    characterScope = assistScope.child()
    local humanoids = {}
    local function bind(humanoid)
      if not humanoid:IsA("Humanoid") or humanoids[humanoid] then
        return
      end
      humanoids[humanoid] = true
      characterScope.connect(humanoid.Died, function()
        if
          player.Character == character
          and utils.isActive()
          and utils.getConfigValue("ParryOnDeath") == true
          and utils.getConfigValue("AutoParry") ~= true
        then
          utils.setConfig({ AutoParry = true })
        end
      end)
    end
    characterScope.connect(character.ChildAdded, bind)
    for _, child in ipairs(character:GetChildren()) do
      bind(child)
    end
  end
  assistScope.connect(player.CharacterAdded, watch)
  assistScope.connect(player.CharacterRemoving, function()
    if characterScope then
      characterScope.destroy()
      characterScope = nil
    end
  end)
  if player.Character then
    watch(player.Character)
  end
  local utils = loaded.utils
  local gameInfo = loaded.gameinfo
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
      if contract.onBallSync == true and type(module.onBallSync) ~= "function" then
        return nil, "contrato BallSync incompleto: " .. name
      end
      if contract.onBallSync == true then
        ballSyncSubscribers[#ballSyncSubscribers + 1] = {
          name = name,
          handler = module.onBallSync,
        }
      end
    end
  end
  local syncPriority = { combatloop = 1 }
  table.sort(ballSyncSubscribers, function(a, b)
    local left, right = syncPriority[a.name] or 3, syncPriority[b.name] or 3
    return left == right and a.name < b.name or left < right
  end)
  local syncErrors = {}
  local function dispatchBallSync(decodedData)
    if not utils.isActive() or type(decodedData) ~= "table" then
      return
    end
    for _, sub in ipairs(ballSyncSubscribers) do
      local ok, result, detail = pcall(sub.handler, decodedData)
      if not ok or result == false then
        local message = not ok and debug.traceback(tostring(result), 2) or tostring(detail or "handler retornou false")
        local time = os.clock()
        if not syncErrors[sub.name] or time - syncErrors[sub.name] >= 1 then
          syncErrors[sub.name] = time
          local reported, reportError = pcall(utils.recordError, sub.name .. ".onBallSync", message)
          if not reported then
            printRawError(sub.name, reportError)
          end
        end
      end
    end
  end
  local pendingAttributeRefresh = false
  local function notifyBallSync(data)
    if type(data) ~= "table" then
      return
    end
    if data.Source == "clash" or (data.Source == "target" and data.TargetPlayerID == nil) then
      if pendingAttributeRefresh then
        return
      end
      pendingAttributeRefresh = true
      task.defer(function()
        pendingAttributeRefresh = false
        if utils.isActive() then
          dispatchBallSync({ Source = "clash" })
        end
      end)
    else
      dispatchBallSync(data)
    end
  end
  local pendingSyncRefresh = false
  local function scheduleSyncRefresh()
    if pendingSyncRefresh then
      return
    end
    pendingSyncRefresh = true
    task.defer(function()
      pendingSyncRefresh = false
      if not utils.isActive() then
        return
      end
      local refreshed = gameInfo.applySync(nil)
      if type(refreshed) == "table" then
        refreshed = table.clone(refreshed)
        refreshed.Source = "replicator"
        notifyBallSync(refreshed)
      end
    end)
  end
  local function onBallSync(...)
    if not utils.isActive() then
      return
    end
    local argCount = select("#", ...)
    local data
    for index = 1, argCount do
      local value = select(index, ...)
      if typeof(value) == "buffer" then
        if type(gameInfo.decodeBallPacket) == "function" then
          local packet = gameInfo.decodeBallPacket(value)
          if type(packet) == "table" and type(packet.Sequence) == "number" then
            packet.Source = "packet"
            if gameInfo.applyPacket(packet) then
              notifyBallSync(packet)
            end
          end
        end
        scheduleSyncRefresh()
        return
      end
      if type(value) == "table" then
        data = value
        break
      end
      if type(value) == "string" then
        local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, value)
        if decodedOk and type(decoded) == "table" then
          data = decoded
          break
        end
      end
    end
    local decodedData = gameInfo.applySync(data)
    if type(decodedData) ~= "table" then
      scheduleSyncRefresh()
      return
    end
    decodedData = table.clone(decodedData)
    decodedData.Source = "packet"
    notifyBallSync(decodedData)
  end
  local watcherReady = gameInfo.installBallWatcher(utils.trackGlobal, notifyBallSync)
  if watcherReady ~= true then
    error("GameInfo.installBallWatcher falhou", 2)
  end
  local syncReady = gameInfo.bindBallSync(onBallSync)
  local maintenanceReady = gameInfo.startMaintenance({
    isActive = utils.isActive,
    onBallSync = onBallSync,
  })
  if maintenanceReady ~= true then
    error("GameInfo.startMaintenance falhou", 2)
  end
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
function Runtime.createAPI(loaded)
  local info, utils = loaded.gameinfo, loaded.utils
  return {
    readouts = loaded.telemetry.create(loaded),
    createActions = function(context) return loaded.inventoryactions.create(loaded, context) end,
    getJumpButton = function()
      local player = utils.getLocalPlayer()
      local gui = player and player:FindFirstChildOfClass("PlayerGui")
      for _, name in ipairs({ "Interface", "MobileUI", "Buttons", "Jump", "Button" }) do
        gui = gui and gui:FindFirstChild(name)
      end
      return gui
    end,
    getUIConfig = function() return loaded.gameui.definition end,
    getGameContext = info.getGameContext,
    areAbilitiesEnabled = info.areAbilitiesEnabled,
    getAbilityAvailability = info.getAbilityAvailability,
    observeAbilityMode = info.observeAbilityMode,
    hasClashPrediction = loaded.autospam.hasClashPrediction,
    resetState = loaded.spam.resetState,
    createVisualAdapter = loaded.nativevisuals.create,
    applyVisualPolicy = loaded.nativevisuals.apply,
    controls = {
      setManualSpam = utils.setManualSpamActive,
      isManualSpamActive = utils.isManualSpamActive,
      onAutoDarkChanged = loaded.autodark.sync,
      onAutoJumpChanged = loaded.autojump.sync,
      onUpDash = function()
        local ok, err = loaded.movement.upDash()
        if not ok then
          utils.recordError("UpDash", err or "Dash indisponível")
        end
      end,
      onPanic = function()
        utils.setConfig({ AutoParry = false, AutoSpam = false })
        utils.stopAllSpam()
        loaded.autospam.stopSpam()
      end,
    },
    updateBlockers = {
      function()
        local match = info.getGameContext()
        if not match.inMatch or not match.alive then
          return false
        end
        local physics = loaded.deflectgeometry.getDefensePhysics()
        local clash = info.getClashContext()
        local spam = loaded.autospam.getActivationContext()
        return (physics and physics.inClash == true)
          or (clash and type(clash.age) == "number" and clash.age >= 0 and clash.age <= 0.8)
          or (spam and spam.active == true)
      end,
    },
    miniVisibility = {
      MiniSpamVisible = function()
        if utils.getConfigValue("ManualSpamUIOnDuel") ~= true then
          return false
        end
        local match = info.getGameContext()
        if not match.inMatch or not match.alive or not match.roundActive then
          return false
        end
        local count = 0
        for _, candidate in ipairs(utils.getPlayers():GetPlayers()) do
          local lives, model = candidate:GetAttribute("Lives"), candidate.Character
          local humanoid = model and model:FindFirstChildOfClass("Humanoid")
          if type(lives) == "number" and lives > 0 and candidate:GetAttribute("Playing") ~= false and humanoid and humanoid.Health > 0 then
            count += 1
          end
        end
        return count == 2
      end,
    },
    migrateConfig = function(data)
      local changed = false
      if data.AutoSpam == nil and type(data.AutoClash) == "boolean" then
        data.AutoSpam = data.AutoClash
        changed = true
      end
      if data.AutoParryFactor08Applied ~= true then
        data.AutoParryWindowFactor, data.AutoParryFactor08Applied, changed = 0.25, true, true
      elseif tonumber(data.AutoParryWindowFactor) == 0.8 then
        data.AutoParryWindowFactor, changed = 0.25, true
      end
      if data.AutoParryFactor03Applied ~= true then
        if tonumber(data.AutoParryWindowFactor) == 0.25 then
          data.AutoParryWindowFactor = 0.3
        end
        data.AutoParryFactor03Applied, changed = true, true
      end
      if data.ClickMethod == "Game" then
        data.ClickMethod, changed = "Deflect", true
      end
      for _, key in ipairs({
        "AutoClash",
        "AutoClashActivationMs",
        "AutoClashDeactivationMs",
        "ClashMaxDistance",
        "AutoSpamClashPrediction",
        "AutoSpamPredictionMargin",
        "ClashGrace",
        "ClashMaxAge",
      }) do
        if data[key] ~= nil then
          data[key], changed = nil, true
        end
      end
      return changed
    end,
  }
end
function Runtime.teardown()
  if assistScope then
    assistScope.destroy()
    assistScope = nil
  end
  return true
end
Runtime.__contract = { provides = { "setup", "teardown", "bind", "createAPI" }, requires = {} }

return Runtime
