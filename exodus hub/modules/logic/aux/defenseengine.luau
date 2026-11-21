-- [[ defenseengine ]]

-- module
local DefenseEngine = {}
function DefenseEngine.setup() return true end
function DefenseEngine.create(deps)
  assert(type(deps) == "table" and type(deps.canAct) == "function", "política do AP ausente"); local Players = game:GetService("Players")
  local ReplicatedStorage = game:GetService("ReplicatedStorage"); local RunService = game:GetService("RunService")
  local UserInputService = game:GetService("UserInputService"); local player = Players.LocalPlayer
  local running = true; local connections = {}
  local totalCalls, trainingPulse = 0, nil
  local replicator, originalApplySnapshot, wrappedApplySnapshot
  local control = {}; local telemetry = {}
  local function publish(values)
    if values.mode and telemetry.mode ~= values.mode then table.clear(telemetry) end
    for key, value in pairs(values) do
      telemetry[key] = value
    end
    if deps.onState then deps.onState(telemetry) end
  end
  control.getSnapshot = function() return telemetry end
  local function stop()
    running = false
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
    table.clear(connections)
    if wrappedApplySnapshot and replicator and replicator.ApplySnapshot == wrappedApplySnapshot then replicator.ApplySnapshot = originalApplySnapshot end
  end
  control.stop = stop
  local function installTraining(gate, recordOverlayCall)
    local seenGateVersion = gate.version
    local CONFIG = {
      MIN_SPEED = 16,
      MAX_SPEED = 1000,
      MIN_RADIUS = 8.5,
      MAX_RADIUS = 16,
      SLOW_WINDOW = 0.5,
      FAST_WINDOW = 0.3,
      WINDOW_FACTOR = 0.45,
      MAX_FACTOR = 0.85,
      FAST_RETURN = 0.1,
      SLOW_RETURN = 0.9,
      CADENCE_EXPIRY = 1.5,
      FACTOR_RELEASE = 0.25,
      MAX_SAMPLE_AGE = 0.25,
      TRAINING_MAX_AGE = 0.6,
      VISUAL_MAX_AGE = 0.1,
      UI_INTERVAL = 0.1,
      NATIVE_INTERVAL = 0.008,
      TRAINING_INTERVAL = 0.03,
    }

    local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
    local function vector(v) return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
    local function id(v) return finite(v) and v > 0 and v % 1 == 0 end
    local function child(p, name) return p and p:FindFirstChild(name) end
    local function load(module)
      if not module or not module:IsA("ModuleScript") then return nil end
      local ok, value = pcall(require, module)
      if ok and type(value) == "table" then return value end
      warn("[DefenseEngine] Falha ao carregar " .. module.Name .. ": " .. tostring(value))
    end
    local function track(c)
      connections[#connections + 1] = c; return c
    end
    local replicator, client, gameBall, matchEnum
    local shared = child(ReplicatedStorage, "Shared") or child(ReplicatedStorage, "TS"); local dataExport = load(child(child(shared, "Core"), "GameData"))
    local gameData = dataExport and dataExport.GameData; local trainingRoot = child(ReplicatedStorage, "Training")
    local trainingShared = load(child(trainingRoot, "TrainingShared"))
    if not trainingShared then return end
    local low, high = trainingShared.BaseSpeed or 16, trainingShared.MaxSpeed or 600; local userId = player.UserId
    local character, root, humanoid, ball, trainingBall, playerMark, trainingTrail, targetTrail, normalTrail
    local ballScanned, markScanned = false, false; local mode, trainingSample, latestSample, latestAt, lastSequence = nil, nil, nil, nil, nil
    local trainingRemotes, trainingBlock, trainingStateRemote, trainingEventRemote
    local trainingStateConnection, trainingEventConnection
    local trainingParryFloor
    local trainingEnded, trainingFloor, trainingTime = false, -math.huge, nil; local ping, range, pingAt, maintenanceAt = nil, CONFIG.MIN_RADIUS, -math.huge, -math.huge
    local frame, spent, sending, episodeStart, cutoff = 0, false, false, nil, -math.huge; local slots = {}
    local signalSerial, latestOrder, generation = 0, 0, 0; local episodeStrong = false
    local networkFloor = -math.huge; local lastOwnAt, partner, returnInterval, factorAt = nil, nil, nil, os.clock()
    local activeFactor, wasTargeted = CONFIG.WINDOW_FACTOR, false
    local physicsCache, visualPosition, visualAt, visualVelocity
    local callTimes, firstCall, lastCall, peakCount, lastAttempt = {}, 1, 0, 0, -math.huge; local callModes = {}
    local evaluate, lastError
    local function report(err)
      if err ~= lastError then lastError = err; warn("[DefenseEngine] " .. tostring(err)) end
    end
    local function samplePing()
      local ok, v = pcall(player.GetNetworkPing, player); ping = ok and finite(v) and v >= 0 and v or nil
    end
    local function dataAttribute(owner, name, fallback)
      if gameData and type(gameData.GetFallback) == "function" then
        local ok, v = pcall(gameData.GetFallback, gameData, owner, name, fallback)
        if ok then return v end
      end
      local v = owner:GetAttribute(name); return v == nil and fallback or v
    end
    local function resetCycle()
      episodeStrong = false; trainingParryFloor = nil
      generation = generation + 1; signalSerial, latestOrder = 0, 0
      lastAttempt = -math.huge; networkFloor = -math.huge
      table.clear(slots); spent, episodeStart, cutoff, wasTargeted = false, nil, -math.huge, false
      lastOwnAt, partner, returnInterval = nil, nil, nil; activeFactor, factorAt, physicsCache = CONFIG.WINDOW_FACTOR, os.clock(), nil
      visualPosition, visualAt, visualVelocity = nil, nil, nil
    end
    local function put(name, value, now, weak, serverTime)
      local slot = slots[name]
      if not slot then slot = { value = nil, entry = -math.huge }; slots[name] = slot end
      if type(value) ~= "boolean" then
        slot.pending = nil; slot.at = -math.huge
        return
      end
      if weak then
        if slot.pending ~= value then
          signalSerial = signalSerial + 1; slot.pending, slot.frame, slot.count, slot.pendingOrder = value, frame, 1, signalSerial
          return
        end
        if slot.frame ~= frame then slot.frame, slot.count = frame, slot.count + 1 end
        if slot.count < 2 then return end
      end
      slot.at = now
      if value == slot.value then return end
      local previousValue, previousEntry = slot.value, slot.entry; signalSerial = signalSerial + 1
      slot.value, slot.entry = value, (weak and value == true) and slot.pendingOrder or signalSerial
      slot.serverTime = finite(serverTime) and serverTime or workspace:GetServerTimeNow() - (ping or 0) - 0.02; local canRearm = not (weak and episodeStrong)
      if weak and value == false and canRearm then
        for source, other in pairs(slots) do
          local visual = source == "color" or source == "mark" or source == "trail"
          local lifetime = source == "attribute" and math.huge or (source == "goal" and CONFIG.TRAINING_MAX_AGE or CONFIG.MAX_SAMPLE_AGE)
          if not visual and other.value == true and other.entry >= cutoff and now >= other.at and now - other.at <= lifetime then canRearm = false; break end
        end
      end
      if canRearm and value == false and previousValue == true and episodeStart and previousEntry >= episodeStart then
        cutoff, spent, episodeStart, wasTargeted, physicsCache = signalSerial, false, nil, false, nil; episodeStrong = false
        networkFloor = math.max(networkFloor, slot.serverTime)
      end
    end
    local function resolve(now)
      local selected, entry
      for name, slot in pairs(slots) do
        local lifetime = (name == "color" or name == "mark" or name == "trail") and CONFIG.VISUAL_MAX_AGE or CONFIG.MAX_SAMPLE_AGE
        if name == "attribute" then lifetime = math.huge elseif name == "goal" then lifetime = CONFIG.TRAINING_MAX_AGE end
        if slot.value == true and slot.entry >= cutoff and now >= slot.at and now - slot.at <= lifetime then
          if name ~= "color" and name ~= "mark" and name ~= "trail" then episodeStrong = true end
          if not entry or slot.entry < entry then selected, entry = name, slot.entry end
        end
      end
      if not selected then return false end
      if not episodeStart then episodeStart = entry; networkFloor = math.max(networkFloor, slots[selected].serverTime) end
      if not wasTargeted then
        if lastOwnAt then local elapsed = now - lastOwnAt; returnInterval = elapsed > 0 and elapsed <= CONFIG.CADENCE_EXPIRY and elapsed or nil end
        lastOwnAt, wasTargeted = now, true
      end
      return true
    end
    local function targetState(target)
      if id(target) then return target == userId end
      return nil
    end
    local function refreshAttribute()
      if mode ~= "match" then return end
      local target = workspace:GetAttribute("GameBallTarget"); put("attribute", targetState(target), os.clock(), false)
      if id(target) and target ~= userId then
        if partner and partner ~= target then returnInterval, lastOwnAt = nil, nil end
        partner = target
      end
    end
    local function refreshRange()
      local v = player:GetAttribute("DeflectRange"); range = finite(v) and math.clamp(v, CONFIG.MIN_RADIUS, CONFIG.MAX_RADIUS) or CONFIG.MIN_RADIUS
    end
    local function cacheParts()
      local v
      if not ball or not ball.Parent then
        v = workspace:FindFirstChild("GameBall")
        if not v and not ballScanned then v = workspace:FindFirstChild("GameBall", true) end
        ballScanned = true; ball = v and v:IsA("BasePart") and v or nil
      end
      local training = child(workspace, "Training"); v = child(child(training, "TrainingClient"), "TrainingBall")
      trainingBall = v and v:IsA("BasePart") and v or nil; playerMark = child(character, "PlayerBallHighlight")
        or (playerMark and playerMark.Parent and playerMark)
        or ReplicatedStorage:FindFirstChild("PlayerBallHighlight", true)
      local trails = child(trainingBall, "Trails"); trainingTrail, targetTrail, normalTrail = child(trails, "BallTrail"), child(trails, "BallTrailTarget"), child(trails, "BallTrail2")
    end
    local function bindCharacter(value)
      character = value; root = child(value, "HumanoidRootPart")
      humanoid = value and value:FindFirstChildOfClass("Humanoid"); mode = nil
      resetCycle(); cacheParts()
    end
    local function isTraining()
      if not root or not trainingShared or type(trainingShared.InZone) ~= "function" then return false end
      if (tonumber(dataAttribute(player, "Lives", 0)) or 0) > 0 then return false end
      local ok, inside = pcall(trainingShared.InZone, root.Position); return ok and inside == true
    end
    local function selectMode()
      if seenGateVersion ~= gate.version then seenGateVersion = gate.version; resetCycle() end
      local nextMode = isTraining() and "training" or "match"
      if mode ~= nextMode then
        mode = nextMode; resetCycle()
        if mode == "match" then refreshAttribute() end
      end
    end
    local function packetSignals(now)
      if mode ~= "match" or not replicator then return end
      if not latestAt or now - latestAt > CONFIG.MAX_SAMPLE_AGE then return end
      local sample = latestSample
      if not sample or sample.serverTime < networkFloor then return end
      local target, highlight = sample.targetId, sample.highlightId; put("packet", targetState(target), latestAt, false, sample.serverTime)
      put("highlightId", targetState(highlight), latestAt, false, sample.serverTime)
      if id(target) and type(replicator.IsLocalTarget) == "function" then
        local ok, yes = pcall(replicator.IsLocalTarget, replicator)
        if ok and type(yes) == "boolean" then put("provider", yes, latestAt, false, sample.serverTime) end
      end
    end
    local red = Color3.fromRGB(202, 56, 30); local gray = Color3.fromRGB(153, 153, 153)
    local function sameColor(a, b)
      return typeof(a) == "Color3" and typeof(b) == "Color3" and math.abs(a.R - b.R) < 0.005 and math.abs(a.G - b.G) < 0.005 and math.abs(a.B - b.B) < 0.005
    end
    local function sequenceEqual(a, b)
      if typeof(a) ~= "ColorSequence" or typeof(b) ~= "ColorSequence" then return false end
      local aa, bb = a.Keypoints, b.Keypoints
      if #aa ~= #bb then return false end
      for index, point in ipairs(aa) do
        if math.abs(point.Time - bb[index].Time) > 0.001 or not sameColor(point.Value, bb[index].Value) then return false end
      end
      return true
    end
    local function visualSignals(now)
      local currentBall = mode == "training" and trainingBall or ball; local visible = currentBall and currentBall.Parent and currentBall.Transparency < 1 and currentBall.LocalTransparencyModifier < 1
      local color
      if visible then
        local normal = currentBall:GetAttribute("SkinNormalColor")
        if not sameColor(normal, red) then
          if sameColor(currentBall.Color, red) then color = true elseif sameColor(currentBall.Color, typeof(normal) == "Color3" and normal or gray) then color = false end
        end
        local position = currentBall.Position
        if vector(position) then
          if visualPosition and visualAt and now > visualAt then
            local velocity = (position - visualPosition) / (now - visualAt); visualVelocity = vector(velocity) and velocity.Magnitude <= CONFIG.MAX_SPEED * 1.5 and velocity or nil
          end
          visualPosition, visualAt = position, now
        end
      end
      put("color", color, now, true)
      if mode == "match" then
        playerMark = child(character, "PlayerBallHighlight") or playerMark; local mark = playerMark
        local targeted
        if mark and mark:IsA("Highlight") and mark.Parent then targeted = mark.Enabled == true and mark.Parent == character end
        put("mark", targeted, now, true)
      else
        local trail
        if visible and trainingTrail and targetTrail and normalTrail and trainingTrail.Enabled then
          local ownColor, normalColor = targetTrail.Color, normalTrail.Color
          if not sequenceEqual(ownColor, normalColor) then
            if sequenceEqual(trainingTrail.Color, ownColor) then trail = true elseif sequenceEqual(trainingTrail.Color, normalColor) then trail = false end
          end
        end
        put("trail", trail, now, true)
      end
    end
    local function recordCall(now, calledMode)
      recordOverlayCall(now, "training")
      while firstCall <= lastCall and callTimes[firstCall] <= now - 1 + 0.000001 do
        callTimes[firstCall], callModes[firstCall] = nil, nil; firstCall = firstCall + 1
      end
      if firstCall > lastCall then
        firstCall, lastCall = 1, 0
      elseif firstCall > 128 then
        local count = lastCall - firstCall + 1; table.move(callTimes, firstCall, lastCall, 1)
        table.move(callModes, firstCall, lastCall, 1)
        for index = count + 1, lastCall do
          callTimes[index], callModes[index] = nil, nil
        end
        firstCall, lastCall = 1, count
      end
      lastCall = lastCall + 1; callTimes[lastCall], callModes[lastCall] = now, calledMode
      peakCount = math.max(peakCount, lastCall - firstCall + 1)
    end
    local function countCalls(now, filterMode)
      local count = 0
      for index = firstCall, lastCall do
        if callTimes[index] > now - 1 + 0.000001 and callModes[index] == filterMode then count = count + 1 end
      end
      return count
    end
    local function updateUI() end
    local function adaptFactor(now, tti, closing, speed)
      local pressure = 0
      if returnInterval and lastOwnAt and now - lastOwnAt <= math.min(CONFIG.CADENCE_EXPIRY, math.max(CONFIG.FAST_RETURN, returnInterval) * 2) then
        pressure = 1 - math.clamp((returnInterval - CONFIG.FAST_RETURN) / (CONFIG.SLOW_RETURN - CONFIG.FAST_RETURN), 0, 1)
      end
      local budget = (ping or 0) + 1 / 60
      if finite(tti) then pressure = math.max(pressure, math.clamp((budget - tti) / math.max(budget, 0.001), 0, 1)) end
      pressure = math.max(pressure, math.clamp(closing / math.max(speed, 1) - 1, 0, 1)); local desired = CONFIG.WINDOW_FACTOR + (CONFIG.MAX_FACTOR - CONFIG.WINDOW_FACTOR) * pressure
      if desired >= activeFactor then activeFactor = desired else activeFactor = desired + (activeFactor - desired) * math.exp(-math.max(0, now - factorAt) / CONFIG.FACTOR_RELEASE) end
      activeFactor, factorAt = math.clamp(activeFactor, CONFIG.WINDOW_FACTOR, CONFIG.MAX_FACTOR), now; return activeFactor
    end
    local function motion(now, own)
      if mode == "training" then
        local sample = trainingSample
        if trainingEnded or not sample or now - sample.receivedAt > CONFIG.TRAINING_MAX_AGE then return end
        local age = workspace:GetServerTimeNow() - sample.serverTime
        if not finite(age) or age < -0.02 or age > CONFIG.TRAINING_MAX_AGE then return end
        return sample.position + sample.velocity * math.clamp(age, 0, CONFIG.MAX_SAMPLE_AGE), sample.velocity, sample.speed
      end
      local sample = latestSample
      if
        sample
        and latestAt
        and now - latestAt <= CONFIG.MAX_SAMPLE_AGE
        and sample.targetId == userId
        and latestOrder >= cutoff
        and sample.serverTime >= networkFloor
      then
        local age = workspace:GetServerTimeNow() - sample.serverTime
        if not finite(age) or age < -0.02 or age > CONFIG.MAX_SAMPLE_AGE or not vector(sample.position) then return end
        local speed = sample.speed
        if not finite(speed) or speed < CONFIG.MIN_SPEED or speed > CONFIG.MAX_SPEED or sample.locked == true then return end
        local offset = sample.position - own; local outer = range + CONFIG.MAX_SPEED * (math.max(age, 0) + CONFIG.SLOW_WINDOW * CONFIG.MAX_FACTOR + (ping or 0))
        if offset:Dot(offset) > outer * outer then return end
        if physicsCache and physicsCache.sample == sample and physicsCache.own == own and now - physicsCache.at <= 0.001 then return physicsCache.position, physicsCache.velocity, speed end
        if not replicator or type(replicator.SimulateFrom) ~= "function" then return end
        local elapsed = math.max(age, 0)
        local ok, position, nextPosition = pcall(
          function() return replicator:SimulateFrom(sample, elapsed, own), replicator:SimulateFrom(sample, elapsed + 1 / 240, own) end
        )
        if not ok or not vector(position) or not vector(nextPosition) then return end
        local velocity = (nextPosition - position) * 240
        if not vector(velocity) then return end
        physicsCache = { sample = sample, own = own, at = now, position = position, velocity = velocity }; return position, velocity, speed
      end
      local sync = replicator and replicator.syncData; local speed = type(sync) == "table" and sync.Speed
      if
        not ball
        or not ball.Parent
        or ball.Transparency == 1
        or ball.LocalTransparencyModifier == 1
        or not vector(ball.Position)
        or not finite(speed)
        or sync.Locked == true
      then
        return
      end
      local velocity = ball.AssemblyLinearVelocity
      if not vector(velocity) or velocity.Magnitude < 0.1 then velocity = visualVelocity end
      return ball.Position, velocity, speed
    end
    local function dispatch(now)
      if not deps.canAct(mode or "match") or UserInputService:GetFocusedTextBox() then return end
      local minInterval = mode == "training" and CONFIG.TRAINING_INTERVAL or CONFIG.NATIVE_INTERVAL
      if now - lastAttempt < minInterval then return end
      local success, detail, accepted
      local sentGeneration, sentEpisode, sentMode = generation, episodeStart, mode
      if mode == "training" then
        local camera = workspace.CurrentCamera; local limit = workspace:GetAttribute("CPS_LIMIT")
        if not finite(limit) then limit = trainingShared and trainingShared.DefaultCpsLimit or 16 end
        if not trainingBlock or not trainingBlock.Parent or not camera or countCalls(now, "training") >= limit then return end
        sending = true; success, detail = pcall(trainingBlock.FireServer, trainingBlock, camera.CFrame.Position, camera.CFrame.LookVector)
        accepted = success
      else
        local ability = client and client.Abilities and client.Abilities[1]
        if type(ability) ~= "table" or type(ability.Deflect) ~= "function" then return end
        local last = ability.LastDeflectCallAt
        if finite(last) and now - last < CONFIG.NATIVE_INTERVAL then return end
        if type(ability.IsOwnerAlive) == "function" and not ability:IsOwnerAlive() then return end
        local limit = workspace:GetAttribute("CPS_LIMIT")
        if not finite(limit) then limit = 50 end
        if type(ability.ClickInstances) == "table" and #ability.ClickInstances >= limit then return end
        sending = true; success, detail = pcall(ability.Deflect, ability)
        accepted = success and ability.LastDeflectCallAt ~= last
      end
      sending, lastAttempt = false, now
      if not success then report(detail); return end
      if accepted and running then
        if generation == sentGeneration and episodeStart == sentEpisode then spent = true end
        recordCall(now, sentMode)
      end
    end
    function evaluate()
      if gate.matchActive or not deps.canAct("training") then return end
      if not running or sending or not root or not root.Parent or not humanoid or humanoid.Health <= 0 then return end
      selectMode()
      if mode ~= "training" or trainingEnded then return end
      local now = os.clock()
      if mode == "training" then
        local sample = trainingSample
        if sample and sample.serverTime >= networkFloor and now - sample.receivedAt <= CONFIG.TRAINING_MAX_AGE then put("goal", sample.targeted, sample.receivedAt, false, sample.serverTime) end
      end
      local targeted = resolve(now)
      publish({
        mode = "training",
        cycle = tostring(generation) .. ":" .. tostring(episodeStart),
        targeted = targeted,
        fired = spent,
        targetId = targeted and userId or -1,
        ping = ping or 0,
        ball = trainingBall,
      })
      if not targeted or spent or not ping then return end
      local own = root.Position
      if not vector(own) then return end
      local position, velocity, speed = motion(now, own)
      if not vector(position) or not finite(speed) or speed < CONFIG.MIN_SPEED or speed > CONFIG.MAX_SPEED then return end
      local offset = position - own; local squared = offset:Dot(offset)
      if not finite(squared) then return end
      local distance = math.sqrt(squared); local rootVelocity = vector(root.AssemblyLinearVelocity) and root.AssemblyLinearVelocity or Vector3.zero
      local closing = speed
      if vector(velocity) then closing = distance > 0.001 and -(velocity - rootVelocity):Dot(offset) / distance or speed end
      if not finite(closing) or (distance > (mode == "training" and CONFIG.MIN_RADIUS or range) and closing <= 0) then return end
      local radius = mode == "training" and CONFIG.MIN_RADIUS or range; local tti = closing > 0 and math.max(0, distance - radius) / closing or nil
      local factor = adaptFactor(now, tti, closing, speed); local fraction = math.clamp((speed - low) / (high - low), 0, 1)
      local window = CONFIG.SLOW_WINDOW + (CONFIG.FAST_WINDOW - CONFIG.SLOW_WINDOW) * fraction
      if mode == "training" then
        if trainingShared and type(trainingShared.GetBlockWindow) == "function" then
          local ok, nativeWindow = pcall(trainingShared.GetBlockWindow, speed)
          if not ok or not finite(nativeWindow) or nativeWindow <= 0 then return end
          window = nativeWindow
        else
          window = 0.85 + (0.2 - 0.85) * fraction
        end
      end
      local threshold = radius + math.max(0, closing) * (window * factor + ping)
      publish({
        mode = "training",
        targeted = true,
        speed = speed,
        distance = distance,
        closing = closing,
        radius = radius,
        threshold = threshold,
        window = window,
        factor = factor,
        tti = tti,
        fired = spent,
      })
      if finite(threshold) and distance <= threshold then dispatch(now) end
    end
    local function safeEvaluate()
      local ok, detail = pcall(evaluate)
      if not ok then report(detail) end
    end
    local function trainingGoal(goal, target)
      if id(goal) then return goal == userId end
      if goal == 0 then return false end
      if (goal == nil or (finite(goal) and goal < 0)) and type(target) == "string" and target ~= "" then return false end
      return nil
    end
    local function trainingPacket(position, velocity, serverTime, goal, target, speed)
      if not vector(position) or not vector(velocity) or not finite(serverTime) then return end
      if speed == nil then speed = velocity.Magnitude end
      if not finite(speed) or speed < CONFIG.MIN_SPEED or speed > CONFIG.MAX_SPEED then return end
      local age = workspace:GetServerTimeNow() - serverTime
      if not finite(age) or age < -0.02 or age > CONFIG.TRAINING_MAX_AGE or serverTime <= trainingFloor then return end
      if trainingTime and serverTime <= trainingTime then return end
      local targeted = trainingGoal(goal, target)
      if goal ~= nil and not finite(goal) then return end
      if trainingEnded then
        trainingEnded = false
        if mode == "training" then resetCycle() end
      end
      if mode == "training" and trainingParryFloor and serverTime > trainingParryFloor and targeted == true and root and vector(root.Position) then
        local projected = position + velocity * math.clamp(age, 0, CONFIG.MAX_SAMPLE_AGE); local offset = projected - root.Position
        local rootVelocity = vector(root.AssemblyLinearVelocity) and root.AssemblyLinearVelocity or Vector3.zero; local relative = velocity - rootVelocity
        if offset:Dot(relative) < 0 then
          signalSerial = signalSerial + 1; cutoff, spent, episodeStart, episodeStrong, wasTargeted, physicsCache = signalSerial, false, nil, false, false, nil
          slots.goal = nil; trainingParryFloor = nil
        end
      end
      trainingTime = serverTime
      trainingSample = {
        position = position,
        velocity = velocity,
        serverTime = serverTime,
        goal = goal,
        target = target,
        targeted = targeted,
        speed = speed,
        receivedAt = os.clock(),
      }

      selectMode()
      if mode == "training" and serverTime >= networkFloor then put("goal", targeted, trainingSample.receivedAt, false, serverTime) end
      safeEvaluate()
    end
    local function trainingEvent(kind, owner)
      if kind == "Parry" and owner == userId and mode == "training" and trainingSample then
        trainingParryFloor = math.max(trainingTime or -math.huge, workspace:GetServerTimeNow() - (ping or 0)); spent = true
        return
      end
      if kind == "BallSpawn" or kind == "BallDespawn" or kind == "Kill" then
        trainingParryFloor = nil; trainingFloor = math.max(trainingFloor, trainingTime or -math.huge)
        trainingSample, trainingTime = nil, nil; trainingEnded = kind ~= "BallSpawn"
        if mode == "training" then resetCycle() end
      end
    end
    local function validSyncRemote(instance)
      return typeof(instance) == "Instance" and (instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")) and instance.Parent ~= nil
    end
    local function bindTraining()
      trainingRemotes = child(child(ReplicatedStorage, "Training"), "Remotes"); trainingBlock = child(trainingRemotes, "Block")
      local state = child(trainingRemotes, "BallState"); local event = child(trainingRemotes, "Event")
      if state ~= trainingStateRemote then
        if trainingStateConnection then trainingStateConnection:Disconnect() end
        trainingStateRemote = state
        if validSyncRemote(state) then trainingStateConnection = track(state.OnClientEvent:Connect(trainingPacket)) end
      end
      if event ~= trainingEventRemote then
        if trainingEventConnection then trainingEventConnection:Disconnect() end
        trainingEventRemote = event
        if validSyncRemote(event) then trainingEventConnection = track(event.OnClientEvent:Connect(trainingEvent)) end
      end
    end
    refreshRange(); samplePing()
    bindCharacter(player.Character); selectMode()
    bindTraining(); track(player:GetAttributeChangedSignal("DeflectRange"):Connect(refreshRange))
    track(player.CharacterAdded:Connect(function(value)
      bindCharacter(value); safeEvaluate()
    end))
    track(player.CharacterRemoving:Connect(function(value)
      if character == value then bindCharacter(nil) end
    end))
    track(workspace.DescendantAdded:Connect(function(value)
      if value.Name == "GameBall" and value:IsA("BasePart") then ball = value; physicsCache = nil end
      if value.Name == "PlayerBallHighlight" and value:IsA("Highlight") then playerMark = value end
      if
        value.Name == "TrainingBall"
        or value.Name == "PlayerBallHighlight"
        or value.Name == "BallTrail"
        or value.Name == "BallTrailTarget"
        or value.Name == "BallTrail2"
      then
        cacheParts()
      end
      if character and value.Parent == character then
        if value.Name == "HumanoidRootPart" and value:IsA("BasePart") then root = value end
        if value:IsA("Humanoid") then humanoid = value end
        if value.Name == "PlayerBallHighlight" then playerMark = value end
      end
      if value.Name == "GameBall" or value.Name == "TrainingBall" or value.Name == "HumanoidRootPart" or value:IsA("Humanoid") then safeEvaluate() end
    end))
    track(workspace.DescendantRemoving:Connect(function(value)
      if value == ball then ball = nil; physicsCache = nil end
      if value == trainingBall then trainingBall = nil end
      if value == root then root = nil end
      if value == humanoid then humanoid = nil end
    end))
    track(RunService.PreSimulation:Connect(safeEvaluate)); track(RunService.PostSimulation:Connect(safeEvaluate))
    track(RunService.RenderStepped:Connect(function()
      if gate.matchActive or not deps.canAct("training") then return end
      frame = frame + 1; selectMode()
      visualSignals(os.clock()); safeEvaluate()
    end))
    local uiElapsed = 0
    track(RunService.Heartbeat:Connect(function(dt)
      if not running or gate.matchActive then return end
      local now = os.clock()
      if now - pingAt >= 0.1 then pingAt = now; samplePing() end
      if now - maintenanceAt >= 0.5 then
        maintenanceAt = now; cacheParts()
        bindTraining()
      end
      safeEvaluate(); uiElapsed = uiElapsed + dt
      if uiElapsed >= CONFIG.UI_INTERVAL then uiElapsed = 0; updateUI() end
    end))
    updateUI(); safeEvaluate()
    warn("[AP LAB V14] Treino restaurado")
  end
  local function initialize()
    local CONFIG = {
      MIN_SPEED = 16,
      MAX_SPEED = 1000,
      MIN_RADIUS = 8.5,
      MAX_RADIUS = 16,
      SLOW_WINDOW = 0.5,
      FAST_WINDOW = 0.3,
      WINDOW_FACTOR = 0.45,
      MAX_FACTOR = 0.85,
      FAST_RETURN = 0.1,
      SLOW_RETURN = 0.9,
      CADENCE_EXPIRY = 1.5,
      FACTOR_RELEASE = 0.25,
      MAX_SAMPLE_AGE = 0.25,
      VISUAL_MAX_AGE = 0.1,
      NATIVE_INTERVAL = 0.008,
      UI_INTERVAL = 0.1,
    }

    local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
    local function vector(v) return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
    local function id(v) return finite(v) and v > 0 and v % 1 == 0 end
    local function child(parent, name) return parent and parent:FindFirstChild(name) end
    local function load(module)
      if not module or not module:IsA("ModuleScript") then return nil end
      local ok, result = pcall(require, module)
      if ok and type(result) == "table" then return result end
      warn("[DefenseEngine] " .. module.Name .. ": " .. tostring(result))
    end
    local function track(c)
      connections[#connections + 1] = c; return c
    end
    local shared = child(ReplicatedStorage, "Shared") or child(ReplicatedStorage, "TS"); local gameplay = child(shared, "Gameplay")
    local folder = child(gameplay, "BallReplicator") or child(shared, "BallReplicator"); local exported = load(folder and (folder:IsA("ModuleScript") and folder or child(folder, "BallReplicator")))
    replicator = exported and (exported.BallReplicator or exported); local client = load(child(child(shared, "Abilities"), "ClientAbilities") or child(shared, "ClientAbilities"))
    local ballExport = load(child(gameplay, "GameBall")); local gameBall = ballExport and ballExport.GameBall
    local enumExport = load(child(child(shared, "Enums"), "MatchStatus")); local matchEnum = enumExport and enumExport.MatchStatus
    local ballFeel = load(child(folder, "BallFeel")); local low, high = 16, 600
    if gameBall then
      local ok, a, b = pcall(function() return gameBall:GetBaseSpeed(), gameBall:GetMaxSpeed() end)
      if ok and finite(a) and finite(b) and a > 0 and b > a then low, high = a, b end
    end
    local trainingGate = { matchActive = false, version = 0 }; local userId, inverseSpan = player.UserId, 1 / (high - low)
    local PACKET, HIGHLIGHT, PROVIDER, ATTRIBUTE, COLOR, MARK = 1, 2, 3, 4, 5, 6; local slots = {}
    for index = 1, 6 do
      slots[index] = { weak = index >= COLOR, value = nil, entry = -math.huge, at = -math.huge }
    end
    local character, root, humanoid, ball, playerMark
    local ballScanned, markScanned = false, false; local ping, range, roleActive, frame = nil, CONFIG.MIN_RADIUS, false, 0
    local latestSample, latestAt, lastSequence, teleported = nil, nil, nil, false; local packetVersion, serial, cutoff, episodeStart, strongEpisode = 0, 0, -math.huge, nil, false
    local latestOrder = 0; local spent, sending, generation = false, false, 0
    local lastAttempt, shotToken, confirmedToken = -math.huge, 0, 0
    local lastShot, departure, physicsCache
    local lastAckAt = -math.huge; local lastOwnAt, partner, returnInterval = nil, nil, nil
    local activeFactor, factorAt = CONFIG.WINDOW_FACTOR, os.clock()
    local visualPosition, visualAt, visualVelocity
    local networkFloor, wasTargeted = -math.huge, false; local callTimes, firstCall, lastCall, peakCount = {}, 1, 0, 0
    local metrics = { packets = 0, calls = 0, confirmations = 0, recovered = 0, rejectedNative = 0, rejectedPackets = 0 }
    local evaluate, safeEvaluate, recoverReturn, lastError
    local function report(detail)
      if detail ~= lastError then lastError = detail; warn("[DefenseEngine] " .. tostring(detail)) end
    end
    local function clearSlot(slot)
      slot.value, slot.entry, slot.at, slot.pending, slot.count = nil, -math.huge, -math.huge, nil, 0
    end
    local function resetCycle()
      generation = generation + 1; serial, cutoff, episodeStart, strongEpisode = 0, -math.huge, nil, false
      spent, lastShot, departure, physicsCache, wasTargeted = false, nil, nil, nil, false; networkFloor, lastAttempt = -math.huge, -math.huge
      lastOwnAt, partner, returnInterval = nil, nil, nil; activeFactor, factorAt = CONFIG.WINDOW_FACTOR, os.clock()
      visualPosition, visualAt, visualVelocity = nil, nil, nil
      for index = 1, 6 do
        clearSlot(slots[index])
      end
    end
    local function roleIsActive()
      local lives = player:GetAttribute("Lives")
      if finite(lives) and lives <= 0 then return false end
      return not matchEnum or workspace:GetAttribute("MatchStatus") == matchEnum.InGame
    end
    local function refreshRole()
      local active = roleIsActive(); trainingGate.matchActive = active
      if active ~= roleActive then
        trainingGate.version = trainingGate.version + 1; roleActive = active
        resetCycle()
      end
    end
    local function refreshRange()
      local value = player:GetAttribute("DeflectRange"); range = finite(value) and math.clamp(value, CONFIG.MIN_RADIUS, CONFIG.MAX_RADIUS) or CONFIG.MIN_RADIUS
      physicsCache = nil
    end
    local function samplePing()
      local ok, value = pcall(player.GetNetworkPing, player); ping = ok and finite(value) and value >= 0 and value or nil
    end
    local function targetState(value)
      if id(value) then return value == userId end
    end
    local function put(index, value, now, serverTime)
      local slot = slots[index]
      if type(value) ~= "boolean" then slot.pending, slot.at = nil, -math.huge; return end
      if slot.weak then
        if slot.pending ~= value then
          serial = serial + 1; slot.pending, slot.frame, slot.count, slot.pendingOrder = value, frame, 1, serial
          return
        end
        if slot.frame ~= frame then slot.frame, slot.count = frame, slot.count + 1 end
        if slot.count < 2 then return end
      end
      slot.at = now
      if value == slot.value then return end
      local old, oldEntry = slot.value, slot.entry; serial = serial + 1
      slot.value, slot.entry = value, (slot.weak and value) and slot.pendingOrder or serial; slot.serverTime = finite(serverTime) and serverTime or workspace:GetServerTimeNow() - (ping or 0) - 0.02
      if value == false and old == true and episodeStart and oldEntry >= episodeStart and not (slot.weak and strongEpisode) then
        cutoff, spent, episodeStart, strongEpisode, wasTargeted, physicsCache = serial, false, nil, false, false, nil; networkFloor = math.max(networkFloor, slot.serverTime)
        departure = nil
      end
    end
    local function resolve(now)
      local selected, oldest
      for index = 1, 6 do
        local slot = slots[index]; local lifetime = slot.weak and CONFIG.VISUAL_MAX_AGE or CONFIG.MAX_SAMPLE_AGE
        if index == ATTRIBUTE then lifetime = math.huge end
        if slot.value == true and slot.entry >= cutoff and now >= slot.at and now - slot.at <= lifetime then
          if not slot.weak then strongEpisode = true end
          if not oldest or slot.entry < oldest then selected, oldest = index, slot.entry end
        end
      end
      if not selected then return false end
      if not episodeStart then episodeStart = oldest; networkFloor = math.max(networkFloor, slots[selected].serverTime) end
      if not wasTargeted then
        if lastOwnAt then local elapsed = now - lastOwnAt; returnInterval = elapsed > 0 and elapsed <= CONFIG.CADENCE_EXPIRY and elapsed or nil end
        lastOwnAt, wasTargeted = now, true
      end
      return true
    end
    local function observeOther(target)
      if id(target) and target ~= userId then
        if partner and partner ~= target then returnInterval, lastOwnAt = nil, nil end
        partner = target
      end
    end
    local function refreshAttribute()
      if not roleActive then refreshRole() end
      local target = workspace:GetAttribute("GameBallTarget"); put(ATTRIBUTE, targetState(target), os.clock())
      observeOther(target)
    end
    local function cacheParts()
      if not ball or not ball.Parent then
        local value = workspace:FindFirstChild("GameBall")
        if not value and not ballScanned then value = workspace:FindFirstChild("GameBall", true) end
        ballScanned = true; ball = value and value:IsA("BasePart") and value or nil
      end
      playerMark = child(character, "PlayerBallHighlight") or (playerMark and playerMark.Parent and playerMark)
      if not playerMark and not markScanned then playerMark = ReplicatedStorage:FindFirstChild("PlayerBallHighlight", true); markScanned = true end
    end
    local function bindCharacter(value)
      character, root = value, child(value, "HumanoidRootPart"); humanoid = value and value:FindFirstChildOfClass("Humanoid")
      resetCycle(); cacheParts()
      refreshRole(); refreshAttribute()
    end
    local red, gray = Color3.fromRGB(202, 56, 30), Color3.fromRGB(153, 153, 153)
    local function sameColor(a, b)
      return typeof(a) == "Color3" and typeof(b) == "Color3" and math.abs(a.R - b.R) < 0.005 and math.abs(a.G - b.G) < 0.005 and math.abs(a.B - b.B) < 0.005
    end
    local function visualSignals(now)
      local color
      if ball and ball.Parent and ball.Transparency < 1 and ball.LocalTransparencyModifier < 1 then
        local normal = ball:GetAttribute("SkinNormalColor")
        if not sameColor(normal, red) then
          if sameColor(ball.Color, red) then color = true elseif sameColor(ball.Color, typeof(normal) == "Color3" and normal or gray) then color = false end
        end
        local position = ball.Position
        if vector(position) then
          if visualPosition and visualAt and now > visualAt then
            local velocity = (position - visualPosition) / (now - visualAt); visualVelocity = vector(velocity) and velocity.Magnitude <= CONFIG.MAX_SPEED * 1.5 and velocity or nil
          end
          visualPosition, visualAt = position, now
        end
      end
      put(COLOR, color, now); playerMark = child(character, "PlayerBallHighlight") or playerMark
      local mark = playerMark
      local yes
      if mark and mark:IsA("Highlight") and mark.Parent then yes = mark.Enabled == true and mark.Parent == character end
      put(MARK, yes, now)
    end
    local function packetSignals(now)
      local sample = latestSample
      if not sample or sample.serverTime < networkFloor then return end
      put(PACKET, targetState(sample.targetId), now, sample.serverTime); put(HIGHLIGHT, targetState(sample.highlightId), now, sample.serverTime)
      if sample.targetId ~= userId and sample.highlightId ~= userId and id(sample.targetId) and type(replicator.IsLocalTarget) == "function" then
        local ok, yes = pcall(replicator.IsLocalTarget, replicator)
        if ok then put(PROVIDER, yes, now, sample.serverTime) end
      else
        put(PROVIDER, nil, now)
      end
    end
    local function motion(now, own, needVelocity)
      local sample = latestSample
      if
        sample
        and latestAt
        and latestOrder >= cutoff
        and now - latestAt <= CONFIG.MAX_SAMPLE_AGE
        and sample.targetId == userId
        and sample.serverTime >= networkFloor
      then
        local age = workspace:GetServerTimeNow() - sample.serverTime
        if not finite(age) or age < -0.02 or age > CONFIG.MAX_SAMPLE_AGE or sample.locked == true then return end
        local speed = sample.speed
        if speed < CONFIG.MIN_SPEED or speed > CONFIG.MAX_SPEED then return end
        local offset = sample.position - own; local outer = range + CONFIG.MAX_SPEED * (math.max(age, 0) + CONFIG.SLOW_WINDOW * CONFIG.MAX_FACTOR + (ping or 0))
        if offset:Dot(offset) > outer * outer then return end
        if physicsCache and physicsCache.sample == sample and physicsCache.own == own and now - physicsCache.at <= 0.001 then
          if not needVelocity or physicsCache.velocity then return physicsCache.position, physicsCache.velocity, speed end
        end
        if not replicator or type(replicator.SimulateFrom) ~= "function" then return end
        local elapsed = math.max(age, 0); local ok, position = pcall(replicator.SimulateFrom, replicator, sample, elapsed, own)
        if not ok or not vector(position) then return end
        local delta = position - own
        local velocity
        if needVelocity or delta:Dot(delta) > range * range then
          local nextOk, nextPosition = pcall(replicator.SimulateFrom, replicator, sample, elapsed + 1 / 240, own)
          if not nextOk or not vector(nextPosition) then return end
          velocity = (nextPosition - position) * 240
          if not vector(velocity) then return end
        end
        physicsCache = { sample = sample, own = own, at = now, position = position, velocity = velocity }; return position, velocity, speed
      end
      local sync = replicator and replicator.syncData; local speed = type(sync) == "table" and sync.Speed
      if
        not ball
        or not ball.Parent
        or ball.Transparency == 1
        or ball.LocalTransparencyModifier == 1
        or not vector(ball.Position)
        or not finite(speed)
        or sync.Locked == true
      then
        return
      end
      local velocity = ball.AssemblyLinearVelocity
      if not vector(velocity) or velocity.Magnitude < 0.1 then velocity = visualVelocity end
      return ball.Position, velocity, speed
    end
    local function recordCall(now, calledMode)
      totalCalls = totalCalls + 1; telemetry.fired = true
      if deps.onAttempt then deps.onAttempt(calledMode or "match", now) end
      while firstCall <= lastCall and callTimes[firstCall] <= now - 1 + 0.000001 do
        callTimes[firstCall] = nil; firstCall = firstCall + 1
      end
      if firstCall > lastCall then
        firstCall, lastCall = 1, 0
      elseif firstCall > 128 then
        local count = lastCall - firstCall + 1; table.move(callTimes, firstCall, lastCall, 1)
        for index = count + 1, lastCall do
          callTimes[index] = nil
        end
        firstCall, lastCall = 1, count
      end
      lastCall = lastCall + 1; callTimes[lastCall] = now
      peakCount = math.max(peakCount, lastCall - firstCall + 1)
    end
    local function adaptFactor(now, tti, closing, speed)
      local pressure = 0
      if returnInterval and lastOwnAt and now - lastOwnAt <= math.min(CONFIG.CADENCE_EXPIRY, math.max(CONFIG.FAST_RETURN, returnInterval) * 2) then
        pressure = 1 - math.clamp((returnInterval - CONFIG.FAST_RETURN) / (CONFIG.SLOW_RETURN - CONFIG.FAST_RETURN), 0, 1)
      end
      local budget = (ping or 0) + 1 / 60
      if finite(tti) then pressure = math.max(pressure, math.clamp((budget - tti) / math.max(budget, 0.001), 0, 1)) end
      pressure = math.max(pressure, math.clamp(closing / math.max(speed, 1) - 1, 0, 1)); local desired = CONFIG.WINDOW_FACTOR + (CONFIG.MAX_FACTOR - CONFIG.WINDOW_FACTOR) * pressure
      if desired >= activeFactor then activeFactor = desired else activeFactor = desired + (activeFactor - desired) * math.exp(-math.max(0, now - factorAt) / CONFIG.FACTOR_RELEASE) end
      activeFactor, factorAt = math.clamp(activeFactor, CONFIG.WINDOW_FACTOR, CONFIG.MAX_FACTOR), now; return activeFactor
    end
    local function inClash()
      if deps.getClashContext then return deps.getClashContext() ~= nil end
      if not gameBall or type(gameBall.IsInClash) ~= "function" then return false end
      local ok, yes = pcall(gameBall.IsInClash, gameBall, player); return ok and yes == true
    end
    local function matchWindow(speed, fraction, clash)
      local requested = CONFIG.SLOW_WINDOW + (CONFIG.FAST_WINDOW - CONFIG.SLOW_WINDOW) * fraction
      if clash and gameBall and type(gameBall.ApplyClashPressure) == "function" then
        local ok, nativeWindow = pcall(function()
          local window = 0.85 + (0.2 - 0.85) * fraction
          if type(gameBall.GetClashMinWindow) == "function" then
            local minimum = gameBall:GetClashMinWindow(speed)
            if not finite(minimum) or minimum <= 0 then return nil end
            window = math.max(window, minimum)
          end
          return gameBall:ApplyClashPressure(window, player)
        end)
        if ok and finite(nativeWindow) and nativeWindow > 0 then return math.min(requested, nativeWindow) end
      end
      return requested
    end
    local function dispatch(now)
      if sending or spent or not deps.canAct("match") or not roleIsActive() or UserInputService:GetFocusedTextBox() then return end
      local ability = client and client.Abilities and client.Abilities[1]
      if type(ability) ~= "table" or type(ability.Deflect) ~= "function" then return end
      local last = ability.LastDeflectCallAt
      if now - lastAttempt < CONFIG.NATIVE_INTERVAL or (finite(last) and now - last < CONFIG.NATIVE_INTERVAL) then return end
      if type(ability.IsOwnerAlive) == "function" and not ability:IsOwnerAlive() then return end
      local limit = workspace:GetAttribute("CPS_LIMIT")
      if not finite(limit) then limit = 50 end
      if type(ability.ClickInstances) == "table" and #ability.ClickInstances >= limit then return end
      local expectedGeneration, expectedEpisode, version = generation, episodeStart, packetVersion; sending = true
      local nativeStarted = os.clock(); local ok, detail = pcall(ability.Deflect, ability)
      metrics.maxNativeMs = math.max(metrics.maxNativeMs or 0, (os.clock() - nativeStarted) * 1000); sending, lastAttempt = false, now
      if not ok then report(detail); return end
      if ability.LastDeflectCallAt == last then metrics.rejectedNative = metrics.rejectedNative + 1; return end
      if not running then return end
      shotToken = shotToken + 1; metrics.calls = metrics.calls + 1
      if expectedGeneration == generation and expectedEpisode == episodeStart then
        spent = true; lastShot = { token = shotToken, version = version, serverTime = latestSample and latestSample.serverTime or -math.huge }
      end
      recordCall(now)
    end
    function recoverReturn(now)
      if not departure or not spent or not lastShot or departure.token ~= lastShot.token or not root then return false end
      local sample = latestSample
      if
        not sample
        or packetVersion <= departure.version
        or sample.serverTime < departure.floor
        or sample.serverTime <= lastShot.serverTime
        or sample.targetId ~= userId
        or sample.locked == true
      then
        return false
      end
      if now - latestAt > CONFIG.MAX_SAMPLE_AGE then return false end
      local own = root.Position
      if not vector(own) then return false end
      local position, velocity = motion(now, own, true)
      if not vector(position) or not vector(velocity) then return false end
      local delta = position - own; local rootVelocity = vector(root.AssemblyLinearVelocity) and root.AssemblyLinearVelocity or Vector3.zero
      local incoming = delta:Dot(velocity - rootVelocity) < 0
      if not incoming and delta:Dot(delta) <= range * range and vector(sample.direction) then incoming = (sample.position - own):Dot(sample.direction) < 0 end
      if not incoming then return false end
      serial = serial + 1; latestOrder = serial
      cutoff, spent, episodeStart, strongEpisode, wasTargeted = serial, false, nil, false, false; clearSlot(slots[PACKET])
      clearSlot(slots[HIGHLIGHT]); clearSlot(slots[PROVIDER])
      departure = nil; metrics.recovered = metrics.recovered + 1
      packetSignals(latestAt); return true
    end
    function evaluate()
      if not running or not deps.canAct("match") or sending or not roleActive or not root or not root.Parent or not humanoid or humanoid.Health <= 0 then return end
      local now = os.clock(); local clash = false
      if spent and (not departure or not recoverReturn(now)) then return end
      local targeted = resolve(now)
      publish({
        mode = "match",
        cycle = tostring(generation) .. ":" .. tostring(episodeStart),
        targeted = targeted,
        fired = spent,
        targetId = targeted and userId or -1,
        ping = ping or 0,
        ball = ball,
      })
      if not targeted or not ping then return end
      local own = root.Position
      if not vector(own) then return end
      local position, velocity, speed = motion(now, own, false)
      if not vector(position) or not finite(speed) or speed < CONFIG.MIN_SPEED or speed > CONFIG.MAX_SPEED then return end
      local delta = position - own; local squared = delta:Dot(delta)
      if not finite(squared) then return end
      if squared <= range * range then
        publish({
          mode = "match",
          targeted = true,
          speed = speed,
          distance = math.sqrt(squared),
          radius = range,
          threshold = range,
          window = CONFIG.SLOW_WINDOW + (CONFIG.FAST_WINDOW - CONFIG.SLOW_WINDOW) * math.clamp((speed - low) * inverseSpan, 0, 1),
          factor = activeFactor,
          tti = 0,
          fired = spent,
        })
        dispatch(now); return
      end
      local distance = math.sqrt(squared); local rootVelocity = vector(root.AssemblyLinearVelocity) and root.AssemblyLinearVelocity or Vector3.zero
      local closing = speed
      if vector(velocity) then closing = -(velocity - rootVelocity):Dot(delta) / distance end
      if not finite(closing) or closing <= 0 then return end
      local factor = adaptFactor(now, (distance - range) / closing, closing, speed); local fraction = math.clamp((speed - low) * inverseSpan, 0, 1)
      clash = clash or inClash(); local window = matchWindow(speed, fraction, clash)
      local threshold = range + closing * (window * factor + ping)
      publish({
        mode = "match",
        targeted = true,
        speed = speed,
        distance = distance,
        closing = closing,
        radius = range,
        threshold = threshold,
        window = window,
        factor = factor,
        tti = (distance - range) / closing,
        fired = spent,
      })
      if finite(threshold) and distance <= threshold then dispatch(now) end
    end
    local notifying = false
    function safeEvaluate()
      if not running then return end
      if roleActive and deps.onOpportunity and not notifying then
        notifying = true; local ok, detail = pcall(deps.onOpportunity)
        notifying = false
        if not ok then report(detail) end
      end
      local ok, detail = pcall(evaluate)
      if not ok then report(detail) end
    end
    local function ownParry(kind, owner)
      if kind ~= "parry" or owner ~= userId or not running or not roleActive or not spent or not lastShot then return end
      local now = os.clock()
      if confirmedToken == lastShot.token or now - lastAckAt < CONFIG.NATIVE_INTERVAL then return end
      lastAckAt = now; confirmedToken = lastShot.token
      metrics.confirmations = metrics.confirmations + 1
      departure = { token = lastShot.token, version = lastShot.version, floor = math.max(lastShot.serverTime, workspace:GetServerTimeNow() - (ping or 0)) }; safeEvaluate()
    end
    local function acceptSnapshot(sample, receivedAt)
      if
        type(sample) ~= "table"
        or not finite(sample.serverTime)
        or not vector(sample.position)
        or not finite(sample.speed)
        or sample.speed < 0
        or sample.speed > CONFIG.MAX_SPEED
      then
        metrics.rejectedPackets = metrics.rejectedPackets + 1; return
      end
      if sample.direction ~= nil and not vector(sample.direction) then metrics.rejectedPackets = metrics.rejectedPackets + 1; return end
      if sample.velocity ~= nil and not vector(sample.velocity) then metrics.rejectedPackets = metrics.rejectedPackets + 1; return end
      local age = workspace:GetServerTimeNow() - sample.serverTime
      if not finite(age) or age < -0.02 or age > CONFIG.MAX_SAMPLE_AGE or (latestSample and sample.serverTime < latestSample.serverTime) then
        metrics.rejectedPackets = metrics.rejectedPackets + 1; return
      end
      if sample.seq ~= nil then
        if not finite(sample.seq) or sample.seq < 0 or sample.seq > 65535 or sample.seq % 1 ~= 0 then return end
        if lastSequence then
          local delta = (sample.seq - lastSequence) % 65536
          if delta == 0 or delta >= 32768 then return end
        end
        lastSequence = sample.seq
      elseif latestSample and sample.serverTime <= latestSample.serverTime then
        return
      end
      if not roleActive then refreshRole() end
      if sample.teleported == true and not teleported then resetCycle(); refreshAttribute() end
      if latestAt then metrics.maxPacketGapMs = math.max(metrics.maxPacketGapMs or 0, (receivedAt - latestAt) * 1000) end
      teleported = sample.teleported == true; latestSample, latestAt, physicsCache = sample, receivedAt, nil
      packetVersion, serial = packetVersion + 1, serial + 1; latestOrder = serial
      metrics.packets = metrics.packets + 1; packetSignals(receivedAt)
      observeOther(sample.targetId); safeEvaluate()
    end
    refreshRange(); samplePing()
    bindCharacter(player.Character)
    if replicator then
      originalApplySnapshot = replicator.ApplySnapshot
      if type(originalApplySnapshot) == "function" then
        wrappedApplySnapshot = function(self, sample)
          local receivedAt = os.clock(); local result = originalApplySnapshot(self, sample)
          local ok, detail = pcall(acceptSnapshot, sample, receivedAt); metrics.maxPacketHandlerMs = math.max(metrics.maxPacketHandlerMs or 0, (os.clock() - receivedAt) * 1000)
          if not ok then report(detail) end
          return result
        end
        replicator.ApplySnapshot = wrappedApplySnapshot
      end
      local history = replicator.history; local initial = type(history) == "table" and history[#history]
      if initial then acceptSnapshot(initial, os.clock()) end
    end
    if ballFeel and ballFeel.Hit then track(ballFeel.Hit:Connect(ownParry)) end
    track(player:GetAttributeChangedSignal("Lives"):Connect(function()
      refreshRole(); refreshAttribute()
      safeEvaluate()
    end))
    track(workspace:GetAttributeChangedSignal("MatchStatus"):Connect(function()
      refreshRole(); refreshAttribute()
      safeEvaluate()
    end))
    track(player:GetAttributeChangedSignal("DeflectRange"):Connect(refreshRange))
    track(workspace:GetAttributeChangedSignal("GameBallTarget"):Connect(function()
      refreshAttribute(); safeEvaluate()
    end))
    track(player.CharacterAdded:Connect(function(value)
      bindCharacter(value); safeEvaluate()
    end))
    track(player.CharacterRemoving:Connect(function(value)
      if character == value then bindCharacter(nil) end
    end))
    track(workspace.DescendantAdded:Connect(function(value)
      if value.Name == "GameBall" and value:IsA("BasePart") then ball = value; physicsCache = nil end
      if value.Name == "PlayerBallHighlight" and value:IsA("Highlight") then playerMark = value end
      if character and value.Parent == character then
        if value.Name == "HumanoidRootPart" and value:IsA("BasePart") then root = value end
        if value:IsA("Humanoid") then humanoid = value end
      end
      if value.Name == "GameBall" or value.Name == "HumanoidRootPart" or value:IsA("Humanoid") then safeEvaluate() end
    end))
    track(workspace.DescendantRemoving:Connect(function(value)
      if value == ball then ball = nil; physicsCache = nil end
      if value == root then root = nil end
      if value == humanoid then humanoid = nil end
    end))
    track(RunService.PreSimulation:Connect(safeEvaluate)); track(RunService.PostSimulation:Connect(safeEvaluate))
    track(RunService.RenderStepped:Connect(function()
      frame = frame + 1
      if roleActive then visualSignals(os.clock()); safeEvaluate() end
    end))
    local pingAt, maintenanceAt, uiElapsed = -math.huge, -math.huge, 0
    track(RunService.Heartbeat:Connect(function(dt)
      if not running then return end
      local now = os.clock()
      if now - pingAt >= 0.1 then pingAt = now; samplePing() end
      if now - maintenanceAt >= 0.5 then maintenanceAt = now; cacheParts() end
      safeEvaluate(); uiElapsed = uiElapsed + dt
      if uiElapsed >= CONFIG.UI_INTERVAL then
        uiElapsed = 0
        if control.stats and deps.onStats then deps.onStats(control.stats()) end
      end
    end))
    local stats = function()
      return {
        packets = metrics.packets,
        calls = totalCalls,
        confirmations = metrics.confirmations,
        recovered = metrics.recovered,
        rejectedNative = metrics.rejectedNative,
        rejectedPackets = metrics.rejectedPackets,
        maxCps = peakCount,
        maxNativeMs = metrics.maxNativeMs or 0,
        maxPacketHandlerMs = metrics.maxPacketHandlerMs or 0,
        maxPacketGapMs = metrics.maxPacketGapMs or 0,
        confirmedChannel = ballFeel ~= nil and ballFeel.Hit ~= nil,
      }
    end
    control.stats = stats
    control.pulse = function()
      local before = totalCalls; safeEvaluate()
      if trainingPulse then trainingPulse() end
      return totalCalls > before
    end
    trainingPulse = installTraining(trainingGate, recordCall); safeEvaluate()
  end
  local ok, detail = xpcall(initialize, debug.traceback)
  if not ok then stop(); return nil, detail end
  return control
end
DefenseEngine.__contract = { requires = {}, provides = { "setup", "create" }, version = 1 }

return DefenseEngine
