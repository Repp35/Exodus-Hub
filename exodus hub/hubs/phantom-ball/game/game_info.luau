-- [[ gameinfo ]]

-- module
local GameInfo = {}
local utils
local resolveTarget
local syncSequence
local registry
local profiler
local presenceTracker
local evaluationDepth = 0
local parryProjectionCache
local players
local world
local ball = nil
local searchAt = 0
local watching = false
local ballVisualConnection
local abilityScript
local abilities
local replicatorScript
local replicator
local gameBallScript
local gameBall
local ballSync
local targeting
local targetCache
local targetCacheAt
local targetAttributeAt = 0
local ballData
local dashAnimation
local minimumSpeed
local maximumSpeed
local speedAt
local syncConnection = nil
local syncRemote = nil
local snapshotConnection = nil
local snapshotRemote = nil
local maintenance = 0
local pingSamples, pingIndex, pingSum, pingSampleAt, pingRaw = {}, 0, 0, nil, nil
local trainingConnection = nil
local trainingRemote = nil
local trainingState = nil
local trainingSequence = 0
local trainingEventConnection
local trainingEventRemote
local trainingZone
local trainingRound = 0
local trainingDespawned = false
local trainingServerTime = nil
local trainingPacketFloor = -math.huge
local trainingObservers = {}
local trainingParryAt
local trainingDataModule
local trainingData
local ballFeelModule
local ballFeel
local trainingSharedModule
local trainingShared
local snapshotBuilder
local dashStateCache = setmetatable({}, { __mode = "k" })

-- configuration
local CONFIG = {
  MIN_SPEED = 16,
  MAX_SPEED = 600,
  PACKET_AGE = 0.5,
  BALL_SEARCH_INTERVAL = 0.5,
  SYNC_CONNECTED_INTERVAL = 3,
  SYNC_RETRY_INTERVAL = 1,
  SPAM_MIN_INTERVAL = 0.008,
  SPEED_REFRESH = 0.5,
  SAMPLE_INTERVAL = 1 / 240,
  SAMPLE_MAX_GAP = 0.5,
  PING_SAMPLE_INTERVAL = 0.25,
  PING_SAMPLE_COUNT = 8,
  SNAPSHOT_CACHE_INTERVAL = 1 / 240,
  DASH_STATE_CACHE_INTERVAL = 1 / 30,
  GAME_IDS = {
    DEFLECT = 1,
    DASH = 2,
    FIERCE = 19,
    DARK = 20,
    HAUNTER_REMOTE = 9.150098456648103e76,
    DARK_EVENT = 2.4141700243704228e76,
    MANIFEST_REMOTE = 9.318024238496386e76,
    CRATE_CHECK = 4.702176977990345e76,
    CRATE_OWNED = 1.796923298985336e75,
    CRATE_NEW = 1.0038569313364564e77,
  },
}

minimumSpeed, maximumSpeed, speedAt = CONFIG.MIN_SPEED, CONFIG.MAX_SPEED, 0

-- helpers
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function validBallSpeed(value) return finite(value) and value >= 0 and value <= 1000 end
local function finiteVector(value) return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z) end
local function invalidateSnapshotCache()
  if snapshotBuilder then
    snapshotBuilder.invalidate()
  end
  targetCache, targetCacheAt = nil, -math.huge
end
local function child(parent, name) return parent and parent:FindFirstChild(name) end
local function load(module, name)
  if not module or not module:IsA("ModuleScript") then
    error("API externa ausente: TS." .. tostring(name), 2)
  end
  local result = require(module)
  if type(result) ~= "table" then
    error("API externa inválida: TS." .. tostring(name) .. " não retornou tabela", 2)
  end
  return result
end
local function storage() return utils and utils.getReplicatedStorage() end
local function ts() return child(storage(), "Shared") or child(storage(), "TS") end
local function sharedLayout() return child(storage(), "Shared") ~= nil end
local function getTrainingSource()
  local module = child(child(storage(), "Training"), "TrainingShared")
  if module ~= trainingSharedModule then
    trainingSharedModule, trainingShared = module, nil
  end
  if module and not trainingShared then
    local ok, result = pcall(load, module, "TrainingShared")
    if ok then
      trainingShared = result
    end
  end
  return trainingShared
end
local function inTrainingArea()
  local player = players and players.LocalPlayer
  if not registry then
    return false
  end
  local _, _, _, root = registry.getParts(player and player.UserId)
  if not root then
    return false
  end
  local lives = player:GetAttribute("Lives")
  local module = child(child(ts(), "Core"), "GameData")
  if module ~= trainingDataModule then
    trainingDataModule, trainingData = module, nil
  end
  if module and not trainingData then
    local ok, result = pcall(load, module, "GameData")
    if ok then
      trainingData = result.GameData
    end
  end
  if trainingData and type(trainingData.GetFallback) == "function" then
    local ok, result = pcall(trainingData.GetFallback, trainingData, player, "Lives", 0)
    if ok then
      lives = result
    end
  end
  if finite(lives) and lives > 0 then
    return false
  end
  local source = getTrainingSource()
  if source and type(source.InZone) == "function" then
    local ok, inside = pcall(source.InZone, root.Position)
    if ok and type(inside) == "boolean" then
      return inside
    end
  end
  local area = trainingZone
  if not area or not area.Parent then
    area = child(child(child(world, "Training"), "Areas"), "Zone")
    trainingZone = area
  end
  if not area or not area:IsA("BasePart") then
    return false
  end
  local localPos, half = area.CFrame:PointToObjectSpace(root.Position), area.Size / 2
  return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end
function GameInfo.isTrainingArea() return inTrainingArea() end
function GameInfo.fireTrainingParry()
  if not inTrainingArea() then
    return false, "fora da arena de treino"
  end
  local endpoint = child(child(child(storage(), "Training"), "Remotes"), "Block")
  local camera = world.CurrentCamera
  if not endpoint or not endpoint:IsA("RemoteEvent") or not camera then
    return false, "bloqueio de treino indisponível"
  end
  endpoint:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
  return true
end

-- abilities
local function getAbilities()
  if abilities and abilityScript and abilityScript.Parent then
    return abilities
  end
  local root = ts()
  local module = child(child(root, "Abilities"), "ClientAbilities") or child(root, "ClientAbilities")
  if abilityScript ~= module then
    abilityScript, abilities = module, nil
  end
  if not module then
    return nil
  end
  if not abilities then
    local value = load(module, "ClientAbilities")
    if type(value.Abilities) ~= "table" then
      error("API externa ausente: TS.ClientAbilities.Abilities", 2)
    end
    abilities = value.Abilities
  end
  return abilities
end
local function getAbility(index, method)
  local list = getAbilities()
  local ability = list and list[index]
  if ability == nil then
    return nil
  end
  if type(ability) ~= "table" or type(ability[method]) ~= "function" then
    error(("API externa ausente: ClientAbilities[%d].%s"):format(index, method), 2)
  end
  return ability
end
local function getReplicator()
  if replicator and replicatorScript and replicatorScript.Parent then
    return replicator
  end
  local root = ts()
  local folder = child(child(root, "Gameplay"), "BallReplicator") or child(root, "BallReplicator")
  local module = folder and (folder:IsA("ModuleScript") and folder or child(folder, "BallReplicator"))
  if module ~= replicatorScript then
    replicatorScript, replicator = module, nil
  end
  if not replicator and module then
    local ok, value = pcall(load, module, "BallReplicator")
    if ok then
      if type(value.BallReplicator) == "table" then
        replicator = value.BallReplicator
      elseif value.syncData ~= nil then
        replicator = value
      end
    end
  end
  return replicator
end
local function syncData(provider) return ballSync and ballSync.getData(provider) or nil end

-- targeting
function GameInfo.getBallTargetAttribute() return world:GetAttribute("GameBallTarget") end
local function findBall()
  local candidate = world:FindFirstChild("GameBall") or world:FindFirstChild("GameBall", true)
  if candidate and candidate:IsA("BasePart") then
    return candidate
  end
  return nil
end
local function getBall()
  if ball and ball.Parent then
    return ball
  end
  if watching and os.clock() < searchAt then
    return nil
  end
  local previous = ball
  ball, searchAt = findBall(), os.clock() + CONFIG.BALL_SEARCH_INTERVAL
  if previous ~= ball then
    invalidateSnapshotCache()
  end
  return ball
end
local function disconnect(connection)
  if connection then
    if utils and type(utils.untrackGlobal) == "function" then
      utils.untrackGlobal(connection)
    end
    connection:Disconnect()
  end
end

-- synchronization
local function validSyncRemote(instance)
  return typeof(instance) == "Instance" and (instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")) and instance.Parent ~= nil
end
local function disconnectSync()
  if syncConnection then
    if utils then
      utils.untrackGlobal(syncConnection)
    end
    syncConnection:Disconnect()
  end
  if snapshotConnection then
    if utils then
      utils.untrackGlobal(snapshotConnection)
    end
    snapshotConnection:Disconnect()
  end
  syncConnection, syncRemote, snapshotConnection, snapshotRemote = nil, nil, nil, nil
end
local function findSyncRemote()
  local replicated = storage()
  if not replicated then
    return nil
  end
  local remotes = replicated:FindFirstChild("Remotes")
  local candidate = remotes and remotes:FindFirstChild("BallSyncData")
  if validSyncRemote(candidate) then
    return candidate
  end
  candidate = replicated:FindFirstChild("BallSyncData")
  if validSyncRemote(candidate) then
    return candidate
  end
  candidate = replicated:FindFirstChild("BallSyncData", true)
  if validSyncRemote(candidate) then
    return candidate
  end
  return nil
end
local function notifyTraining()
  local listeners = table.clone(trainingObservers)
  for _, entry in ipairs(listeners) do
    if entry.Connected then
      local ok, err = pcall(entry.callback)
      if not ok then
        utils.recordError("Training.onState", err)
      end
    end
  end
end
function GameInfo.observeTraining(callback)
  assert(type(callback) == "function", "training callback required")
  local entry = { Connected = true, callback = callback }
  function entry:Disconnect()
    if not self.Connected then
      return
    end
    self.Connected = false
    local index = table.find(trainingObservers, self)
    if index then
      table.remove(trainingObservers, index)
    end
  end
  trainingObservers[#trainingObservers + 1] = entry
  return entry
end
local function resetTrainingBall(despawned)
  trainingPacketFloor = math.max(trainingPacketFloor, trainingServerTime or -math.huge)
  trainingRound += 1
  trainingState, trainingDespawned, trainingParryAt, trainingServerTime = nil, despawned, nil, nil
  invalidateSnapshotCache()
end
local function bindTrainingSync()
  local remotes = child(child(storage(), "Training"), "Remotes")
  local event = child(remotes, "Event")
  if not validSyncRemote(event) then
    event = nil
  end
  if trainingEventRemote ~= event or (trainingEventConnection and not trainingEventConnection.Connected) then
    disconnect(trainingEventConnection)
    trainingEventConnection, trainingEventRemote = nil, event
    resetTrainingBall(false)
  end
  if event and not trainingEventConnection then
    trainingEventConnection = event.OnClientEvent:Connect(function(kind, playerId)
      if kind == "BallSpawn" then
        resetTrainingBall(false)
      elseif kind == "BallDespawn" or kind == "Kill" then
        resetTrainingBall(true)
      elseif kind == "Parry" and players.LocalPlayer and playerId == players.LocalPlayer.UserId then
        trainingParryAt = world:GetServerTimeNow()
        invalidateSnapshotCache()
      end
      notifyTraining()
    end)
    utils.trackGlobal(trainingEventConnection)
  end
  local training = child(remotes, "BallState")
  if not validSyncRemote(training) then
    training = nil
  end
  if trainingRemote ~= training or (trainingConnection and not trainingConnection.Connected) then
    disconnect(trainingConnection)
    trainingConnection, trainingRemote, trainingServerTime = nil, nil, nil
    resetTrainingBall(trainingDespawned)
  end
  if training and not trainingConnection then
    trainingRemote = training
    trainingConnection = training.OnClientEvent:Connect(function(position, velocity, serverTime, goal, target, speed)
      if not finiteVector(position) or not finiteVector(velocity) or not finite(serverTime) then
        return
      end
      local receivedAt = os.clock()
      local age = world:GetServerTimeNow() - serverTime
      if age < -0.02 or age > 0.6 or serverTime <= trainingPacketFloor or (trainingServerTime and serverTime <= trainingServerTime) then
        return
      end
      if trainingDespawned then
        resetTrainingBall(false)
      end
      if speed == nil then
        speed = velocity.Magnitude
      end
      if not validBallSpeed(speed) then
        return
      end
      trainingServerTime = serverTime
      trainingSequence = (trainingSequence + 1) % 65536
      trainingState = {
        position = position,
        velocity = velocity,
        serverTime = serverTime,
        goal = goal,
        target = target,
        speed = speed,
        receivedAt = receivedAt,
        sequence = trainingSequence,
        round = trainingRound,
      }

      invalidateSnapshotCache()
      notifyTraining()
    end)
    utils.trackGlobal(trainingConnection)
  end
end
function GameInfo.bindBallSync(handler)
  if type(handler) ~= "function" then
    return false
  end
  bindTrainingSync()
  local nativeReady = ballSync.bindNative(handler)
  local candidate = findSyncRemote()
  if not candidate then
    if syncRemote and not validSyncRemote(syncRemote) then
      disconnectSync()
    end
    return nativeReady or (syncConnection ~= nil and syncConnection.Connected == true)
  end
  local replicated = storage()
  local remotes = replicated and replicated:FindFirstChild("Remotes")
  local snapshotCandidate = remotes and remotes:FindFirstChild("BallSnapshot")
  if not validSyncRemote(snapshotCandidate) then
    snapshotCandidate = nil
  end
  if not (syncConnection and syncConnection.Connected and syncRemote == candidate) then
    disconnectSync()
    syncConnection, syncRemote = candidate.OnClientEvent:Connect(handler), candidate
    utils.trackGlobal(syncConnection)
  end
  if snapshotRemote ~= snapshotCandidate or (snapshotConnection and not snapshotConnection.Connected) then
    if snapshotConnection then
      utils.untrackGlobal(snapshotConnection)
      snapshotConnection:Disconnect()
    end
    snapshotConnection, snapshotRemote = nil, nil
  end
  if snapshotCandidate and not snapshotConnection then
    snapshotConnection, snapshotRemote = snapshotCandidate.OnClientEvent:Connect(handler), snapshotCandidate
    utils.trackGlobal(snapshotConnection)
  end
  return true
end

-- lifecycle
function GameInfo.startMaintenance(options)
  if type(options) ~= "table" or type(options.isActive) ~= "function" then
    return false
  end
  maintenance += 1
  local token = maintenance
  task.spawn(function()
    while token == maintenance do
      if not options.isActive() or token ~= maintenance then
        break
      end
      local linked = type(options.onBallSync) == "function" and GameInfo.bindBallSync(options.onBallSync)
      if token ~= maintenance then
        break
      end
      task.wait(linked and CONFIG.SYNC_CONNECTED_INTERVAL or CONFIG.SYNC_RETRY_INTERVAL)
    end
  end)
  return true
end
function GameInfo.stopMaintenance()
  if presenceTracker then
    presenceTracker.stop()
    presenceTracker = nil
  end
  maintenance += 1
  if ballSync then
    ballSync.destroy()
  end
  disconnectSync()
  disconnect(trainingConnection)
  disconnect(trainingEventConnection)
  trainingConnection, trainingRemote, trainingServerTime = nil, nil, nil
  trainingEventConnection, trainingEventRemote = nil, nil
  resetTrainingBall(false)
end
function GameInfo.teardown()
  GameInfo.stopMaintenance()
  if ballVisualConnection then
    disconnect(ballVisualConnection)
    ballVisualConnection = nil
  end
  for _, entry in ipairs(trainingObservers) do
    entry.Connected = false
  end
  table.clear(trainingObservers)
  table.clear(dashStateCache)
  ball, ballData, snapshotBuilder, targetCache, trainingZone = nil, nil, nil, nil, nil
  abilityScript, abilities, replicatorScript, replicator, gameBallScript, gameBall = nil, nil, nil, nil, nil, nil
  trainingDataModule, trainingData, dashAnimation, ballSync, targeting, registry = nil, nil, nil, nil, nil, nil
  ballFeelModule, ballFeel, trainingSharedModule, trainingShared = nil, nil, nil, nil
  evaluationDepth, parryProjectionCache = 0, nil
end
function GameInfo.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then
    return false, "dependência ausente: Utils"
  end
  if type(deps.BallSync) ~= "table" or type(deps.BallSync.create) ~= "function" then
    return false, "dependência ausente: BallSync"
  end
  if type(deps.Targeting) ~= "table" or type(deps.Targeting.create) ~= "function" then
    return false, "dependência ausente: Targeting"
  end
  GameInfo.stopMaintenance()
  ballFeelModule, ballFeel, trainingSharedModule, trainingShared = nil, nil, nil, nil
  utils, registry = deps.Utils, deps.PlayerRegistry
  evaluationDepth, parryProjectionCache = 0, nil
  profiler = deps.Profiler
  ballSync = deps.BallSync.create({
    getReplicator = getReplicator,
    invalidateSnapshotCache = invalidateSnapshotCache,
    packetAge = CONFIG.PACKET_AGE,
    serverNow = function() return world and world:GetServerTimeNow() end,
    report = function(detail) utils.recordError("BallSync.native", detail) end,
  })
  targeting = deps.Targeting.create({ storage = storage })
  targetCache, targetCacheAt, targetAttributeAt = nil, -math.huge, 0
  players, world = utils.getPlayers(), utils.getWorkspace()
  if not players or not world then
    return false, "dependência ausente: Players ou Workspace"
  end
  if ballVisualConnection then
    disconnect(ballVisualConnection)
    ballVisualConnection = nil
  end
  ball, searchAt, watching = nil, 0, false
  ballData, dashAnimation = nil, nil
  abilityScript, abilities, replicatorScript, replicator, gameBallScript, gameBall = nil, nil, nil, nil, nil, nil
  trainingState, trainingSequence, trainingDataModule, trainingData = nil, 0, nil, nil
  trainingZone, snapshotBuilder = nil, nil
  trainingPacketFloor = -math.huge
  table.clear(dashStateCache)
  minimumSpeed, maximumSpeed, speedAt = CONFIG.MIN_SPEED, CONFIG.MAX_SPEED, 0
  pingSamples, pingIndex, pingSum, pingSampleAt, pingRaw = {}, 0, 0, nil, nil
  presenceTracker = deps.Presence.create(utils, registry)
  presenceTracker.start()
  snapshotBuilder = deps.Snapshots.create({
    utils = utils,
    world = world,
    players = players,
    config = CONFIG,
    getTrainingState = function() return trainingState end,
    getTrainingParryAt = function() return trainingParryAt end,
    getTrainingSignals = targeting.training,
    inEvaluation = function() return evaluationDepth > 0 end,
    getBall = getBall,
    getReplicator = getReplicator,
    syncData = syncData,
    resolveTarget = resolveTarget,
    syncSequence = syncSequence,
    inTrainingArea = inTrainingArea,
    getBallFrozen = GameInfo.getBallFrozen,
    getReceivedAt = ballSync.getReceivedAt,
    getVersion = ballSync.getVersion,
  })
  return true
end
function GameInfo.getBall() return getBall() end
function GameInfo.getBallPosition(value) return value.Position end
function GameInfo.getBallVelocity(value) return value.AssemblyLinearVelocity end
function GameInfo.getRootPosition(root) return root.Position end
function GameInfo.getLocalPing() return players.LocalPlayer and players.LocalPlayer:GetNetworkPing() or nil end
function GameInfo.getAveragePing()
  local time = os.clock()
  if pingSampleAt == nil or time < pingSampleAt or time - pingSampleAt >= CONFIG.PING_SAMPLE_INTERVAL then
    pingSampleAt = time
    local value = GameInfo.getLocalPing()
    if finite(value) and value >= 0 then
      pingRaw = value
      if #pingSamples < CONFIG.PING_SAMPLE_COUNT then
        pingSamples[#pingSamples + 1] = value
      else
        pingIndex = pingIndex % CONFIG.PING_SAMPLE_COUNT + 1
        pingSum -= pingSamples[pingIndex]
        pingSamples[pingIndex] = value
      end
      pingSum += value
    end
  end
  return #pingSamples > 0 and pingSum / #pingSamples or 0, pingRaw, #pingSamples
end
local MATCH_STATUSES = {
  [-1] = "None",
  [0] = "WaitingForPlayers",
  [1] = "Intermission",
  [2] = "VoteGamemode",
  [3] = "VoteMap",
  [4] = "VoteLives",
  [5] = "Starting",
  [6] = "InGame",
}

local GAME_MODES = { [0] = "Phantom Ball", [1] = "2 Teams", [2] = "4 Teams", [3] = "Zero Abilities", [5] = "Ball Bounce", [6] = "No Movement", [7] = "3 Lives" }
function GameInfo.getGameContext()
  presenceTracker.update()
  local presence, presenceHumanoid = presenceTracker.get()
  local player = players and players.LocalPlayer
  local placeId = game.PlaceId
  local matchStatus = world and world:GetAttribute("MatchStatus")
  local modeId = world and world:GetAttribute("CurGamemode")
  local lives = player and player:GetAttribute("Lives")
  local playing = player and player:GetAttribute("Playing")
  local afk = player and player:GetAttribute("AFK")
  local roundActive
  if finite(matchStatus) then
    roundActive = matchStatus == 6
  end
  local inMatch = presence.entered == true
  local training = inTrainingArea()
  local area = "unknown"
  if placeId == 12979690461 then
    if inMatch then
      area = "match"
    elseif training then
      area = "training"
    elseif player and finite(lives) then
      area = "lobby"
    end
  end
  return {
    area = area,
    placeId = placeId,
    inMatch = inMatch,
    eliminated = presence.eliminated == true,
    alive = presenceHumanoid ~= nil and presenceHumanoid.Health > 0,
    roundActive = roundActive,
    training = training,
    playing = playing,
    lives = lives,
    afkEnabled = afk == true,
    matchStatus = matchStatus,
    matchStatusName = MATCH_STATUSES[matchStatus],
    modeId = modeId,
    modeName = GAME_MODES[modeId],
  }
end
function GameInfo.areAbilitiesEnabled() return world:GetAttribute("CurGamemode") ~= 3 end
function GameInfo.getNativeButtonAnimations()
  local root = ts()
  local module = child(child(root, "UI"), "ButtonAnimations")
  if not module then
    return nil
  end
  local value = load(module, "ButtonAnimations")
  local animations = value and value.ButtonAnimations
  if type(animations) == "table" and type(animations.Bind) == "function" and type(animations.Unbind) == "function" then
    return animations
  end
  return nil
end
function GameInfo.getAbilityAvailability(name)
  local ids = { dark = CONFIG.GAME_IDS.DARK, dash = CONFIG.GAME_IDS.DASH, fierce = CONFIG.GAME_IDS.FIERCE }
  local labels = { dark = "Dark Seal", dash = "Dash", fierce = "Fierce Deflect" }
  local id = ids[name]
  if not id then
    return false, "Habilidade desconhecida."
  end
  if not GameInfo.areAbilitiesEnabled() then
    return false, "Esta partida está no modo sem habilidades."
  end
  local equipped = getAbilities()
  if not equipped or not equipped[id] then
    return false, "Você precisa equipar " .. labels[name] .. " para usar esta opção."
  end
  return true
end
function GameInfo.observeAbilityMode(callback)
  return world:GetAttributeChangedSignal("CurGamemode"):Connect(function() callback(GameInfo.areAbilitiesEnabled()) end)
end
local function generatedRemote(id)
  local root = ts()
  local remotes = child(child(root, "Network"), "GeneratedNetworkRemotes") or child(root, "GeneratedNetworkRemotes")
  local remote = child(remotes, "RE_" .. tostring(id))
  return remote and remote:IsA("RemoteEvent") and remote or nil
end
function GameInfo.getHaunterEvent() return generatedRemote(CONFIG.GAME_IDS.HAUNTER_REMOTE) end
local function playerRoot(id)
  local _, character, _, root = registry.getParts(id)
  return root, character
end
function GameInfo.getPlayerMotion(id)
  local root, character = playerRoot(id)
  if not root then
    return nil
  end
  return root.Position, root.AssemblyLinearVelocity, character
end
function GameInfo.getDeflectTargetPrediction(id)
  local source = players:GetPlayerByUserId(id)
  local root = source and source.Character and source.Character:FindFirstChild("HumanoidRootPart")
  if not root then
    return nil
  end
  local mode = world:GetAttribute("CurGamemode")
  local teams = mode == 1 or mode == 2
  local candidates = {}
  for _, candidate in ipairs(registry.getPlayers()) do
    local position, character = playerRoot(candidate.UserId)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local lives = candidate:GetAttribute("Lives")
    if
      candidate ~= source
      and candidate:GetAttribute("IsCloaked") ~= true
      and position
      and humanoid
      and humanoid.Health > 0
      and (not finite(lives) or lives > 0)
      and candidate:GetAttribute("Playing") ~= false
      and (not teams or source:GetAttribute("PlayerTeam") ~= candidate:GetAttribute("PlayerTeam"))
    then
      if candidate:GetAttribute("DarkSealed") == true then
        return candidate.UserId, 1, 1, "dark_seal"
      end
      if candidate:GetAttribute("IsCloaked") ~= true then
        candidates[#candidates + 1] = { player = candidate, root = position }
      end
    end
  end
  local camera = source:GetAttribute("CamCFrame")
  local observed = typeof(camera) == "CFrame"
  if not observed then
    camera = root.CFrame
  end
  if typeof(camera) ~= "CFrame" then
    return nil
  end
  local origin, look = camera.Position, camera.LookVector
  if (origin - root.Position).Magnitude > 64 then
    origin = root.Position
  end
  if not finiteVector(origin) or not finiteVector(look) or look.Magnitude < 0.5 then
    return nil
  end
  if #candidates == 1 then
    return candidates[1].player.UserId, 1, 1, "single_candidate"
  end
  look = look.Unit
  local winner, best, runner = nil, -math.huge, -math.huge
  for _, entry in ipairs(candidates) do
    local candidate, position = entry.player, entry.root
    local delta = position.Position - origin
    if delta.Magnitude > 0.001 then
      local score = look:Dot(delta.Unit)
      if score > best then
        winner, runner, best = candidate.UserId, best, score
      elseif score > runner then
        runner = score
      end
    end
  end
  if winner then
    local separation = best - runner
    if best < (observed and 0.75 or 0.9) or separation < (observed and 0.03 or 0.15) then
      return nil, best, separation, "aim_uncertain"
    end
    return winner, best, separation, observed and "camera" or "root"
  end
  return nil
end
function GameInfo.getPlayerDistance(id)
  local own = players.LocalPlayer
  local ownRoot = own and own.Character and own.Character:FindFirstChild("HumanoidRootPart")
  local otherRoot = playerRoot(id)
  if not ownRoot or not ownRoot.Parent or not otherRoot then
    return nil
  end
  return (ownRoot.Position - otherRoot.Position).Magnitude
end
function GameInfo.getParrySignal()
  local folder = child(child(ts(), "Gameplay"), "BallReplicator") or child(ts(), "BallReplicator")
  local module = child(folder, "BallFeel")
  if module ~= ballFeelModule then
    ballFeelModule, ballFeel = module, nil
  end
  if module and not ballFeel then
    local ok, result = pcall(load, module, "BallFeel")
    if ok then
      ballFeel = result
    end
  end
  return ballFeel and ballFeel.Hit or nil
end
function GameInfo.getTrainingWindow(speed)
  local trainingShared = getTrainingSource()
  if trainingShared and type(trainingShared.GetBlockWindow) == "function" then
    local ok, window = pcall(trainingShared.GetBlockWindow, speed)
    return ok and finite(window) and window > 0 and window or nil
  end
  local low, high = trainingShared and trainingShared.BaseSpeed or 16, trainingShared and trainingShared.MaxSpeed or 600
  if not finite(low) or not finite(high) or high <= low then
    return nil
  end
  return 0.85 - 0.65 * math.clamp((speed - low) / (high - low), 0, 1)
end
function GameInfo.isNativeClash()
  local source = GameInfo.getDefenseSource()
  local player = players.LocalPlayer
  if not source or not player or type(source.IsInClash) ~= "function" then
    return false
  end
  local ok, result = pcall(source.IsInClash, source, player)
  return ok and result == true
end
function GameInfo.getLastAcceptedDeflectAt()
  local ability = GameInfo.getDeflectAbility()
  local stamp = ability and ability.LastDeflectCallAt
  return finite(stamp) and stamp >= 0 and stamp or nil
end
function GameInfo.getDeflectAbility() return getAbility(CONFIG.GAME_IDS.DEFLECT, "Deflect") end
function GameInfo.getDeflectCallStamp(ability)
  ability = ability or GameInfo.getDeflectAbility()
  if not ability then
    return nil
  end
  local called, pressed = ability.LastDeflectCallAt, ability.LastPressClock
  if not finite(called) or called < 0 then
    called = nil
  end
  if not finite(pressed) or pressed < 0 then
    pressed = nil
  end
  return called and pressed and math.max(called, pressed) or called or pressed
end
function GameInfo.getLastDeflectPressAt()
  local ability = GameInfo.getDeflectAbility()
  if not ability then
    return nil
  end
  local pressedAt = GameInfo.getDeflectCallStamp(ability)
  if finite(pressedAt) and pressedAt > 0 then
    return pressedAt
  end
  local latest
  if type(ability.ClickInstances) == "table" then
    for _, click in ipairs(ability.ClickInstances) do
      local remaining = type(click) == "table" and click.Time
      if finite(remaining) and remaining > 0 and remaining <= 1 then
        latest = latest and math.max(latest, remaining) or remaining
      end
    end
  end
  return latest and (os.clock() - (1 - latest)) or 0
end
function GameInfo.getMinimumSpamInterval() return CONFIG.SPAM_MIN_INTERVAL end
function GameInfo.getAutoSpamDelay()
  local ability = GameInfo.getDeflectAbility()
  if not ability then
    return nil
  end
  local time = os.clock()
  local last = ability.LastDeflectCallAt or ability.LastPressClock
  local delay = finite(last) and math.max(0, CONFIG.SPAM_MIN_INTERVAL - (time - last)) or 0
  local limit = world:GetAttribute("CPS_LIMIT")
  if not finite(limit) then
    limit = 50
  end
  limit = math.floor(limit)
  if limit <= 0 then
    return nil
  end
  local clicks = ability.ClickInstances
  if type(clicks) ~= "table" then
    return nil
  end
  if #clicks >= limit then
    local remaining
    for _, click in ipairs(clicks) do
      if type(click) == "table" and finite(click.Time) then
        remaining = remaining and math.min(remaining, click.Time) or click.Time
      end
    end
    if not remaining then
      return nil
    end
    delay = math.max(delay, remaining > 0 and remaining or 1 / 240)
  end
  return delay
end
function GameInfo.getDashAbility() return getAbility(CONFIG.GAME_IDS.DASH, "Dash") end
function GameInfo.getDeflectAnimationCatalog()
  local animations = child(child(storage(), "Animations"), "Deflect")
  local catalog = {}
  if not animations then
    return catalog
  end
  local phases = { BlockStart = "start", BlockLoop = "loop", Parry = "parry" }
  for _, animation in ipairs(animations:GetDescendants()) do
    local phase = phases[animation.Name]
    if phase and animation:IsA("Animation") then
      local id = animation.AnimationId:match("[?&]id=(%d+)") or animation.AnimationId:match("%d+")
      if id and (not catalog[id] or phase == "start") then
        catalog[id] = phase
      end
    end
  end
  return catalog
end
function GameInfo.getDeflectAttemptAnimationIds()
  local ids = {}
  for id, phase in pairs(GameInfo.getDeflectAnimationCatalog()) do
    if phase ~= "parry" then
      ids[id] = true
    end
  end
  return ids
end
function GameInfo.getLocalDashState()
  local ability = GameInfo.getDashAbility()
  if not ability then
    return false
  end
  return ability.Dashing == true, tonumber(ability.DashSpeed), tonumber(ability.DashTime)
end
function GameInfo.getPlayerDashKind(player)
  if not player then
    return "unknown"
  end
  if player == players.LocalPlayer then
    local list = getAbilities()
    local wind = list and list[22]
    if wind and (wind.Dashing == true or wind.Controlling == true) then
      return "wind", "native"
    end
    local ability = GameInfo.getDashAbility()
    if ability and ability.Dashing == true and ability.DashSpeed == 120 and ability.DashTime == 0.2 and ability.DashTime2 == nil then
      return "normal", "native"
    end
    return "unknown"
  end
  local character = player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not root then
    return "unknown"
  end
  local effect = root:FindFirstChild("WindDash")
  if effect then
    local objects = { effect }
    for _, item in ipairs(effect:GetDescendants()) do
      objects[#objects + 1] = item
    end
    for _, item in ipairs(objects) do
      if (item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail")) and item.Enabled then
        return "wind", "effect"
      end
    end
  end
  local signal = character:GetAttribute("IsDashing")
  if signal ~= true and signal ~= 1 and signal ~= "true" then
    return "unknown"
  end
  if root.AssemblyLinearVelocity.Magnitude > 140 then
    return "wind", "speed"
  end
  return "normal", "shared"
end
function GameInfo.isPlayerDashing(player)
  if not player then
    return false
  end
  if player == players.LocalPlayer then
    local ability = GameInfo.getDashAbility()
    return ability ~= nil and ability.Dashing == true
  end
  local character = player.Character
  local cached = dashStateCache[player]
  local time = os.clock()
  if cached and cached.character == character and time >= cached.at and time - cached.at < CONFIG.DASH_STATE_CACHE_INTERVAL then
    return cached.value
  end
  local function finish(value)
    cached = cached or {}
    cached.character, cached.at, cached.value = character, time, value
    dashStateCache[player] = cached
    return value
  end
  if not character or not character.Parent then
    return finish(false)
  end
  if character:GetAttribute("IsDashing") == true then
    return finish(true)
  end
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
  if not dashAnimation or not dashAnimation.Parent then
    local replicated = storage()
    local animations = replicated and replicated:FindFirstChild("Animations")
    local movement = animations and animations:FindFirstChild("Movement")
    dashAnimation = movement and movement:FindFirstChild("Dash")
  end
  if not animator or not dashAnimation or not dashAnimation:IsA("Animation") or dashAnimation.AnimationId == "" then
    return finish(false)
  end
  for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
    local animation = track.Animation
    if track.IsPlaying and animation and animation.AnimationId == dashAnimation.AnimationId then
      return finish(true)
    end
  end
  return finish(false)
end
function GameInfo.getFierceDeflectAbility() return getAbility(CONFIG.GAME_IDS.FIERCE, "ActivateAndBlock") end
function GameInfo.getDarkSealAbility() return getAbility(CONFIG.GAME_IDS.DARK, "SendEvent") end
function GameInfo.getSyncData() return syncData() end
syncSequence = function(current, provider) return ballSync.getSequence(current, provider) end
function GameInfo.getSyncSequence() return syncSequence(syncData(), getReplicator()) end
function GameInfo.getSyncVersion() return ballSync and ballSync.getVersion() or 0 end
function GameInfo.applyPacket(value) return ballSync.applyPacket(value) end
function GameInfo.decodeBallPacket(value) return ballSync.decodeBallPacket(value) end
resolveTarget = function(time, provider, sync, currentBall)
  time = finite(time) and time or utils.now()
  if targetCache and time >= targetCacheAt and (evaluationDepth > 0 or time - targetCacheAt < CONFIG.SNAPSHOT_CACHE_INTERVAL) then
    return targetCache
  end
  if provider == nil then
    provider = getReplicator()
  end
  if sync == nil then
    sync = syncData(provider or false)
  end
  if currentBall == nil then
    currentBall = getBall()
  end
  local receivedAt = ballSync.getReceivedAt()
  local fresh = receivedAt > 0 and time >= receivedAt and time - receivedAt <= CONFIG.PACKET_AGE
  local serverNow = type(world.GetServerTimeNow) == "function" and world:GetServerTimeNow() or nil
  local matchStatus = world:GetAttribute("MatchStatus")
  local report = targeting.resolve({
    player = players.LocalPlayer,
    players = players,
    world = world,
    ball = currentBall,
    sync = sync,
    syncFresh = fresh,
    receivedAt = receivedAt,
    attributeAt = targetAttributeAt,
    provider = provider,
    serverNow = serverNow,
    sequence = syncSequence(sync, provider),
    maxAge = CONFIG.PACKET_AGE,
    active = not finite(matchStatus) or matchStatus == 6,
  })
  targetCache, targetCacheAt = report, time
  return report
end
function GameInfo.getParryTargetStatus(time)
  targetCache, targetCacheAt = nil, -math.huge
  return resolveTarget(time)
end
function GameInfo.getTargetSignals(time)
  if inTrainingArea() then
    local id = trainingState and trainingState.goal
    local valid = finite(id) and id > 0
    return {
      mode = "training",
      targetId = valid and id or -1,
      targeted = valid and players.LocalPlayer ~= nil and id == players.LocalPlayer.UserId,
      known = valid,
      signals = {},
    }
  end
  local report = resolveTarget(time)
  local copy = table.clone(report)
  copy.positive, copy.signals = table.clone(report.positive), {}
  for index, signal in ipairs(report.signals) do
    copy.signals[index] = table.clone(signal)
  end
  return copy
end
function GameInfo.getTargetId()
  if inTrainingArea() then
    return trainingState and trainingState.goal or -1
  end
  return resolveTarget().targetId
end

-- snapshots
local function snapshot(time) return snapshotBuilder.get(time) end

-- public-api
function GameInfo.beginEvaluation()
  if evaluationDepth == 0 then
    invalidateSnapshotCache()
  end
  evaluationDepth += 1
end
function GameInfo.endEvaluation() evaluationDepth = math.max(0, evaluationDepth - 1) end
function GameInfo.getPlayers() return registry.getPlayers() end
function GameInfo.getPlayerParts(id) return registry.getParts(id) end
function GameInfo.getSnapshot(_, time) return snapshot(time) end
function GameInfo.getSnapshotAt(time) return snapshot(time) end
local function projectedSnapshot(value, position, velocity, speed, age, derived)
  local predicted = table.clone(value)
  predicted.visualPosition, predicted.visualVelocity = value.position, value.velocity
  predicted.position, predicted.velocity, predicted.speed = position, velocity, speed
  predicted.predictedVelocity, predicted.predicted, predicted.predictionAge, predicted.predictionSource = derived, true, age, "replicator_simulation"
  value.parrySnapshot, value.parrySampled = predicted, true
  return predicted
end
function GameInfo.getParrySnapshot(time, localTarget, needVelocity, minimumServerTime)
  local value = snapshot(time)
  if value and localTarget == true and value.mode ~= "training" and (not value.targeted or value.targetUncertain) then
    value = table.clone(value)
    value.targeted, value.targetUncertain, value.targetId = true, false, players.LocalPlayer.UserId
    value.parrySampled, value.parrySnapshot = nil, nil
  end
  if
    not value
    or value.mode == "training"
    or not value.targeted
    or value.ballCanMove == false
    or (value.teleported and localTarget ~= true)
    or value.locked
    or value.targetUncertain
  then
    return value
  end
  if finite(minimumServerTime) and finite(value.serverTime) and value.serverTime < minimumServerTime then
    return value
  end
  if value.parrySampled and (needVelocity == false or not value.parrySnapshot or value.parrySnapshot.predictedVelocity ~= false) then
    return value.parrySnapshot or value
  end
  local provider = getReplicator()
  if not provider or type(provider.SimulateFrom) ~= "function" or not world then
    return value
  end
  local history = provider.history
  local latest = type(history) == "table" and history[#history]
  local sync = syncData(provider)
  local sample, sampleKey
  if type(latest) == "table" and provider.lastSeq == value.syncSequence and latest.targetId == value.targetId then
    sample, sampleKey = latest, latest
  elseif sync and finite(sync.ServerTime) and finiteVector(sync.RealPosition) and finiteVector(sync.ForcedDirection) then
    sampleKey = sync
    sample = {
      position = sync.RealPosition,
      direction = sync.ForcedDirection,
      speed = sync.Speed,
      accel = finite(sync.Accel) and sync.Accel or 0,
      maxSpeed = sync.MaxSpeed or sync.Speed,
      serverTime = sync.ServerTime,
      targetId = sync.TargetPlayerID,
      locked = sync.Locked,
      grace = sync.Grace,
      oldGrace = sync.OldGrace,
      possessed = (sync.PossessorId or 0) ~= 0,
      curveTime = sync.CurveTime or 1,
      curveTimeMax = sync.CurveTimeMax or 1,
      curveAxis = sync.CurveAxis,
      bouncesLeft = sync.BouncesLeft or 0,
      flightTime = sync.FlightTime,
      noSpeedFeel = sync.NoSpeedFeel,
    }

  end
  if not sample or sample.targetId ~= value.targetId or not finite(sample.serverTime) or not finiteVector(sample.position) then
    return value
  end
  local serverNow = world:GetServerTimeNow()
  local age = serverNow - sample.serverTime
  if not finite(age) or age < -0.02 or age > 0.25 then
    return value
  end
  local target = playerRoot(value.targetId)
  if not target then
    return value
  end
  local now, own = os.clock(), target.Position
  local radius = players.LocalPlayer:GetAttribute("DeflectRange")
  radius = finite(radius) and math.clamp(radius, 8.5, 16) or 8.5
  if localTarget == true then
    local delta = sample.position - own
    local outer = radius + 1000 * (math.max(age, 0) + 0.5 * 0.85 + GameInfo.getAveragePing())
    if delta:Dot(delta) > outer * outer then
      return nil
    end
  end
  local cache = parryProjectionCache
  if
    cache
    and cache.provider == provider
    and cache.ball == value.ball
    and cache.sample == sampleKey
    and cache.serverTime == sample.serverTime
    and cache.sequence == value.syncSequence
    and cache.own == own
    and now >= cache.at
    and now - cache.at <= 0.001
    and (needVelocity == false or cache.derived)
  then
    return projectedSnapshot(value, cache.position, cache.velocity, sample.speed, cache.age, cache.derived)
  end
  local dt = 1 / 240
  local measured = profiler.begin("game.native_simulation")
  profiler.count("game.native_simulations")
  local ok, position = pcall(provider.SimulateFrom, provider, sample, math.max(age, 0), target.Position)
  if not ok or not finiteVector(position) then
    profiler.finish("game.native_simulation", measured)
    return value
  end
  local velocity = value.velocity
  local derived = false
  local delta = position - own
  if needVelocity ~= false or delta:Dot(delta) > radius * radius then
    profiler.count("game.native_simulations")
    local nextOk, nextPosition = pcall(provider.SimulateFrom, provider, sample, math.max(age, 0) + dt, target.Position)
    if not nextOk or not finiteVector(nextPosition) then
      profiler.finish("game.native_simulation", measured)
      return value
    end
    velocity, derived = (nextPosition - position) / dt, true
  end
  profiler.finish("game.native_simulation", measured)
  cache = cache or {}
  cache.provider, cache.ball, cache.sample, cache.serverTime, cache.sequence = provider, value.ball, sampleKey, sample.serverTime, value.syncSequence
  cache.own, cache.at, cache.position, cache.velocity, cache.age, cache.derived = own, now, position, velocity, math.max(age, 0), derived
  parryProjectionCache = cache
  return projectedSnapshot(value, position, velocity, sample.speed, math.max(age, 0), derived)
end
function GameInfo.isSnapshotValid(value)
  return type(value) == "table"
    and typeof(value.ball) == "Instance"
    and value.ball:IsA("BasePart")
    and value.ball.Parent ~= nil
    and finiteVector(value.position)
    and finiteVector(value.velocity)
    and validBallSpeed(value.speed)
    and (value.syncSpeed == nil or validBallSpeed(value.syncSpeed))
    and finite(value.targetId)
    and type(value.targeted) == "boolean"
end
function GameInfo.getDefenseSnapshot(time, predict)
  time = finite(time) and time or os.clock()
  local value = predict == false and snapshot(time) or GameInfo.getParrySnapshot(time)
  if not GameInfo.isSnapshotValid(value) then
    return nil, "snapshot_unavailable"
  end
  if value.teleported or value.locked or value.resetting or value.ballCanMove == false or value.frozen then
    return nil, "ball_unavailable"
  end
  if value.targetUncertain or value.targetId <= 0 or value.targetId % 1 ~= 0 then
    return nil, "target_unknown"
  end
  if finite(value.syncAt) and (time < value.syncAt or time - value.syncAt > CONFIG.PACKET_AGE) then
    return nil, "snapshot_stale"
  end
  if value.syncAt ~= nil and not finite(value.syncAt) then
    return nil, "snapshot_invalid"
  end
  if value.mode ~= "training" and not GameInfo.getGameContext().inMatch then
    return nil, "not_in_match"
  end
  return value
end
function GameInfo.isSnapshotAfterDeflect(value, confirmedAt)
  if type(value) ~= "table" or not finite(value.serverTime) or not finite(confirmedAt) then
    return false
  end
  local elapsed = os.clock() - confirmedAt
  if elapsed < 0 then
    return false
  end
  local floor = world:GetServerTimeNow() - elapsed - GameInfo.getAveragePing()
  return value.serverTime >= floor - 0.000001
end
function GameInfo.applySync(value) return ballSync.applySync(value) end
function GameInfo.installBallWatcher(track, onTargetChanged)
  if type(track) ~= "function" then
    return false, "trackConnection invalido"
  end
  local function targetChanged()
    invalidateSnapshotCache()
    if type(onTargetChanged) == "function" then
      onTargetChanged({ Source = "target" })
    end
  end
  local function watchVisual(item)
    if ballVisualConnection then
      disconnect(ballVisualConnection)
      ballVisualConnection = nil
    end
    if item then
      ballVisualConnection = item:GetPropertyChangedSignal("Color"):Connect(targetChanged)
      track(ballVisualConnection)
    end
  end
  for _, name in ipairs({ "LastParryAt", "LastParryBy", "LastParryTarget", "ClashStartedAt", "ClashHits" }) do
    track(world:GetAttributeChangedSignal(name):Connect(function()
      if type(onTargetChanged) == "function" then
        onTargetChanged({ Source = "clash" })
      end
    end))
  end
  track(world:GetAttributeChangedSignal("GameBallTarget"):Connect(function()
    targetAttributeAt = os.clock()
    invalidateSnapshotCache()
    if type(onTargetChanged) == "function" then
      onTargetChanged({ Source = "target", TargetPlayerID = world:GetAttribute("GameBallTarget") })
    end
  end))
  track((world.DescendantAdded or world.ChildAdded):Connect(function(item)
    if item.Name == "GameBall" and item:IsA("BasePart") and ball ~= item then
      ball = item
      watchVisual(item)
      invalidateSnapshotCache()
    end
  end))
  track((world.DescendantRemoving or world.ChildRemoved):Connect(function(item)
    if ball == item then
      watchVisual(nil)
      ball, searchAt = nil, 0
      invalidateSnapshotCache()
    end
  end))
  ball, watching, searchAt = findBall(), true, os.clock() + CONFIG.BALL_SEARCH_INTERVAL
  watchVisual(ball)
  return true
end
function GameInfo.getBallSpeedLimits()
  local time = os.clock()
  if time < speedAt then
    return minimumSpeed, maximumSpeed
  end
  speedAt = time + CONFIG.SPEED_REFRESH
  local module = child(child(ts(), "Gameplay"), "GameBall")
  if module ~= gameBallScript then
    gameBallScript, gameBall = module, nil
  end
  if not module then
    return minimumSpeed, maximumSpeed
  end
  if not gameBall then
    gameBall = load(module, "GameBall").GameBall
  end
  if type(gameBall) ~= "table" or type(gameBall.GetBaseSpeed) ~= "function" or type(gameBall.GetMaxSpeed) ~= "function" then
    error("API externa ausente: TS.Gameplay.GameBall.GetBaseSpeed/GetMaxSpeed", 2)
  end
  local low, high = gameBall:GetBaseSpeed(), gameBall:GetMaxSpeed()
  if not finite(low) or not finite(high) or low <= 0 or high <= low then
    error("API externa inválida: GameBall retornou limites de velocidade inválidos", 2)
  end
  minimumSpeed, maximumSpeed = low, high
  return minimumSpeed, maximumSpeed
end
function GameInfo.getDefenseSource()
  GameInfo.getBallSpeedLimits()
  return gameBall
end
function GameInfo.usesSharedLayout() return sharedLayout() end
function GameInfo.getBallFrozen()
  if not ballData or not ballData.Parent then
    ballData = child(world, "BallData")
  end
  if not ballData then
    return nil
  end
  return ballData:GetAttribute("Frozen") == true
end
function GameInfo.getDarkSealEventId() return CONFIG.GAME_IDS.DARK_EVENT end
function GameInfo.createCrateNetwork()
  local root = ts()
  if not root then
    error("API externa ausente: Shared ou TS", 2)
  end
  local folder = root:FindFirstChild("Network") or root:WaitForChild("Network", 10)
  local network = folder and (folder:FindFirstChild("Network") or folder:WaitForChild("Network", 10))
  if not network or not network:IsA("ModuleScript") then
    error("API externa ausente: Network.Network", 2)
  end
  return require(network).Network.new()
end
function GameInfo.spinCrate(network, crate, guard)
  local owned = network:CSendFunction(CONFIG.GAME_IDS.CRATE_CHECK, crate)
  if type(guard) == "function" and not guard() then
    return false
  end
  network:CSendEvent(owned == true and CONFIG.GAME_IDS.CRATE_OWNED or CONFIG.GAME_IDS.CRATE_NEW, crate)
  return true
end
function GameInfo.getManifestRemote() return generatedRemote(CONFIG.GAME_IDS.MANIFEST_REMOTE) end
function GameInfo.getClashStatus(maxDistance)
  local status = { active = false, source = "exodus", reason = "no_parry" }
  local player = players.LocalPlayer
  local at = world:GetAttribute("LastParryAt")
  if not player or not finite(at) then
    return status
  end
  local by, target = world:GetAttribute("LastParryBy"), world:GetAttribute("LastParryTarget")
  local age = world:GetServerTimeNow() - at
  status.lastParryAt, status.age = at, age
  status.maxAge, status.grace = 0.8, 0
  status.maxDistance = finite(maxDistance) and math.max(0, maxDistance) or math.huge
  if not finite(age) or age < 0 or age > status.maxAge then
    status.reason = "expired"
    return status
  end
  local partnerId
  if by == player.UserId then
    partnerId = target
  elseif target == player.UserId then
    partnerId = by
  else
    status.reason = "not_in_pair"
    return status
  end
  if not finite(partnerId) or partnerId <= 0 or partnerId % 1 ~= 0 or partnerId == player.UserId then
    status.reason = "not_in_pair"
    return status
  end
  status.partnerId = partnerId
  local hits = world:GetAttribute("ClashHits")
  if not finite(hits) or hits < 1 then
    status.reason = "no_pair_exchange"
    return status
  end
  local currentTarget = world:GetAttribute("GameBallTarget")
  if finite(currentTarget) and currentTarget ~= player.UserId and currentTarget ~= partnerId then
    status.reason = "third_target"
    return status
  end
  local partner, _, humanoid, other = registry.getParts(partnerId)
  local _, _, _, root = registry.getParts(player.UserId)
  if not root or not other then
    status.reason = "missing_player"
    return status
  end
  if not humanoid or humanoid.Health <= 0 or partner:GetAttribute("Playing") == false then
    status.reason = "player_dead"
    return status
  end
  status.distance = (root.Position - other.Position).Magnitude
  if not finite(status.distance) or status.distance > status.maxDistance then
    status.reason = "distance"
    return status
  end
  status.active, status.reason = true, "clashing"
  return status
end
function GameInfo.IsInClash() return GameInfo.getClashStatus().active end
function GameInfo.getExodusClashContext()
  local status = GameInfo.getClashStatus()
  return status.active and status or nil
end
function GameInfo.getNativeClashContext() return GameInfo.getExodusClashContext() end
function GameInfo.getClashContext(ignoreDistance)
  local player = players.LocalPlayer
  if not player then
    return nil
  end
  local lastAt, by, target = world:GetAttribute("LastParryAt"), world:GetAttribute("LastParryBy"), world:GetAttribute("LastParryTarget")
  if not finite(lastAt) or not finite(by) or not finite(target) then
    return nil
  end
  local partnerId = by == player.UserId and target or (target == player.UserId and by or nil)
  if not partnerId or partnerId <= 0 or partnerId == player.UserId then
    return nil
  end
  local age, currentTarget = world:GetServerTimeNow() - lastAt, GameInfo.getBallTargetAttribute()
  if age < 0 or (age > 1 and (age > 2.5 or currentTarget ~= target)) then
    return nil
  end
  local _, _, _, ownRoot = registry.getParts(player.UserId)
  local _, _, _, partnerRoot = registry.getParts(partnerId)
  if not ownRoot or not partnerRoot then
    return nil
  end
  if ignoreDistance ~= true and (ownRoot.Position - partnerRoot.Position).Magnitude > 35 then
    return nil
  end
  return { partnerId = partnerId, lastParryAt = lastAt, age = age }
end
function GameInfo.getStatus()
  if not snapshotBuilder then
    return { available = false }
  end
  local now = utils.now()
  local value = snapshot(now)
  return {
    schema = utils.apiVersion(),
    clash = GameInfo.getClashStatus(),
    generatedAt = now,
    available = value ~= nil,
    targetId = value and value.targetId or -1,
    targeted = value and value.targeted or false,
    targeting = GameInfo.getTargetSignals(now),
    speed = value and value.speed or 0,
  }
end

-- contract
GameInfo.__contract = {
  access = {
    references = { "getDeflectAbility", "getDashAbility", "getFierceDeflectAbility", "getDarkSealAbility", "getDefenseSource" },
    default = "game.write",
    methods = {
      fireTrainingParry = "combat.execute",
      createCrateNetwork = "game.inventory",
      spinCrate = "game.inventory",
    },
  },
  requires = {
    Profiler = "profiler",
    Utils = "utils",
    PlayerRegistry = "playerregistry",
    Presence = "presence",
    Snapshots = "snapshots",
    BallSync = "ballsync",
    Targeting = "targeting",
  },
  requiresMethods = {
    Profiler = { "begin", "finish", "count" },
    PlayerRegistry = { "getPlayers", "getParts" },
    Presence = { "create" },
    Snapshots = { "create" },
    BallSync = { "create" },
    Targeting = { "create" },
    Utils = {
      "now",
      "apiVersion",
      "getPlayers",
      "getReplicatedStorage",
      "getWorkspace",
      "getRunService",
      "trackGlobal",
      "untrackGlobal",
      "recordError",
    },
  },
  provides = {
    "getParrySignal",
    "getTrainingWindow",
    "isNativeClash",
    "getLastAcceptedDeflectAt",
    "getSyncVersion",
    "teardown",
    "beginEvaluation",
    "endEvaluation",
    "getPlayers",
    "getPlayerParts",
    "getDefenseSource",
    "usesSharedLayout",
    "setup",
    "applyPacket",
    "isTrainingArea",
    "getGameContext",
    "observeTraining",
    "fireTrainingParry",
    "getBall",
    "getBallPosition",
    "getBallVelocity",
    "getRootPosition",
    "getLocalPing",
    "getAveragePing",
    "areAbilitiesEnabled",
    "getAbilityAvailability",
    "getNativeButtonAnimations",
    "observeAbilityMode",
    "getPlayerDistance",
    "getPlayerMotion",
    "getDeflectTargetPrediction",
    "getHaunterEvent",
    "getBallFrozen",
    "getDeflectAbility",
    "getLastDeflectPressAt",
    "getDeflectCallStamp",
    "getAutoSpamDelay",
    "getMinimumSpamInterval",
    "getDashAbility",
    "getLocalDashState",
    "isPlayerDashing",
    "getPlayerDashKind",
    "getFierceDeflectAbility",
    "getDarkSealAbility",
    "getDarkSealEventId",
    "createCrateNetwork",
    "spinCrate",
    "getBallSpeedLimits",
    "getManifestRemote",
    "getClashContext",
    "getNativeClashContext",
    "getClashStatus",
    "IsInClash",
    "getExodusClashContext",
    "getStatus",
    "getSnapshot",
    "getSnapshotAt",
    "getParrySnapshot",
    "getDefenseSnapshot",
    "isSnapshotAfterDeflect",
    "isSnapshotValid",
    "getSyncData",
    "getSyncSequence",
    "decodeBallPacket",
    "getTargetId",
    "getTargetSignals",
    "getParryTargetStatus",
    "getDeflectAttemptAnimationIds",
    "getDeflectAnimationCatalog",
    "getBallTargetAttribute",
    "applySync",
    "installBallWatcher",
    "bindBallSync",
    "startMaintenance",
    "stopMaintenance",
  },
}

return GameInfo
