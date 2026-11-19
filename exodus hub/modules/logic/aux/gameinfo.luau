-- [[ gameinfo ]]

-- module
local GameInfo = {}
local utils, players, world
local ball, searchAt, watching = nil, 0, false
local ballVisualConnection
local abilityScript, abilities, replicatorScript, replicator, gameBallScript, gameBall
local ballSync, targeting, targetCache, targetCacheAt
local sampledBall, sampledPosition, sampledAt, measuredVelocity, movedAt
local ballData, dashAnimation
local minimumSpeed, maximumSpeed, speedAt
local errors = {}
local syncConnection, syncRemote, snapshotConnection, snapshotRemote, maintenance = nil, nil, nil, nil, 0
local pingSamples, pingIndex, pingSum, pingSampleAt, pingRaw = {}, 0, 0, nil, nil
local trainingConnection, trainingRemote, trainingState, trainingSequence = nil, nil, nil, 0
local trainingEventConnection, trainingEventRemote
local trainingZone
local trainingRound, trainingDespawned, trainingServerTime = 0, false, nil
local trainingObservers = {}
local trainingParryAt
local trainingDataModule, trainingData
local snapshotCache, snapshotCacheAt = nil, -math.huge
local presence, presenceConnections, presenceDeath = {}, {}, nil
local presenceHumanoid, lobbyRegion, lobbySearchAt
local updatePresence
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
  snapshotCache, snapshotCacheAt, targetCache, targetCacheAt = nil, -math.huge, nil, -math.huge
end
local function child(parent, name) return parent and parent:FindFirstChild(name) end
local function report(name, message)
  local time = os.clock()
  if errors[name] and time - errors[name] < 2 then return end
  errors[name] = time; local detail = name .. ": " .. tostring(message)
  if utils and type(utils.recordError) == "function" then utils.recordError("GameInfo", detail) else warn("[GameInfo] " .. detail) end
end
local function load(module, name)
  if not module or not module:IsA("ModuleScript") then error("API externa ausente: TS." .. tostring(name), 2) end
  local result = require(module)
  if type(result) ~= "table" then error("API externa inválida: TS." .. tostring(name) .. " não retornou tabela", 2) end
  return result
end
local function storage() return utils and utils.getReplicatedStorage() end
local function ts() return child(storage(), "Shared") or child(storage(), "TS") end
local function sharedLayout() return child(storage(), "Shared") ~= nil end
local function inTrainingArea()
  local player = players and players.LocalPlayer; local character = player and player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not root or not root.Parent then return false end
  local area = trainingZone
  if not area or not area.Parent then area = child(child(child(world, "Training"), "Areas"), "Zone"); trainingZone = area end
  if not area or not area:IsA("BasePart") then return false end
  local localPos = area.CFrame:PointToObjectSpace(root.Position); local half = area.Size / 2
  if math.abs(localPos.X) > half.X or math.abs(localPos.Y) > half.Y or math.abs(localPos.Z) > half.Z then return false end
  local module = child(child(ts(), "Core"), "GameData")
  if module ~= trainingDataModule then trainingDataModule, trainingData = module, nil end
  if module and not trainingData then
    local ok, result = pcall(load, module, "GameData")
    if ok then trainingData = result.GameData end
  end
  local lives = player:GetAttribute("Lives")
  if trainingData and type(trainingData.GetFallback) == "function" then
    local ok, result = pcall(trainingData.GetFallback, trainingData, player, "Lives", 0)
    if ok then lives = result end
  end
  return not finite(lives) or lives <= 0
end
function GameInfo.isTrainingArea() return inTrainingArea() end
function GameInfo.fireTrainingParry()
  if not inTrainingArea() then return false, "fora da arena de treino" end
  local endpoint = child(child(child(storage(), "Training"), "Remotes"), "Block"); local camera = world.CurrentCamera
  if not endpoint or not endpoint:IsA("RemoteEvent") or not camera then return false, "bloqueio de treino indisponível" end
  endpoint:FireServer(camera.CFrame.Position, camera.CFrame.LookVector); return true
end

-- membership
local function inLobby(root)
  if not root then return true end
  local time = os.clock()
  if not lobbyRegion or not lobbyRegion.Parent then
    if not lobbySearchAt or time >= lobbySearchAt then lobbySearchAt = time + 0.5; lobbyRegion = world:FindFirstChild("Lobby Area", true) end
  end
  local function inside(region)
    if not region or not region:IsA("BasePart") then return false end
    local point = region.CFrame:PointToObjectSpace(root.Position); local half = region.Size * 0.5
    return math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y and math.abs(point.Z) <= half.Z
  end
  return inside(lobbyRegion) or inside(child(child(child(world, "Training"), "Areas"), "SafeArea"))
end
local function stopPresence()
  if presenceDeath then presenceDeath:Disconnect(); presenceDeath = nil end
  for _, connection in ipairs(presenceConnections) do
    if utils and type(utils.untrackGlobal) == "function" then utils.untrackGlobal(connection) end
    connection:Disconnect()
  end
  presenceConnections, presenceHumanoid = {}, nil
end
updatePresence = function()
  if not players or not world then return end
  local player = players.LocalPlayer; local character = player and player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  local humanoid = character and type(character.FindFirstChildOfClass) == "function" and character:FindFirstChildOfClass("Humanoid") or nil; local round = world:GetAttribute("MatchStatus") == 6
  local lives = player and player:GetAttribute("Lives"); local playing = player and player:GetAttribute("Playing")
  if humanoid ~= presenceHumanoid then
    if presenceDeath then presenceDeath:Disconnect(); presenceDeath = nil end
    presenceHumanoid = humanoid
    if humanoid and humanoid.Died then
      presenceDeath = humanoid.Died:Connect(function()
        if presenceHumanoid == humanoid and player.Character == character and world:GetAttribute("MatchStatus") == 6 then presence.eliminated, presence.entered = true, false end
      end)
    end
  end
  if presence.round == nil then presence.needsTeleport = not round end
  if not round then
    if presence.round == true then presence.entryProof = false end
    presence.eliminated, presence.entered, presence.needsTeleport = false, false, true
  elseif presence.round == true and presence.entered and presence.character and presence.character ~= character then
    presence.eliminated, presence.entered = true, false
  end
  if root and presence.position and (root.Position - presence.position).Magnitude >= 24 then presence.entryProof = true end
  local alive = humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root.Parent ~= nil
  if round and ((humanoid and humanoid.Health <= 0) or (finite(presence.lives) and presence.lives > 0 and finite(lives) and lives <= 0)) then presence.eliminated = true end
  local candidate = round and alive and finite(lives) and lives > 0 and playing ~= false and not inLobby(root)
  if presence.entered and not candidate then
    if not alive or playing == false or not finite(lives) or lives <= 0 then presence.eliminated = true end
    presence.needsTeleport, presence.entryProof = true, false
  end
  presence.entered = candidate and not presence.eliminated and (not presence.needsTeleport or presence.entryProof == true) or false
  presence.round, presence.character, presence.position, presence.lives = round, character, root and root.Position, lives
end
local function startPresence()
  presence, lobbyRegion, lobbySearchAt = {}, nil, nil; updatePresence()
  local function track(connection)
    presenceConnections[#presenceConnections + 1] = connection
    if type(utils.trackGlobal) == "function" then utils.trackGlobal(connection) end
  end
  if type(world.GetAttributeChangedSignal) == "function" then track(world:GetAttributeChangedSignal("MatchStatus"):Connect(updatePresence)) end
  local runService = type(utils.getRunService) == "function" and utils.getRunService()
  if runService and runService.Heartbeat then
    local elapsed = 0
    track(runService.Heartbeat:Connect(function(dt)
      elapsed += dt
      if elapsed >= 0.1 then elapsed = 0; updatePresence() end
    end))
  end
end

-- abilities
local function getAbilities()
  if abilities and abilityScript and abilityScript.Parent then return abilities end
  local root = ts(); local module = child(child(root, "Abilities"), "ClientAbilities") or child(root, "ClientAbilities")
  if abilityScript ~= module then abilityScript, abilities = module, nil end
  if not module then return nil end
  if not abilities then
    local value = load(module, "ClientAbilities")
    if type(value.Abilities) ~= "table" then error("API externa ausente: TS.ClientAbilities.Abilities", 2) end
    abilities = value.Abilities
  end
  return abilities
end
local function getAbility(index, method)
  local list = getAbilities(); local ability = list and list[index]
  if ability == nil then return nil end
  if type(ability) ~= "table" or type(ability[method]) ~= "function" then error(("API externa ausente: ClientAbilities[%d].%s"):format(index, method), 2) end
  return ability
end
local function getReplicator()
  if replicator and replicatorScript and replicatorScript.Parent then return replicator end
  local root = ts(); local folder = child(child(root, "Gameplay"), "BallReplicator") or child(root, "BallReplicator")
  local module = folder and (folder:IsA("ModuleScript") and folder or child(folder, "BallReplicator"))
  if module ~= replicatorScript then replicatorScript, replicator = module, nil end
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
local function targetId(data) return data and data.TargetPlayerID or -1 end
local function findBall()
  local candidate = world:FindFirstChild("GameBall") or world:FindFirstChild("GameBall", true)
  if candidate and candidate:IsA("BasePart") then return candidate end
  return nil
end
local function getBall()
  if ball and ball.Parent then return ball end
  if watching and os.clock() < searchAt then return nil end
  local previous = ball; ball, searchAt = findBall(), os.clock() + CONFIG.BALL_SEARCH_INTERVAL
  if previous ~= ball then invalidateSnapshotCache() end
  return ball
end
local function disconnect(connection)
  if connection then
    if utils and type(utils.untrackGlobal) == "function" then utils.untrackGlobal(connection) end
    connection:Disconnect()
  end
end

-- synchronization
local function validSyncRemote(instance)
  return typeof(instance) == "Instance" and (instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")) and instance.Parent ~= nil
end
local function disconnectSync()
  if syncConnection then
    if utils then utils.untrackGlobal(syncConnection) end
    syncConnection:Disconnect()
  end
  if snapshotConnection then
    if utils then utils.untrackGlobal(snapshotConnection) end
    snapshotConnection:Disconnect()
  end
  syncConnection, syncRemote, snapshotConnection, snapshotRemote = nil, nil, nil, nil
end
local function findSyncRemote()
  local replicated = storage()
  if not replicated then return nil end
  local remotes = replicated:FindFirstChild("Remotes"); local candidate = remotes and remotes:FindFirstChild("BallSyncData")
  if validSyncRemote(candidate) then return candidate end
  candidate = replicated:FindFirstChild("BallSyncData")
  if validSyncRemote(candidate) then return candidate end
  candidate = replicated:FindFirstChild("BallSyncData", true)
  if validSyncRemote(candidate) then return candidate end
  return nil
end
local function notifyTraining()
  local listeners = table.clone(trainingObservers)
  for _, entry in ipairs(listeners) do
    if entry.Connected then
      local ok, err = pcall(entry.callback)
      if not ok then utils.recordError("Training.onState", err) end
    end
  end
end
function GameInfo.observeTraining(callback)
  assert(type(callback) == "function", "training callback required"); local entry = { Connected = true, callback = callback }
  function entry:Disconnect()
    if not self.Connected then return end
    self.Connected = false; local index = table.find(trainingObservers, self)
    if index then table.remove(trainingObservers, index) end
  end
  trainingObservers[#trainingObservers + 1] = entry; return entry
end
local function resetTrainingBall(despawned)
  trainingRound += 1; trainingState, trainingDespawned, trainingParryAt, trainingServerTime = nil, despawned, nil, nil
  invalidateSnapshotCache()
end
local function bindTrainingSync()
  local remotes = child(child(storage(), "Training"), "Remotes"); local event = child(remotes, "Event")
  if not validSyncRemote(event) then event = nil end
  if trainingEventRemote ~= event or (trainingEventConnection and not trainingEventConnection.Connected) then
    disconnect(trainingEventConnection); trainingEventConnection, trainingEventRemote = nil, event
    resetTrainingBall(false)
  end
  if event and not trainingEventConnection then
    trainingEventConnection = event.OnClientEvent:Connect(function(kind, playerId)
      if kind == "BallSpawn" then resetTrainingBall(false)
      elseif kind == "BallDespawn" or kind == "Kill" then resetTrainingBall(true)
      elseif kind == "Parry" and players.LocalPlayer and playerId == players.LocalPlayer.UserId then trainingParryAt = world:GetServerTimeNow(); invalidateSnapshotCache() end
    end)
    utils.trackGlobal(trainingEventConnection)
  end
  local training = child(remotes, "BallState")
  if not validSyncRemote(training) then training = nil end
  if trainingRemote ~= training or (trainingConnection and not trainingConnection.Connected) then
    disconnect(trainingConnection); trainingConnection, trainingRemote, trainingServerTime = nil, nil, nil
    resetTrainingBall(trainingDespawned)
  end
  if training and not trainingConnection then
    trainingRemote = training
    trainingConnection = training.OnClientEvent:Connect(function(position, velocity, serverTime, goal, target, speed)
      if not finiteVector(position) or not finiteVector(velocity) or not finite(serverTime) then return end
      local receivedAt = os.clock()
      if trainingDespawned or (trainingServerTime and serverTime <= trainingServerTime) then return end
      trainingServerTime = serverTime; trainingSequence = (trainingSequence + 1) % 65536
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

      invalidateSnapshotCache(); notifyTraining()
    end)
    utils.trackGlobal(trainingConnection)
  end
end
function GameInfo.bindBallSync(handler)
  if type(handler) ~= "function" then return false end
  bindTrainingSync(); local candidate = findSyncRemote()
  if not candidate then
    if syncRemote and not validSyncRemote(syncRemote) then disconnectSync() end
    return syncConnection ~= nil and syncConnection.Connected == true
  end
  local replicated = storage(); local remotes = replicated and replicated:FindFirstChild("Remotes")
  local snapshotCandidate = remotes and remotes:FindFirstChild("BallSnapshot")
  if not validSyncRemote(snapshotCandidate) then snapshotCandidate = nil end
  if not (syncConnection and syncConnection.Connected and syncRemote == candidate) then
    disconnectSync(); syncConnection, syncRemote = candidate.OnClientEvent:Connect(handler), candidate
    utils.trackGlobal(syncConnection)
  end
  if snapshotRemote ~= snapshotCandidate or (snapshotConnection and not snapshotConnection.Connected) then
    if snapshotConnection then utils.untrackGlobal(snapshotConnection); snapshotConnection:Disconnect() end
    snapshotConnection, snapshotRemote = nil, nil
  end
  if snapshotCandidate and not snapshotConnection then
    snapshotConnection, snapshotRemote = snapshotCandidate.OnClientEvent:Connect(handler), snapshotCandidate; utils.trackGlobal(snapshotConnection)
  end
  return true
end

-- lifecycle
function GameInfo.startMaintenance(options)
  if type(options) ~= "table" or type(options.isActive) ~= "function" then return false end
  maintenance += 1; local token = maintenance
  task.spawn(function()
    while token == maintenance do
      if not options.isActive() or token ~= maintenance then break end
      local linked = type(options.onBallSync) == "function" and GameInfo.bindBallSync(options.onBallSync)
      if token ~= maintenance then break end
      task.wait(linked and CONFIG.SYNC_CONNECTED_INTERVAL or CONFIG.SYNC_RETRY_INTERVAL)
    end
  end)
  return true
end
function GameInfo.stopMaintenance()
  stopPresence(); maintenance += 1
  disconnectSync(); disconnect(trainingConnection)
  disconnect(trainingEventConnection); trainingConnection, trainingRemote, trainingServerTime = nil, nil, nil
  trainingEventConnection, trainingEventRemote = nil, nil; resetTrainingBall(false)
end
function GameInfo.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then return false, "dependência ausente: Utils" end
  if type(deps.BallSync) ~= "table" or type(deps.BallSync.create) ~= "function" then return false, "dependência ausente: BallSync" end
  if type(deps.Targeting) ~= "table" or type(deps.Targeting.create) ~= "function" then return false, "dependência ausente: Targeting" end
  GameInfo.stopMaintenance(); utils = deps.Utils
  ballSync = deps.BallSync.create({ getReplicator = getReplicator, invalidateSnapshotCache = invalidateSnapshotCache, packetAge = CONFIG.PACKET_AGE })
  targeting = deps.Targeting.create({ storage = storage }); targetCache, targetCacheAt = nil, -math.huge
  players, world = utils.getPlayers(), utils.getWorkspace()
  if not players or not world then return false, "dependência ausente: Players ou Workspace" end
  if ballVisualConnection then disconnect(ballVisualConnection); ballVisualConnection = nil end
  ball, searchAt, watching = nil, 0, false; ballData, dashAnimation = nil, nil
  abilityScript, abilities, replicatorScript, replicator, gameBallScript, gameBall = nil, nil, nil, nil, nil, nil
  sampledBall, sampledPosition, sampledAt, measuredVelocity, movedAt = nil, nil, nil, nil, nil; trainingState, trainingSequence, trainingDataModule, trainingData = nil, 0, nil, nil
  trainingZone = nil; snapshotCache, snapshotCacheAt = nil, -math.huge
  table.clear(dashStateCache); minimumSpeed, maximumSpeed, speedAt = CONFIG.MIN_SPEED, CONFIG.MAX_SPEED, 0
  errors = {}; pingSamples, pingIndex, pingSum, pingSampleAt, pingRaw = {}, 0, 0, nil, nil
  startPresence(); return true
end
function GameInfo.getBall() return getBall() end
function GameInfo.getBallPosition(value) return value.Position end
function GameInfo.getBallVelocity(value) return value.AssemblyLinearVelocity end
function GameInfo.getRootPosition(root) return root.Position end
function GameInfo.getLocalPing() return players.LocalPlayer and players.LocalPlayer:GetNetworkPing() or nil end
function GameInfo.getAveragePing()
  local time = os.clock()
  if pingSampleAt == nil or time < pingSampleAt or time - pingSampleAt >= CONFIG.PING_SAMPLE_INTERVAL then
    pingSampleAt = time; local value = GameInfo.getLocalPing()
    if finite(value) and value >= 0 then
      pingRaw = value
      if #pingSamples < CONFIG.PING_SAMPLE_COUNT then
        pingSamples[#pingSamples + 1] = value
      else
        pingIndex = pingIndex % CONFIG.PING_SAMPLE_COUNT + 1; pingSum -= pingSamples[pingIndex]
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
  updatePresence(); local player = players and players.LocalPlayer
  local placeId = game.PlaceId; local matchStatus = world and world:GetAttribute("MatchStatus")
  local modeId = world and world:GetAttribute("CurGamemode"); local lives = player and player:GetAttribute("Lives")
  local playing = player and player:GetAttribute("Playing"); local afk = player and player:GetAttribute("AFK")
  local roundActive
  if finite(matchStatus) then roundActive = matchStatus == 6 end
  local inMatch = presence.entered == true; local training = inTrainingArea()
  local area = "unknown"
  if placeId == 12979690461 then
    if inMatch then area = "match" elseif training then area = "training" elseif player and finite(lives) then area = "lobby" end
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
  local root = ts(); local module = child(child(root, "UI"), "ButtonAnimations")
  if not module then return nil end
  local value = load(module, "ButtonAnimations"); local animations = value and value.ButtonAnimations
  if type(animations) == "table" and type(animations.Bind) == "function" and type(animations.Unbind) == "function" then return animations end
  return nil
end
function GameInfo.getAbilityAvailability(name)
  local ids = { dark = CONFIG.GAME_IDS.DARK, dash = CONFIG.GAME_IDS.DASH, fierce = CONFIG.GAME_IDS.FIERCE }; local labels = { dark = "Dark Seal", dash = "Dash", fierce = "Fierce Deflect" }
  local id = ids[name]
  if not id then return false, "Habilidade desconhecida." end
  if not GameInfo.areAbilitiesEnabled() then return false, "Esta partida está no modo sem habilidades." end
  local equipped = getAbilities()
  if not equipped or not equipped[id] then return false, "Você precisa equipar " .. labels[name] .. " para usar esta opção." end
  return true
end
function GameInfo.observeAbilityMode(callback)
  return world:GetAttributeChangedSignal("CurGamemode"):Connect(function() callback(GameInfo.areAbilitiesEnabled()) end)
end
local function generatedRemote(id)
  local root = ts(); local remotes = child(child(root, "Network"), "GeneratedNetworkRemotes") or child(root, "GeneratedNetworkRemotes")
  local remote = child(remotes, "RE_" .. tostring(id)); return remote and remote:IsA("RemoteEvent") and remote or nil
end
function GameInfo.getHaunterEvent() return generatedRemote(CONFIG.GAME_IDS.HAUNTER_REMOTE) end
local function playerRoot(id)
  local player = type(id) == "number" and players:GetPlayerByUserId(id); local character = player and player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if root and root.Parent then return root, character end
  return nil
end
function GameInfo.getPlayerMotion(id)
  local root, character = playerRoot(id)
  if not root then return nil end
  return root.Position, root.AssemblyLinearVelocity, character
end
function GameInfo.getDeflectTargetPrediction(id)
  local source = players:GetPlayerByUserId(id); local root = source and source.Character and source.Character:FindFirstChild("HumanoidRootPart")
  if not root then return nil end
  local mode = world:GetAttribute("CurGamemode"); local teams = mode == 1 or mode == 2
  local candidates = {}
  for _, candidate in ipairs(players:GetPlayers()) do
    local position, character = playerRoot(candidate.UserId); local humanoid = character and character:FindFirstChildOfClass("Humanoid")
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
      if candidate:GetAttribute("DarkSealed") == true then return candidate.UserId, 1, 1, "dark_seal" end
      if candidate:GetAttribute("IsCloaked") ~= true then candidates[#candidates + 1] = { player = candidate, root = position } end
    end
  end
  if #candidates == 1 then return candidates[1].player.UserId, 1, 1, "single_candidate" end
  local camera = source:GetAttribute("CamCFrame"); local observed = typeof(camera) == "CFrame"
  if not observed then camera = root.CFrame end
  if typeof(camera) ~= "CFrame" then return nil end
  local origin, look = camera.Position, camera.LookVector
  if (origin - root.Position).Magnitude > 64 then origin = root.Position end
  if not finiteVector(origin) or not finiteVector(look) or look.Magnitude < 0.5 then return nil end
  look = look.Unit; local winner, best, runner = nil, -math.huge, -math.huge
  for _, entry in ipairs(candidates) do
    local candidate, position = entry.player, entry.root; local delta = position.Position - origin
    if delta.Magnitude > 0.001 then
      local score = look:Dot(delta.Unit)
      if score > best then winner, runner, best = candidate.UserId, best, score elseif score > runner then runner = score end
    end
  end
  if winner then return winner, best, best - runner, observed and "camera" or "root" end
  return nil
end
function GameInfo.getPlayerDistance(id)
  local own = players.LocalPlayer; local ownRoot = own and own.Character and own.Character:FindFirstChild("HumanoidRootPart")
  local otherRoot = playerRoot(id)
  if not ownRoot or not ownRoot.Parent or not otherRoot then return nil end
  return (ownRoot.Position - otherRoot.Position).Magnitude
end
function GameInfo.getDeflectAbility() return getAbility(CONFIG.GAME_IDS.DEFLECT, "Deflect") end
function GameInfo.getLastDeflectPressAt()
  local ability = GameInfo.getDeflectAbility()
  if not ability then return nil end
  local pressedAt = ability.LastPressClock
  if finite(pressedAt) and pressedAt > 0 then return pressedAt end
  local latest
  if type(ability.ClickInstances) == "table" then
    for _, click in ipairs(ability.ClickInstances) do
      local remaining = type(click) == "table" and click.Time
      if finite(remaining) and remaining > 0 and remaining <= 1 then latest = latest and math.max(latest, remaining) or remaining end
    end
  end
  return latest and (os.clock() - (1 - latest)) or 0
end
function GameInfo.getMinimumSpamInterval() return CONFIG.SPAM_MIN_INTERVAL end
function GameInfo.getAutoSpamDelay()
  local ability = GameInfo.getDeflectAbility()
  if not ability then return nil end
  local time = os.clock(); local last = ability.LastDeflectCallAt or ability.LastPressClock
  local delay = finite(last) and math.max(0, CONFIG.SPAM_MIN_INTERVAL - (time - last)) or 0; local limit = world:GetAttribute("CPS_LIMIT")
  if not finite(limit) then limit = 50 end
  limit = math.floor(limit)
  if limit <= 0 then return nil end
  local clicks = ability.ClickInstances
  if type(clicks) ~= "table" then return nil end
  if #clicks >= limit then
    local remaining
    for _, click in ipairs(clicks) do
      if type(click) == "table" and finite(click.Time) then remaining = remaining and math.min(remaining, click.Time) or click.Time end
    end
    if not remaining then return nil end
    delay = math.max(delay, remaining > 0 and remaining or 1 / 240)
  end
  return delay
end
function GameInfo.getDashAbility() return getAbility(CONFIG.GAME_IDS.DASH, "Dash") end
function GameInfo.getDeflectAnimationCatalog()
  local animations = child(child(storage(), "Animations"), "Deflect"); local catalog = {}
  if not animations then return catalog end
  local phases = { BlockStart = "start", BlockLoop = "loop", Parry = "parry" }
  for _, animation in ipairs(animations:GetDescendants()) do
    local phase = phases[animation.Name]
    if phase and animation:IsA("Animation") then
      local id = animation.AnimationId:match("[?&]id=(%d+)") or animation.AnimationId:match("%d+")
      if id and (not catalog[id] or phase == "start") then catalog[id] = phase end
    end
  end
  return catalog
end
function GameInfo.getDeflectAttemptAnimationIds()
  local ids = {}
  for id, phase in pairs(GameInfo.getDeflectAnimationCatalog()) do
    if phase ~= "parry" then ids[id] = true end
  end
  return ids
end
function GameInfo.getLocalDashState()
  local ability = GameInfo.getDashAbility()
  if not ability then return false end
  return ability.Dashing == true, tonumber(ability.DashSpeed), tonumber(ability.DashTime)
end
function GameInfo.getPlayerDashKind(player)
  if not player then return "unknown" end
  if player == players.LocalPlayer then
    local list = getAbilities(); local wind = list and list[22]
    if wind and (wind.Dashing == true or wind.Controlling == true) then return "wind", "native" end
    local ability = GameInfo.getDashAbility()
    if ability and ability.Dashing == true and ability.DashSpeed == 120 and ability.DashTime == 0.2 and ability.DashTime2 == nil then return "normal", "native" end
    return "unknown"
  end
  local character = player.Character; local root = character and character:FindFirstChild("HumanoidRootPart")
  if not root then return "unknown" end
  local effect = root:FindFirstChild("WindDash")
  if effect then
    local objects = { effect }
    for _, item in ipairs(effect:GetDescendants()) do
      objects[#objects + 1] = item
    end
    for _, item in ipairs(objects) do
      if (item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail")) and item.Enabled then return "wind", "effect" end
    end
  end
  local signal = character:GetAttribute("IsDashing")
  if signal ~= true and signal ~= 1 and signal ~= "true" then return "unknown" end
  if root.AssemblyLinearVelocity.Magnitude > 140 then return "wind", "speed" end
  return "normal", "shared"
end
function GameInfo.isPlayerDashing(player)
  if not player then return false end
  if player == players.LocalPlayer then local ability = GameInfo.getDashAbility(); return ability ~= nil and ability.Dashing == true end
  local character = player.Character; local cached = dashStateCache[player]
  local time = os.clock()
  if cached and cached.character == character and time >= cached.at and time - cached.at < CONFIG.DASH_STATE_CACHE_INTERVAL then return cached.value end
  local function finish(value)
    cached = cached or {}; cached.character, cached.at, cached.value = character, time, value
    dashStateCache[player] = cached; return value
  end
  if not character or not character.Parent then return finish(false) end
  if character:GetAttribute("IsDashing") == true then return finish(true) end
  local humanoid = character:FindFirstChildOfClass("Humanoid"); local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
  if not dashAnimation or not dashAnimation.Parent then
    local replicated = storage(); local animations = replicated and replicated:FindFirstChild("Animations")
    local movement = animations and animations:FindFirstChild("Movement"); dashAnimation = movement and movement:FindFirstChild("Dash")
  end
  if not animator or not dashAnimation or not dashAnimation:IsA("Animation") or dashAnimation.AnimationId == "" then return finish(false) end
  for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
    local animation = track.Animation
    if track.IsPlaying and animation and animation.AnimationId == dashAnimation.AnimationId then return finish(true) end
  end
  return finish(false)
end
function GameInfo.getFierceDeflectAbility() return getAbility(CONFIG.GAME_IDS.FIERCE, "ActivateAndBlock") end
function GameInfo.getDarkSealAbility() return getAbility(CONFIG.GAME_IDS.DARK, "SendEvent") end
function GameInfo.getSyncData() return syncData() end
local function syncSequence(current, provider) return ballSync.getSequence(current, provider) end
function GameInfo.getSyncSequence() return syncSequence(syncData(), getReplicator()) end
function GameInfo.applyPacket(value) return ballSync.applyPacket(value) end
function GameInfo.decodeBallPacket(value) return ballSync.decodeBallPacket(value) end
local function resolveTarget(time, provider, sync, currentBall)
  time = finite(time) and time or utils.now()
  if targetCache and time >= targetCacheAt and time - targetCacheAt < CONFIG.SNAPSHOT_CACHE_INTERVAL then return targetCache end
  if provider == nil then provider = getReplicator() end
  if sync == nil then sync = syncData(provider or false) end
  if currentBall == nil then currentBall = getBall() end
  local receivedAt = ballSync.getReceivedAt(); local fresh = receivedAt > 0 and time >= receivedAt and time - receivedAt <= CONFIG.PACKET_AGE
  local serverNow = type(world.GetServerTimeNow) == "function" and world:GetServerTimeNow() or nil; local matchStatus = world:GetAttribute("MatchStatus")
  local report = targeting.resolve({
    player = players.LocalPlayer,
    players = players,
    world = world,
    ball = currentBall,
    sync = sync,
    syncFresh = fresh,
    provider = provider,
    serverNow = serverNow,
    sequence = syncSequence(sync, provider),
    maxAge = CONFIG.PACKET_AGE,
    active = not finite(matchStatus) or matchStatus == 6,
  })
  targetCache, targetCacheAt = report, time; return report
end
function GameInfo.getParryTargetStatus(time)
  targetCache, targetCacheAt = nil, -math.huge; return resolveTarget(time)
end
function GameInfo.getTargetSignals(time)
  if inTrainingArea() then
    local id = trainingState and trainingState.goal; local valid = finite(id) and id > 0
    return {
      mode = "training",
      targetId = valid and id or -1,
      targeted = valid and players.LocalPlayer ~= nil and id == players.LocalPlayer.UserId,
      known = valid,
      signals = {},
    }
  end
  local report = resolveTarget(time); local copy = table.clone(report)
  copy.positive, copy.signals = table.clone(report.positive), {}
  for index, signal in ipairs(report.signals) do
    copy.signals[index] = table.clone(signal)
  end
  return copy
end
function GameInfo.getTargetId()
  if inTrainingArea() then return trainingState and trainingState.goal or -1 end
  return resolveTarget().targetId
end

-- snapshots
local function snapshot(time)
  time = finite(time) and time or utils.now()
  if
    snapshotCache
    and snapshotCache.ball
    and snapshotCache.ball.Parent
    and time >= snapshotCacheAt
    and time - snapshotCacheAt < CONFIG.SNAPSHOT_CACHE_INTERVAL
  then
    return snapshotCache
  end
  if inTrainingArea() then
    local sample = trainingState; local model = child(child(child(world, "Training"), "TrainingClient"), "TrainingBall")
    if not sample or time < sample.receivedAt or time - sample.receivedAt > 0.6 or not model or not model:IsA("BasePart") or not model.Parent then return nil end
    local age = math.clamp(world:GetServerTimeNow() - sample.serverTime, 0, 0.25); local target = finite(sample.goal) and sample.goal > 0 and sample.goal or -1
    local result = {
      schema = 2,
      mode = "training",
      ball = model,
      position = sample.position + sample.velocity * age,
      velocity = sample.velocity,
      speed = sample.velocity.Magnitude,
      syncSpeed = sample.speed,
      targetId = target,
      targeted = players.LocalPlayer ~= nil and target == players.LocalPlayer.UserId,
      targetUncertain = false,
      teleported = false,
      locked = false,
      grace = false,
      syncAt = sample.receivedAt,
      serverTime = sample.serverTime,
      syncSequence = sample.sequence,
      trainingRound = sample.round,
      trainingParryAt = trainingParryAt,
    }

    snapshotCache, snapshotCacheAt = result, time; return result
  end
  local currentBall = getBall()
  if not currentBall then return nil end
  local provider = getReplicator(); local position, velocity, sync = currentBall.Position, currentBall.AssemblyLinearVelocity, syncData(provider or false)
  local targetReport = resolveTarget(time, provider, sync, currentBall); local exchangeTarget = targetId(sync)
  local syncReceivedAt = ballSync.getReceivedAt(); local syncFresh = syncReceivedAt > 0 and time >= syncReceivedAt and time - syncReceivedAt <= CONFIG.PACKET_AGE
  if not syncFresh then sync = nil; syncReceivedAt = nil end
  local target = targetReport.targetId; local frozen = GameInfo.getBallFrozen() == true
  if sampledBall ~= currentBall or (sync and sync.Teleported == true) then
    sampledBall, sampledPosition, sampledAt, measuredVelocity, movedAt = currentBall, position, time, Vector3.zero, nil
  elseif sampledPosition and sampledAt and time - sampledAt >= CONFIG.SAMPLE_INTERVAL then
    local elapsed = time - sampledAt; local displacement = position - sampledPosition
    if displacement.Magnitude > 0.001 then
      local measured, expected = displacement / elapsed, sync and tonumber(sync.Speed)
      if elapsed <= CONFIG.SAMPLE_MAX_GAP and (not expected or expected <= 0 or measured.Magnitude <= expected * 2.5 + 30) then measuredVelocity, movedAt = measured, time
      else measuredVelocity, movedAt = Vector3.zero, nil end
    elseif movedAt and time - movedAt > 0.1 then
      measuredVelocity = Vector3.zero
    end
    sampledPosition, sampledAt = position, time
  end
  if typeof(velocity) ~= "Vector3" or velocity.Magnitude < 0.1 then velocity = measuredVelocity or Vector3.zero end
  local result = {
    schema = 2,
    generatedAt = time,
    valid = true,
    ball = currentBall,
    ballValid = true,
    position = position,
    velocity = velocity,
    speed = velocity.Magnitude,
    syncSpeed = sync and sync.Speed or nil,
    realPosition = sync and sync.RealPosition or nil,
    syncDirection = sync and sync.ForcedDirection or nil,
    syncAcceleration = sync and sync.Accel or nil,
    syncMaxSpeed = sync and sync.MaxSpeed or nil,
    targetId = target,
    targeted = players.LocalPlayer ~= nil and target == players.LocalPlayer.UserId,
    targetSource = targetReport.source or "unavailable",
    targetSignals = targetReport,
    exchangeTargetId = exchangeTarget,
    targetUncertain = not targetReport.known,
    teleported = sync and sync.Teleported == true or false,
    locked = sync and sync.Locked == true or false,
    ballCanMove = not frozen and not (sync and sync.Locked == true),
    frozen = frozen,
    grace = sync and sync.Grace == true or false,
    oldGrace = sync and sync.OldGrace == true or false,
    syncAt = syncReceivedAt,
    serverTime = sync and sync.ServerTime or nil,
    syncSequence = syncSequence(sync, provider),
  }

  snapshotCache, snapshotCacheAt = result, time; return result
end

-- public-api
function GameInfo.getSnapshot(_, time) return snapshot(time) end
function GameInfo.getSnapshotAt(time) return snapshot(time) end
function GameInfo.getParrySnapshot(time)
  local value = snapshot(time)
  if not value or value.mode == "training" or not value.targeted or value.ballCanMove == false or value.teleported or value.locked or value.targetUncertain then return value end
  if value.parrySampled then return value.parrySnapshot or value end
  value.parrySampled = true; local provider = getReplicator()
  if not provider or type(provider.SimulateFrom) ~= "function" or not world then return value end
  local history = provider.history; local latest = type(history) == "table" and history[#history]
  local sync = syncData(provider)
  local sample
  if type(latest) == "table" and provider.lastSeq == value.syncSequence and latest.targetId == value.targetId then
    sample = latest
  elseif sync and finite(sync.ServerTime) and finiteVector(sync.RealPosition) and finiteVector(sync.ForcedDirection) then
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
  if not sample or sample.targetId ~= value.targetId or not finite(sample.serverTime) or not finiteVector(sample.position) then return value end
  local serverNow = world:GetServerTimeNow(); local age = serverNow - sample.serverTime
  if not finite(age) or age < -0.02 or age > 0.25 then return value end
  local target = playerRoot(value.targetId)
  if not target then return value end
  local dt = 1 / 240
  local ok, position, nextPosition = pcall(
    function() return provider:SimulateFrom(sample, math.max(age, 0), target.Position), provider:SimulateFrom(sample, math.max(age, 0) + dt, target.Position) end
  )
  if not ok or not finiteVector(position) or not finiteVector(nextPosition) then return value end
  local predicted = table.clone(value); predicted.visualPosition, predicted.visualVelocity = value.position, value.velocity
  predicted.position, predicted.velocity = position, (nextPosition - position) / dt; predicted.speed = predicted.velocity.Magnitude
  predicted.predicted, predicted.predictionAge, predicted.predictionSource = true, math.max(age, 0), "replicator_simulation"; value.parrySnapshot = predicted
  return predicted
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
function GameInfo.applySync(value) return ballSync.applySync(value) end
function GameInfo.installBallWatcher(track, onTargetChanged)
  if type(track) ~= "function" then return false, "trackConnection invalido" end
  local function targetChanged()
    invalidateSnapshotCache()
    if type(onTargetChanged) == "function" then onTargetChanged({ Source = "target" }) end
  end
  local function watchVisual(item)
    if ballVisualConnection then disconnect(ballVisualConnection); ballVisualConnection = nil end
    if item then ballVisualConnection = item:GetPropertyChangedSignal("Color"):Connect(targetChanged); track(ballVisualConnection) end
  end
  track(world:GetAttributeChangedSignal("GameBallTarget"):Connect(targetChanged))
  track((world.DescendantAdded or world.ChildAdded):Connect(function(item)
    if item.Name == "GameBall" and item:IsA("BasePart") and ball ~= item then
      ball = item; watchVisual(item)
      invalidateSnapshotCache()
    end
  end))
  track((world.DescendantRemoving or world.ChildRemoved):Connect(function(item)
    if ball == item then
      watchVisual(nil); ball, searchAt = nil, 0
      invalidateSnapshotCache()
    end
  end))
  ball, watching, searchAt = findBall(), true, os.clock() + CONFIG.BALL_SEARCH_INTERVAL; watchVisual(ball)
  return true
end
function GameInfo.getBallSpeedLimits()
  local time = os.clock()
  if time < speedAt then return minimumSpeed, maximumSpeed end
  speedAt = time + CONFIG.SPEED_REFRESH; local module = child(child(ts(), "Gameplay"), "GameBall")
  if module ~= gameBallScript then gameBallScript, gameBall = module, nil end
  if not module then return minimumSpeed, maximumSpeed end
  if not gameBall then gameBall = load(module, "GameBall").GameBall end
  if type(gameBall) ~= "table" or type(gameBall.GetBaseSpeed) ~= "function" or type(gameBall.GetMaxSpeed) ~= "function" then
    error("API externa ausente: TS.Gameplay.GameBall.GetBaseSpeed/GetMaxSpeed", 2)
  end
  local low, high = gameBall:GetBaseSpeed(), gameBall:GetMaxSpeed()
  if not finite(low) or not finite(high) or low <= 0 or high <= low then error("API externa inválida: GameBall retornou limites de velocidade inválidos", 2) end
  minimumSpeed, maximumSpeed = low, high; return minimumSpeed, maximumSpeed
end
function GameInfo.getDefenseSource()
  GameInfo.getBallSpeedLimits(); return gameBall
end
function GameInfo.usesSharedLayout() return sharedLayout() end
function GameInfo.getBallFrozen()
  if not ballData or not ballData.Parent then ballData = child(world, "BallData") end
  if not ballData then return nil end
  return ballData:GetAttribute("Frozen") == true
end
function GameInfo.getDarkSealEventId() return CONFIG.GAME_IDS.DARK_EVENT end
function GameInfo.createCrateNetwork()
  local root = ts()
  if not root then error("API externa ausente: Shared ou TS", 2) end
  local folder = root:FindFirstChild("Network") or root:WaitForChild("Network", 10); local network = folder and (folder:FindFirstChild("Network") or folder:WaitForChild("Network", 10))
  if not network or not network:IsA("ModuleScript") then error("API externa ausente: Network.Network", 2) end
  return require(network).Network.new()
end
function GameInfo.spinCrate(network, crate, guard)
  local owned = network:CSendFunction(CONFIG.GAME_IDS.CRATE_CHECK, crate)
  if type(guard) == "function" and not guard() then return false end
  network:CSendEvent(owned == true and CONFIG.GAME_IDS.CRATE_OWNED or CONFIG.GAME_IDS.CRATE_NEW, crate); return true
end
function GameInfo.getManifestRemote() return generatedRemote(CONFIG.GAME_IDS.MANIFEST_REMOTE) end
function GameInfo.getClashContext(ignoreDistance)
  local player = players.LocalPlayer
  if not player then return nil end
  local lastAt, by, target = world:GetAttribute("LastParryAt"), world:GetAttribute("LastParryBy"), world:GetAttribute("LastParryTarget")
  if not finite(lastAt) or not finite(by) or not finite(target) then return nil end
  local partnerId = by == player.UserId and target or (target == player.UserId and by or nil)
  if not partnerId or partnerId <= 0 or partnerId == player.UserId then return nil end
  local age, currentTarget = world:GetServerTimeNow() - lastAt, GameInfo.getBallTargetAttribute()
  if age < 0 or (age > 1 and (age > 2.5 or currentTarget ~= target)) then return nil end
  local partner = players:GetPlayerByUserId(partnerId); local ownRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  local partnerRoot = partner and partner.Character and partner.Character:FindFirstChild("HumanoidRootPart")
  if not ownRoot or not partnerRoot then return nil end
  if ignoreDistance ~= true and (ownRoot.Position - partnerRoot.Position).Magnitude > 35 then return nil end
  return { partnerId = partnerId, lastParryAt = lastAt, age = age }
end
function GameInfo.getStatus()
  local now = utils.now(); local value = snapshot(now)
  return {
    schema = utils.apiVersion(),
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
  requires = {
    Utils = "utils",
    BallSync = "ballsync",
    Targeting = "targeting",
  },
  requiresMethods = {
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
    "getStatus",
    "getSnapshot",
    "getSnapshotAt",
    "getParrySnapshot",
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
