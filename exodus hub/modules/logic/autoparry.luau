-- [[ autoparry ]]

-- module
local function createParryRuntime(deps)
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
      warn("[AutoParry] Falha ao carregar " .. module.Name .. ": " .. tostring(value))
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
      if err ~= lastError then lastError = err; warn("[AutoParry] " .. tostring(err)) end
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
      if mode == "training" and now - lastAttempt < CONFIG.TRAINING_INTERVAL then return end
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
        local last = ability.LastDeflectCallAt; sending = true
        success, detail = pcall(ability.Deflect, ability); accepted = success and ability.LastDeflectCallAt ~= last
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
      warn("[AutoParry] " .. module.Name .. ": " .. tostring(result))
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
      if detail ~= lastError then lastError = detail; warn("[AutoParry] " .. tostring(detail)) end
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
      local last = ability.LastDeflectCallAt; local expectedGeneration, expectedEpisode, version = generation, episodeStart, packetVersion
      sending = true; local nativeStarted = os.clock()
      local ok, detail = pcall(ability.Deflect, ability); metrics.maxNativeMs = math.max(metrics.maxNativeMs or 0, (os.clock() - nativeStarted) * 1000)
      sending, lastAttempt = false, now
      if not ok then report(detail); return end
      if ability.LastDeflectCallAt == last then metrics.rejectedNative = metrics.rejectedNative + 1; return end
      if not running then return end
      shotToken = shotToken + 1; metrics.calls = metrics.calls + 1
      if expectedGeneration == generation and expectedEpisode == episodeStart then
        spent = true; lastShot = { token = shotToken, version = version, at = now, serverTime = latestSample and latestSample.serverTime or -math.huge }
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
    local function recoverCooldown(now)
      if not spent or not lastShot or not deps.getCooldown or confirmedToken == lastShot.token then return false end
      local cd = deps.getCooldown()
      if not cd or cd.source == "unknown" or cd.blocking ~= false or cd.miss ~= true then return false end
      if finite(cd.lastParriedAt) and cd.lastParriedAt >= lastShot.at then return false end
      if not finite(cd.pressAt) or cd.pressAt < lastShot.at - 0.001 or cd.pressAt > now then return false end
      spent, departure = false, nil; return true
    end
    function evaluate()
      if not running or not deps.canAct("match") or sending or not roleActive or not root or not root.Parent or not humanoid or humanoid.Health <= 0 then return end
      local now = os.clock(); local clash = false
      if spent and not (departure and recoverReturn(now)) and not recoverCooldown(now) then return end
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
      if confirmedToken == lastShot.token then return end
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

-- ap-adapter
local AutoParry = {}
local activeRuntime
local deflectGeometry
local requestInFlight = false
local utils, gameInfo, remote, cooldownInfo, autoSpam
local maxObservedCps, syncInterval, lastSyncAt, lastAcceptedSample
local state = {
  phase = "detached",
  reason = "initial",
  generation = 0,
  lifeGeneration = 0,
  alive = false,
  bound = false,
  player = nil,
  character = nil,
  root = nil,
  connections = {},
  fired = false,
  awaySeen = false,
  cycle = 0,
  target = -1,
  targetKnown = false,
  lastTargeted = false,
  teleported = false,
  teleportSequence = nil,
  sequence = nil,
  mode = nil,
  lastBall = nil,
  speed = 0,
  distance = 0,
  approaching = false,
  closingSpeed = 0,
  adaptiveWindow = 0,
  adaptiveFactor = 0,
  timeToRange = math.huge,
  frameAllowance = 0,
  triggerDistance = 0,
  ping = 0,
  pingRaw = nil,
  pingCount = 0,
  lastFireAt = 0,
  lastErrorAt = -math.huge,
  clicks = {},
  returns = {},
  autoParryCps = 0,
  lastAutoParryClickAt = nil,
  windowFactor = 0.3,
  awayAt = nil,
  awayTarget = nil,
  targetChangedAt = nil,
  trainingRound = nil,
  trainingBall = nil,
  trainingLastValidAt = 0,
  trainingLastServerTime = nil,
  trainingConfirmedAt = nil,
  nextAttemptAt = 0,
  lastPosition = nil,
  lastSampleAt = 0,
  resetPending = false,
  retryPending = false,
  retryCooldownSeen = false,
  retryReady = false,
  fierceUntil = 0,
  fierceStartedAt = 0,
  fierceCycle = nil,
  fiercePreviouslyFired = false,
  safetyRisk = 0,
  killTime = math.huge,
  predictionSource = nil,
}

-- configuration
local CONFIG = {
  DEFAULT_WINDOW_FACTOR = 0.3,
  MAX_WINDOW_FACTOR = 0.85,
  MATCH_WINDOW_FACTOR = 0.4,
  RETURN_DIRECTION_MAX_AGE = 0.08,
  MATCH_RETRY_DELAY_MAX = 0.5,
  SNAPSHOT_MAX_AGE = 0.5,
  FIERCE_DURATION = 5,
  FIERCE_END_MARGIN = 0.05,
  RETRY_WINDOW_FACTOR = 0.12,
  PRESSURE_SAMPLE_LIMIT = 100,
  PRESSURE_WINDOW = 3,
  TARGET_SEQUENCE_MODULUS = 65536,
  TARGET_SEQUENCE_HALF = 32768,
  MIN_PARRY_SPEED = 16,
  FRAME_BASE = 1 / 60,
  SERVER_FRAME_MARGIN = 1 / 60,
  TIME_EPSILON = 0.000001,
  DISTANCE_EPSILON = 0.0001,
  MAX_FRAME_ALLOWANCE = 0.12,
  TRAINING_WINDOW_FACTOR = 0.3,
  TRAINING_MIN_SPEED = 1,
  TRAINING_MIN_CLOSING_SPEED = 1,
}

-- helpers
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function validBallSpeed(value) return finite(value) and value >= 0 and value <= 1000 end
local function vector(value) return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z) end
local function clock() return os.clock() end
local function phase(value, reason)
  if state.phase == value and state.reason == reason then return end
  local previous = state.phase; state.phase, state.reason = value, reason
  if previous ~= value and utils and type(utils.recordTransition) == "function" then utils.recordTransition("AutoParry", previous, value, reason) end
end
local function track(connection)
  state.connections[#state.connections + 1] = connection; utils.trackCharacter(connection)
end
local function disconnect()
  for i = #state.connections, 1, -1 do
    local connection = state.connections[i]
    if utils then utils.untrackCharacter(connection) end
    connection:Disconnect(); state.connections[i] = nil
  end
end

-- lifecycle
local function resetTracking()
  syncInterval, lastSyncAt, lastAcceptedSample = nil, nil, nil; state.fired, state.awaySeen, state.cycle = false, false, 0
  state.packetBall, state.packetTarget, state.packetAwayAt, state.packetAwayTarget = nil, nil, nil, nil; state.target, state.targetKnown, state.lastTargeted = -1, false, false
  state.teleported, state.teleportSequence, state.sequence = false, nil, nil; state.mode = nil
  state.lastBall, state.speed, state.distance, state.approaching = nil, 0, 0, false; state.closingSpeed, state.triggerDistance, state.frameAllowance = 0, 0, 0
  state.adaptiveWindow, state.adaptiveFactor, state.timeToRange = 0, 0, math.huge; state.ping, state.pingRaw, state.pingCount, state.lastFireAt = 0, nil, 0, 0
  state.autoParryCps, state.lastAutoParryClickAt, state.windowFactor = 0, nil, CONFIG.DEFAULT_WINDOW_FACTOR; state.awayAt, state.awayTarget, state.targetChangedAt = nil, nil, nil
  state.trainingLastValidAt, state.trainingLastServerTime = 0, nil; state.trainingRound, state.trainingBall, state.trainingConfirmedAt = nil, nil, nil
  state.nextAttemptAt = 0; state.lastPosition, state.lastSampleAt = nil, 0
  state.resetPending = false; state.retryPending, state.retryCooldownSeen, state.retryReady = false, false, false
  state.apNativePressAt = nil; state.danger = nil
  state.runtimeCycle = nil; state.safetyRisk, state.killTime, state.predictionSource = 0, math.huge, nil
  state.fierceUntil, state.fierceStartedAt, state.fierceCycle, state.fiercePreviouslyFired = 0, 0, nil, false; table.clear(state.clicks)
  table.clear(state.returns)
end
local function detach(reason)
  if activeRuntime then activeRuntime.stop(); activeRuntime = nil end
  state.generation += 1; disconnect()
  state.lifeGeneration += 1; state.alive, state.bound, state.character, state.root = false, false, nil, nil
  resetTracking(); phase("detached", reason)
end

-- geometry
local function rangeBonus()
  if not state.alive or not state.bound then return 0 end
  local _, cap = deflectGeometry.getDeflectRangeParameters(); local g = deflectGeometry.getDeflectGeometry(0, 0, 0, false, 0)
  return g and math.clamp(g.resilienceBonus, 0, cap) or 0
end
local function resilience()
  local bonus = rangeBonus(); local _, cap, step = deflectGeometry.getDeflectRangeParameters()
  return {
    stack = math.floor(bonus / step + 0.5),
    size = bonus,
    perParry = step,
    cap = cap,
    maxStack = math.ceil(cap / step),
    source = "DeflectRange",
  }
end
local function configuredFactor()
  local factor = utils and tonumber(utils.getConfigValue("AutoParryWindowFactor")); return finite(factor) and math.clamp(factor, 0, CONFIG.MAX_WINDOW_FACTOR) or CONFIG.MATCH_WINDOW_FACTOR
end
local function activeWindowFactor() return configuredFactor() end
local function recordAutoParryRequest()
  local now, previous = clock(), state.lastAutoParryClickAt; local interval = previous and now - previous or nil
  state.autoParryCps = finite(interval) and interval > 0 and 1 / interval or 0; state.lastAutoParryClickAt = now
  if state.autoParryCps > 0 then maxObservedCps = math.max(maxObservedCps or 0, math.min(25, state.autoParryCps)) end
end
local function trainingGeometry(speed, factor) return deflectGeometry.getTrainingGeometry(speed, finite(factor) and factor or activeWindowFactor()) end
local function radius(speed, factor, baseWindow)
  speed = finite(speed) and math.max(speed, 0) or 0
  if state.mode == "training" then return trainingGeometry(speed, factor) end
  factor = tonumber(factor)
  if not finite(factor) then factor = activeWindowFactor(clock()) end
  factor = math.clamp(factor, 0, CONFIG.MAX_WINDOW_FACTOR); return deflectGeometry.getAutoParryGeometry(speed, factor, CONFIG.FRAME_BASE + state.frameAllowance, state.ping)
end
local function guaranteedRadius(geometry, speed, ping) return deflectGeometry.getGuaranteedRadius(geometry, speed, ping) end

-- telemetry
local function samplePing()
  state.ping, state.pingRaw, state.pingCount = gameInfo.getAveragePing()
end
local function appendRecent(list, item)
  list[#list + 1] = item
  if #list > CONFIG.PRESSURE_SAMPLE_LIMIT then table.remove(list, 1) end
end
local function trajectory(position, velocity, rootPosition, nominalSpeed, geometry, rangeOverride)
  local rootVelocity = state.root and state.root.Parent and state.root.AssemblyLinearVelocity or Vector3.zero
  return deflectGeometry.getTrajectory(position, velocity, rootPosition, nominalSpeed, geometry, rangeOverride, rootVelocity)
end
local function radiusTiming(position, velocity, rootPosition, speed, geometry, ping)
  local range = guaranteedRadius(geometry, speed, ping); local _, _, _, entry = trajectory(position, velocity, rootPosition, speed, geometry, range)
  return entry, range, geometry.deflectWindow
end
local function adaptiveLead(geometry) return geometry.effectiveWindow, geometry.windowFactor end
local function parrySnapshot(time) return gameInfo.getSnapshotAt(time) end
local function resolveVelocity(value, position, speed, time)
  local velocity = vector(value.velocity) and value.velocity or Vector3.zero; local direction = value.syncDirection
  local freshReturn = finite(state.targetChangedAt) and time >= state.targetChangedAt and time - state.targetChangedAt <= CONFIG.RETURN_DIRECTION_MAX_AGE
  if freshReturn and finite(speed) and speed > 0 and vector(direction) and direction.Magnitude > 0.01 then
    local synced = direction.Unit * speed
    if velocity.Magnitude < 0.1 or velocity:Dot(synced) < 0 then return synced end
  end
  if velocity.Magnitude > 0.1 then return velocity end
  if state.lastBall == value.ball and vector(state.lastPosition) and state.lastSampleAt > 0 then
    local elapsed = time - state.lastSampleAt
    if elapsed > 0 and elapsed <= 0.25 then
      local measured = (position - state.lastPosition) / elapsed
      if measured.Magnitude > 0.1 then return measured end
    end
  end
  if finite(speed) and speed > 0 and vector(value.syncDirection) and value.syncDirection.Magnitude > 0.01 then return value.syncDirection.Unit * speed end
  return velocity
end
local function matchTiming(value, time, own, factor, observedVelocity)
  if not value or not vector(value.position) or not vector(own) then return nil end
  local speed = finite(value.syncSpeed) and value.syncSpeed or value.speed
  if not validBallSpeed(speed) then return nil end
  local g = radius(speed, factor or activeWindowFactor())
  if not g or not finite(g.fullRadius) then return nil end
  local distance = (value.position - own).Magnitude; local velocity = vector(observedVelocity) and observedVelocity or (vector(value.velocity) and value.velocity or Vector3.zero)
  local closing = distance > 0 and velocity:Dot(own - value.position) / distance or 0
  return {
    geometry = g,
    speed = speed,
    distance = distance,
    closing = closing,
    entry = closing > 0 and math.max(0, distance - g.noWindowParryRadius) / closing or math.huge,
    killTime = math.huge,
    killRadius = deflectGeometry.getKillRadius(g),
    risk = 0,
    factor = g.windowFactor,
    ready = distance <= g.fullRadius,
    velocity = velocity,
  }
end

-- target-sync
local function sequenceOrder(incoming)
  if not finite(incoming) or incoming < 0 or incoming >= CONFIG.TARGET_SEQUENCE_MODULUS or incoming % 1 ~= 0 then return nil end
  if state.sequence == nil then return "new" end
  local delta = (incoming - state.sequence) % CONFIG.TARGET_SEQUENCE_MODULUS
  if delta == 0 then return "same" end
  return delta < CONFIG.TARGET_SEQUENCE_HALF and "new" or "old"
end
local function observeTarget(target, time)
  if not state.player or not finite(target) then return end
  if target <= 0 then
    if state.targetKnown and state.target == state.player.UserId then state.awaySeen, state.awayAt, state.awayTarget = true, time, nil end
    state.target, state.targetKnown = -1, false; return
  end
  if target == state.target and state.targetKnown then return end
  local me, previous = state.player.UserId, state.target; state.lastTargeted = previous == me
  if target == me and previous ~= me then state.targetChangedAt = time end
  if previous == me and target > 0 and target ~= me then
    state.awaySeen = true; state.awayAt = time
    state.awayTarget = target > 0 and target or nil; state.nextAttemptAt = 0
  elseif target == me and previous ~= me and state.awaySeen then
    if state.awayAt and state.awayTarget == previous and time >= state.awayAt then appendRecent(state.returns, { at = time, interval = time - state.awayAt }) end
    state.fired, state.awaySeen = false, false; state.nextAttemptAt = 0
    state.retryPending, state.retryCooldownSeen, state.retryReady = false, false, false; state.cycle += 1
    state.awayAt, state.awayTarget = nil, nil
  end
  state.target, state.targetKnown = target, true
end
local function observePacketReturn(data, time)
  local value = gameInfo.getSnapshotAt(time)
  if not value or value.mode == "training" then return end
  if state.packetBall ~= value.ball then state.packetBall, state.packetTarget, state.packetAwayAt, state.packetAwayTarget = value.ball, nil, nil, nil end
  local target = tonumber(data.TargetPlayerID); local previous = state.packetTarget
  if not finite(target) or target <= 0 then state.packetTarget, state.packetAwayAt, state.packetAwayTarget = nil, nil, nil; return end
  local me = state.player.UserId
  if previous == me and target ~= me then
    state.packetAwayAt, state.packetAwayTarget = time, target
  elseif target == me and previous ~= me and state.packetAwayAt then
    if state.targetKnown and state.target == me then
      if state.packetAwayTarget == previous then appendRecent(state.returns, { at = time, interval = time - state.packetAwayAt }) end
      state.fired, state.awaySeen, state.nextAttemptAt = false, false, 0; state.retryPending, state.retryCooldownSeen, state.retryReady = false, false, false
      state.cycle += 1; state.targetChangedAt = time
      state.awayAt, state.awayTarget = nil, nil
    end
    state.packetAwayAt, state.packetAwayTarget = nil, nil
  end
  state.packetTarget = target
end
local function observeSnapshot(snapshot, time)
  local mode = snapshot.mode == "training" and "training" or "match"
  local newTrainingBall = mode == "training" and (snapshot.trainingRound ~= state.trainingRound or snapshot.ball ~= state.trainingBall)
  local newMatchBall = mode == "match" and state.lastBall ~= nil and state.lastBall ~= snapshot.ball
  if state.mode ~= mode or newTrainingBall or newMatchBall then
    state.cycle += 1; state.trainingRound, state.trainingBall = nil, nil
    if mode == "training" then
      state.trainingRound, state.trainingBall = snapshot.trainingRound, snapshot.ball; state.lastBall = nil
      state.speed, state.distance, state.approaching = 0, 0, false; state.closingSpeed, state.triggerDistance = 0, 0
    end
    state.mode, state.sequence, state.target, state.targetKnown = mode, nil, -1, false; state.fired, state.awaySeen, state.teleported, state.teleportSequence = false, false, false, nil
    state.awayAt, state.awayTarget = nil, nil; state.trainingLastValidAt, state.trainingLastServerTime, state.trainingConfirmedAt = 0, nil, nil
    state.nextAttemptAt = 0; state.lastPosition, state.lastSampleAt = nil, 0
    state.resetPending = newMatchBall; state.retryPending, state.retryCooldownSeen, state.retryReady = false, false, false
    state.targetChangedAt = nil
  end
  local order = sequenceOrder(snapshot.syncSequence)
  if order == "old" then return false end
  if order == "new" then state.sequence = snapshot.syncSequence end
  observeTarget(snapshot.targetId, time); return true
end

-- parry
local function safeCooldown()
  local ok, value = pcall(cooldownInfo.getDeflectCooldownState); return ok and type(value) == "table" and value or nil
end
local function fierceActive(time, cooldown)
  if state.fierceUntil <= 0 then return false end
  local parried = cooldown and finite(cooldown.lastParriedAt) and cooldown.lastParriedAt >= state.fierceStartedAt
  if not parried and time < state.fierceUntil then return true end
  if not parried and state.cycle == state.fierceCycle and not state.fiercePreviouslyFired then state.fired = false end
  state.fierceUntil, state.fierceStartedAt, state.fierceCycle = 0, 0, nil; return false
end
local function matchDataReady(value, time)
  if value.targetUncertain == true then return false end
  if value.mode == "training" then return true end
  if value.teleported or value.locked or value.ballValid == false or value.valid == false or value.resetting == true or value.ballCanMove == false then return false end
  if not finite(value.targetId) or value.targetId <= 0 then return false end
  if value.syncSpeed ~= nil and not validBallSpeed(value.syncSpeed) then return false end
  if not validBallSpeed(value.speed) then return false end
  if value.syncAt ~= nil and not finite(value.syncAt) then return false end
  local speed = finite(value.syncSpeed) and value.syncSpeed or value.speed
  if not finite(speed) or speed < CONFIG.MIN_PARRY_SPEED then return false end
  if finite(value.syncAt) and value.syncAt > 0 and (time < value.syncAt or time - value.syncAt > CONFIG.SNAPSHOT_MAX_AGE) then return false end
  if value.realPosition ~= nil and not vector(value.realPosition) then return false end
  if value.syncDirection ~= nil and not vector(value.syncDirection) then return false end
  return true
end
local function currentRequestReady(expectedBall, expectedMode, trainingThreshold)
  if not state.root or not state.root.Parent or not state.character or not state.character.Parent then return false end
  local time = clock(); local value = parrySnapshot(time)
  if expectedMode ~= "training" then
    local target = gameInfo.getParryTargetStatus(time)
    if not target.known or not target.targeted or target.targetId ~= state.player.UserId then return false end
  end
  if not gameInfo.isSnapshotValid(value) or not matchDataReady(value, time) then return false end
  local mode = value.mode == "training" and "training" or "match"
  if mode ~= expectedMode or value.ball ~= expectedBall or not value.ball.Parent or value.targetId ~= state.player.UserId then return false end
  if mode == "training" then
    if cooldownInfo.getTrainingCooldownState().blocking == true then return false end
  else
    local cooldown = safeCooldown()
    if not cooldown or cooldown.source == "unknown" or cooldown.blocking == true then return false end
  end
  if value.teleported or value.locked or sequenceOrder(value.syncSequence) == "old" then return false end
  if finite(value.syncAt) and value.syncAt > 0 and (time < value.syncAt or time - value.syncAt > CONFIG.SNAPSHOT_MAX_AGE) then return false end
  local position, own = value.position, gameInfo.getRootPosition(state.root)
  if not vector(position) or not vector(own) then return false end
  if mode == "training" then
    local velocity = value.velocity; local speed = value.syncSpeed ~= nil and value.syncSpeed or (vector(velocity) and velocity.Magnitude or nil)
    if not vector(velocity) or not validBallSpeed(speed) or speed < CONFIG.TRAINING_MIN_SPEED then return false end
    local geometry = trainingGeometry(speed, CONFIG.TRAINING_WINDOW_FACTOR); local ping = deflectGeometry.getTrainingLatency(state.ping)
    local entry, _, lead = radiusTiming(position, velocity, own, speed, geometry, ping)
    if entry <= lead then return true end
    local delta = own - position; local distance = delta.Magnitude
    local closing = distance > 0 and velocity:Dot(delta) / distance or 0
    return finite(closing) and closing >= CONFIG.TRAINING_MIN_CLOSING_SPEED and finite(trainingThreshold) and distance <= trainingThreshold
  end
  local matchGeometry
  if mode ~= "training" then
    local timing = matchTiming(value, time, own)
    if not timing or not timing.ready then return false end
    matchGeometry = timing.geometry
  end
  local speed = finite(value.syncSpeed) and value.syncSpeed or value.speed; local geometry = matchGeometry or radius(speed, activeWindowFactor(time))
  if not geometry then return false end
  local threshold = mode == "training" and trainingThreshold or geometry.fullRadius
  if not finite(threshold) or (position - own).Magnitude > threshold + CONFIG.DISTANCE_EPSILON then return false end
  return true
end
local function manualClickOnCurrentTarget()
  if state.mode == "training" or not finite(state.targetChangedAt) then return false end
  local ok, stamp = pcall(function()
    local ability = gameInfo.getDeflectAbility(); return ability and (ability.LastDeflectCallAt or ability.LastPressClock)
  end)
  return ok and finite(stamp) and stamp >= state.targetChangedAt and stamp <= clock() and stamp ~= state.apNativePressAt
end
local function request(reason)
  local now = clock()
  if autoSpam and state.mode ~= "training" then
    autoSpam.onDefenseOpportunity(parrySnapshot(now))
    if utils.isSpamActive() then return false end
  end
  if
    requestInFlight
    or now < state.nextAttemptAt
    or fierceActive(now, safeCooldown())
    or state.fired
    or not state.player
    or (not state.targetKnown or state.target ~= state.player.UserId)
  then
    return false
  end
  if manualClickOnCurrentTarget() then
    state.fired = true; phase("waiting", "manual_target_already_clicked")
    return false
  end
  local manualBlocked = false; local generation, cycle = state.generation, state.cycle
  local boundUtils, boundRemote = utils, remote; local expectedBall, expectedMode, trainingThreshold = state.lastBall, state.mode, state.triggerDistance
  local firedAt, speed, distance = now, state.speed, state.distance; state.fired, state.lastFireAt = true, firedAt
  local wasRetry = state.retryReady; state.retryPending, state.retryCooldownSeen, state.retryReady = false, false, false
  local function sameCycle()
    return state.generation == generation
      and state.cycle == cycle
      and utils == boundUtils
      and remote == boundRemote
      and state.alive
      and state.bound
      and state.fired
      and state.player ~= nil
      and (state.targetKnown and state.target == state.player.UserId)
  end
  local function allowed()
    if manualClickOnCurrentTarget() then manualBlocked = true; return false end
    return sameCycle()
      and not state.teleported
      and boundUtils.isActive()
      and (state.mode == "training" or not boundUtils.isSpamActive())
      and boundUtils.getConfigValue("AutoParry") ~= false
      and currentRequestReady(expectedBall, expectedMode, trainingThreshold)
  end
  requestInFlight = true; local ok, sent, detail = pcall(boundRemote.fireParry, 1, allowed)
  requestInFlight = false
  if not manualBlocked then
    local readOk, stamp = pcall(function()
      local ability = gameInfo.getDeflectAbility(); return ability and (ability.LastDeflectCallAt or ability.LastPressClock)
    end)
    if readOk and finite(stamp) then state.apNativePressAt = stamp end
  end
  if not ok then detail, sent = sent, false end
  if not sameCycle() then return false end
  if sent ~= true then
    if manualBlocked then
      state.fired = true; phase("waiting", "manual_target_already_clicked")
      return false
    end
    if state.mode == "training" then
      state.fired = false; state.nextAttemptAt = clock() + CONFIG.FRAME_BASE
      phase("waiting", "training_attempt_failed"); local errorAt = clock()
      if detail ~= "Deflect cancelado" and detail ~= "Deflect recusado pelo cliente" and detail ~= "Deflect recusado" and errorAt - state.lastErrorAt >= 1 then
        state.lastErrorAt = errorAt; boundUtils.recordError("TrainingParry", tostring(detail or "Treino indisponível"))
      end
      return false
    end
    state.fired = false; state.retryReady = wasRetry
    local delay = CONFIG.FRAME_BASE
    if type(gameInfo.getAutoSpamDelay) == "function" then
      local delayOk, value = pcall(gameInfo.getAutoSpamDelay)
      if delayOk and finite(value) then delay = math.max(1 / 240, value) end
    end
    local cooldown = safeCooldown()
    if cooldown and finite(cooldown.remaining) then delay = math.max(delay, cooldown.remaining) end
    state.nextAttemptAt = clock() + math.clamp(delay, 1 / 240, CONFIG.MATCH_RETRY_DELAY_MAX); phase("waiting", "parry_attempt_failed")
    local errorAt = clock()
    if detail ~= "Deflect cancelado" and detail ~= "Deflect recusado pelo cliente" and detail ~= "Deflect recusado" and errorAt - state.lastErrorAt >= 1 then
      state.lastErrorAt = errorAt; boundUtils.recordError("AutoParry", tostring(detail or "Deflect indisponível"))
    end
    return false
  end
  state.nextAttemptAt = 0; recordAutoParryRequest()
  if expectedMode ~= "training" then
    lastAcceptedSample = {
      at = firedAt,
      ball = expectedBall,
      cycle = cycle,
      targetId = state.target,
      distance = distance,
      speed = speed,
      closingSpeed = state.closingSpeed,
      idealDistance = trainingThreshold,
    }

  end
  if state.mode == "training" then cooldownInfo.recordTrainingDeflectAttempt(firedAt) else state.retryPending = true; cooldownInfo.recordDeflectAttempt(firedAt, speed) end
  local factor = state.mode == "training" and activeWindowFactor(firedAt) or math.max(activeWindowFactor(firedAt), state.adaptiveFactor)
  if factor > 0 then
    local geometry = radius(speed, factor)
    if geometry then
      local denominator = speed * math.max(geometry.leadTime or geometry.effectiveWindow or 0, 0)
      local used = denominator > 0 and math.clamp((distance - geometry.noWindowParryRadius) / denominator, 0, factor) or factor
      appendRecent(state.clicks, { at = firedAt, factor = used, configured = factor, speed = speed })
    end
  end
  phase("fired", reason); return true
end
local function tickTraining(value, root, time)
  local position, velocity, rootPosition = value.position, value.velocity, gameInfo.getRootPosition(root)
  if not vector(position) or not vector(velocity) or not vector(rootPosition) then return end
  local syncSpeed = tonumber(value.syncSpeed); local speed = finite(syncSpeed) and syncSpeed > 0 and syncSpeed or velocity.Magnitude
  if (value.syncSpeed ~= nil and not validBallSpeed(value.syncSpeed)) or not validBallSpeed(speed) or speed < CONFIG.TRAINING_MIN_SPEED then
    state.approaching, state.closingSpeed, state.triggerDistance = false, 0, 0; phase("waiting", "training_speed_unavailable")
    return
  end
  samplePing(); local geometry = trainingGeometry(speed, CONFIG.TRAINING_WINDOW_FACTOR)
  local delta = rootPosition - position; local distance = delta.Magnitude
  local closing = distance > 0 and velocity:Dot(delta) / distance or 0
  if not finite(closing) then closing = 0 end
  local ping = deflectGeometry.getTrainingLatency(state.ping); local threshold = deflectGeometry.getTrainingTrigger(geometry, closing, ping, state.frameAllowance)
  state.lastBall, state.speed, state.distance, state.approaching = value.ball, speed, distance, closing > 0; state.closingSpeed, state.triggerDistance = closing, threshold
  state.trainingLastValidAt, state.trainingLastServerTime = time, value.serverTime; local confirmed = value.trainingParryAt
  if
    state.fired
    and finite(confirmed)
    and confirmed ~= state.trainingConfirmedAt
    and finite(value.serverTime)
    and value.serverTime > confirmed
    and value.targetId == state.player.UserId
    and closing >= CONFIG.TRAINING_MIN_CLOSING_SPEED
  then
    state.fired, state.awaySeen, state.trainingConfirmedAt, state.retryReady = false, false, confirmed, false; state.cycle += 1
    state.nextAttemptAt = 0
  end
  if
    state.fired
    and cooldownInfo.getTrainingCooldownState().blocking ~= true
    and (not finite(confirmed) or confirmed == state.trainingConfirmedAt)
    and value.targetId == state.player.UserId
    and closing >= CONFIG.TRAINING_MIN_CLOSING_SPEED
  then
    state.fired, state.nextAttemptAt, state.retryReady = false, 0, true
  end
  if state.retryReady then threshold = deflectGeometry.getTrainingTrigger(geometry, closing, ping, state.frameAllowance, CONFIG.RETRY_WINDOW_FACTOR); state.triggerDistance = threshold end
  if state.fired then phase("waiting", "training_awaiting_return"); return end
  if finite(confirmed) then state.trainingConfirmedAt = confirmed end
  if cooldownInfo.getTrainingCooldownState().blocking then phase("waiting", "training_lockout"); return end
  if not state.player or value.targetId ~= state.player.UserId then phase("waiting", "training_not_target"); return end
  local radiusEntry, _, gateLead = radiusTiming(position, velocity, rootPosition, speed, geometry, ping)
  if radiusEntry <= gateLead then request(radiusEntry == 0 and "training_inside_radius" or "training_radius_tti"); return end
  if closing < CONFIG.TRAINING_MIN_CLOSING_SPEED then phase("waiting", "training_not_approaching"); return end
  if distance > threshold then phase("waiting", "training_outside_window"); return end
  request("training_parry")
end
local function tick(character, root, generation)
  if generation ~= state.generation or not state.alive or not state.bound or not character.Parent or not root.Parent then return end
  if not utils.isActive() or utils.getConfigValue("AutoParry") == false then return end
  local time = clock(); local value = parrySnapshot(time)
  if generation ~= state.generation or not state.bound or not state.alive then return end
  if not gameInfo.isSnapshotValid(value) then phase("waiting", "snapshot_indisponível"); return end
  if not matchDataReady(value, time) then
    state.lastPosition, state.lastSampleAt = nil, 0; phase("waiting", "invalid_or_reset_sync")
    return
  end
  if finite(value.syncAt) and value.syncAt > 0 and (time < value.syncAt or time - value.syncAt > CONFIG.SNAPSHOT_MAX_AGE) then phase("waiting", "snapshot_stale"); return end
  if not observeSnapshot(value, time) then phase("waiting", "stale_snapshot"); return end
  if value.mode ~= "training" and autoSpam then autoSpam.onDefenseOpportunity(value) end
  if value.mode ~= "training" and utils.isSpamActive() then phase("waiting", "spam_active"); return end
  if state.teleported or value.teleported then
    state.lastPosition, state.lastSampleAt = nil, 0; phase("waiting", "teleport_lock")
    return
  end
  local cooldown = safeCooldown()
  if fierceActive(time, cooldown) then phase("waiting", "fierce_active"); return end
  if value.mode == "training" then tickTraining(value, root, time); return end
  if not cooldown or cooldown.source == "unknown" then phase("waiting", "cooldown_unknown"); return end
  if state.fired and state.retryPending and cooldown then
    if finite(cooldown.lastParriedAt) and cooldown.lastParriedAt >= state.lastFireAt then
      state.retryPending = false
    elseif
      cooldown.miss == true
      and cooldown.blocking == false
      and (cooldown.phase == "miss_finished" or (finite(cooldown.pressAt) and cooldown.pressAt >= state.lastFireAt - 0.05))
    then
      state.fired, state.retryPending, state.retryCooldownSeen, state.retryReady, state.nextAttemptAt = false, false, false, true, 0
    end
  end
  if state.fired then phase("waiting", "target_already_parried"); return end
  if cooldown and cooldown.blocking == true then phase("waiting", "deflect_cooldown"); return end
  if value.locked == true then
    state.approaching, state.closingSpeed, state.triggerDistance = false, 0, 0; phase("waiting", "ball_locked")
    return
  end
  local position, rootPosition = value.position, gameInfo.getRootPosition(root)
  if not vector(position) or not vector(rootPosition) then return end
  if not value.ball.Parent then return end
  local syncSpeed = tonumber(value.syncSpeed); local speed = finite(syncSpeed) and syncSpeed > 0 and syncSpeed or tonumber(value.speed) or 0
  if state.resetPending then
    local real = value.realPosition; local tolerance = math.max(6, math.max(speed, 0) * 0.15)
    if not vector(real) or (position - real).Magnitude > tolerance then
      state.lastPosition, state.lastSampleAt = nil, 0; phase("waiting", "reset_position_pending")
      return
    end
    state.resetPending = false
  end
  local velocity = resolveVelocity(value, position, speed, time); state.lastBall, state.lastPosition, state.lastSampleAt = value.ball, position, time
  if not state.player or value.targetId ~= state.player.UserId then phase("waiting", "not_target"); return end
  samplePing(); local timing = matchTiming(value, time, rootPosition, nil, velocity)
  if not timing then return end
  local geometry = timing.geometry; state.speed, state.distance, state.approaching = timing.speed, timing.distance, timing.closing > 0
  state.closingSpeed, state.triggerDistance = timing.closing, geometry.fullRadius; state.adaptiveWindow, state.adaptiveFactor, state.timeToRange = geometry.effectiveWindow, timing.factor, timing.entry
  state.danger = timing.danger; state.windowFactor, state.safetyRisk, state.killTime = timing.factor, timing.risk, timing.killTime
  state.predictionSource = value.predictionSource or "visual_fallback"
  if timing.ready then request("parry_requested") end
end

-- public-api
function AutoParry.setup(deps)
  if type(deps) ~= "table" or type(deps.DeflectGeometry) ~= "table" then return false, "DeflectGeometry ausente" end
  if
    type(deps) ~= "table"
    or type(deps.Utils) ~= "table"
    or type(deps.GameInfo) ~= "table"
    or type(deps.Remote) ~= "table"
    or type(deps.Cooldown) ~= "table"
  then
    return false, "dependências inválidas"
  end
  detach("setup"); deflectGeometry, autoSpam = deps.DeflectGeometry, deps.AutoSpam
  utils, gameInfo, remote, cooldownInfo = deps.Utils, deps.GameInfo, deps.Remote, deps.Cooldown; state.player = utils.getLocalPlayer()
  if not state.player then return false, "Players.LocalPlayer indisponível" end
  resetTracking(); phase("detached", "setup_complete")
  return true
end
function AutoParry.bindCharacter(character)
  if not utils or not gameInfo or not remote then return false, "dependências não inicializadas" end
  detach("rebind_start")
  if not character or not character.Parent then return false, "personagem indisponível" end
  local generation = state.generation; local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
  if generation ~= state.generation or not root or not root.Parent or not root:IsA("BasePart") then return false, "HumanoidRootPart indisponível" end
  local service, player = utils.getRunService(), utils.getLocalPlayer(); local signal = service and (service.PostSimulation or service.Heartbeat)
  if not signal or not player then return false, "RunService ou jogador indisponível" end
  state.root, state.character, state.player, state.alive, state.bound = root, character, player, true, true; resetTracking()
  phase("waiting", "character_bound")
  local controller, detail = createParryRuntime({
    getClashContext = gameInfo.getExodusClashContext,
    canAct = function(mode)
      if generation ~= state.generation or not state.bound or not utils.isActive() or utils.getConfigValue("AutoParry") == false then return false end
      if clock() < state.fierceUntil then return false end
      return mode == "training" or not utils.isSpamActive()
    end,
    onOpportunity = function()
      if generation == state.generation and autoSpam and utils.isActive() then autoSpam.onDefenseOpportunity(parrySnapshot(clock())) end
    end,
    onState = function(value)
      if generation ~= state.generation then return end
      if value.mode ~= state.mode or value.ball ~= state.lastBall or value.cycle ~= state.runtimeCycle then state.cycle = state.cycle + 1; state.runtimeCycle = value.cycle end
      state.mode, state.lastBall = value.mode, value.ball; state.targetKnown, state.lastTargeted, state.target = value.targeted ~= nil, value.targeted == true, value.targetId or -1
      state.fired = value.fired == true; state.speed, state.distance, state.closingSpeed = value.speed or 0, value.distance or 0, value.closing or 0
      state.triggerDistance, state.windowFactor = value.threshold or 8.5, value.factor or 0.45
      state.adaptiveFactor, state.adaptiveWindow, state.timeToRange = state.windowFactor, (value.window or 0.5) * state.windowFactor, value.tti or math.huge
      state.ping, state.approaching = value.ping or 0, (value.closing or 0) > 0; state.predictionSource = "v14_runtime"
    end,
    onAttempt = function(mode, now)
      if generation ~= state.generation then return end
      state.fired, state.lastFireAt, state.mode = true, now, mode; local previous = state.lastAutoParryClickAt
      state.autoParryCps = previous and now > previous and 1 / (now - previous) or 0; state.lastAutoParryClickAt = now
      if mode == "training" then cooldownInfo.recordTrainingDeflectAttempt(now) else cooldownInfo.recordDeflectAttempt(now, state.speed) end
      phase("waiting", "target_already_parried")
    end,
    onStats = function(stats) maxObservedCps = math.max(maxObservedCps or 0, stats.maxCps or 0) end,
  })
  if not controller then detach("runtime_failed"); return false, detail end
  activeRuntime = controller
  track(character.AncestryChanged:Connect(function(_, parent)
    if not parent and generation == state.generation then detach("character_removed") end
  end))
  return true
end

-- actions
function AutoParry.beginFierce()
  if not state.alive or not state.bound then return nil end
  local time = clock(); local target = gameInfo.getTargetId()
  if finite(target) then observeTarget(target, time) end
  local token = {
    generation = state.generation,
    cycle = state.cycle,
    previouslyFired = state.fired,
    oldUntil = state.fierceUntil,
    oldStartedAt = state.fierceStartedAt,
    oldCycle = state.fierceCycle,
    oldPreviouslyFired = state.fiercePreviouslyFired,
    startedAt = time,
  }

  if state.fierceUntil <= time then state.fiercePreviouslyFired = state.fired; state.fierceCycle = state.cycle end
  local ping = gameInfo.getAveragePing()
  if not finite(ping) or ping < 0 then ping = 0 end
  state.fierceUntil, state.fierceStartedAt = time + CONFIG.FIERCE_DURATION + ping + CONFIG.FIERCE_END_MARGIN, time
  if state.player and state.targetKnown and state.target == state.player.UserId then state.fired = true end
  return token
end
function AutoParry.cancelFierce(token)
  if token and state.generation == token.generation and state.cycle == token.cycle and state.fierceStartedAt == token.startedAt then
    state.fired = token.previouslyFired
    state.fierceUntil, state.fierceStartedAt, state.fierceCycle, state.fiercePreviouslyFired =
      token.oldUntil, token.oldStartedAt, token.oldCycle, token.oldPreviouslyFired
  end
end
function AutoParry.fire()
  if activeRuntime then return activeRuntime.pulse() end
  if not state.alive or not state.bound or state.fired or state.teleported then return false end
  if not utils.isActive() or utils.getConfigValue("AutoParry") == false then return false end
  if not state.player or state.target ~= state.player.UserId or clock() < state.nextAttemptAt then return false end
  return request("manual_parry")
end
function AutoParry.tryRedirectReturn(value, redirectAt)
  if activeRuntime then return activeRuntime.pulse() end
  if not state.alive or not state.bound or not state.player or state.teleported then return false end
  if not state.root or not state.root.Parent then return false end
  if not utils.isActive() or utils.isSpamActive() or utils.getConfigValue("AutoParry") == false then return false end
  if not gameInfo.isSnapshotValid(value) or value.teleported or value.locked then return false end
  local time = clock()
  if type(gameInfo.getParrySnapshot) == "function" then
    local live = parrySnapshot(time)
    if live and live.ball == value.ball then value = live end
  end
  if not matchDataReady(value, time) then return false end
  if not observeSnapshot(value, time) then return false end
  if state.target ~= state.player.UserId then return false end
  if state.fired and finite(redirectAt) and state.lastFireAt >= redirectAt then return true end
  local cooldown = safeCooldown()
  if not cooldown or cooldown.source == "unknown" or cooldown.blocking == true then return false end
  local position, velocity = value.position, value.velocity; local own = gameInfo.getRootPosition(state.root)
  if not vector(position) or not vector(own) then return false end
  samplePing(); local speed = tonumber(value.syncSpeed)
  if not finite(speed) or speed <= 0 then speed = vector(velocity) and velocity.Magnitude or 0 end
  velocity = resolveVelocity(value, position, speed, time); local timing = matchTiming(value, time, own, nil, velocity)
  if not timing then return false end
  local g, distance, closing, entry = timing.geometry, timing.distance, timing.closing, timing.entry
  state.lastBall, state.speed, state.distance, state.approaching = value.ball, speed, distance, closing > 0; state.closingSpeed, state.triggerDistance = closing, g.fullRadius
  state.lastPosition, state.lastSampleAt = position, time; state.adaptiveWindow, state.adaptiveFactor, state.timeToRange = g.effectiveWindow, g.windowFactor, entry
  state.danger = timing.danger; state.windowFactor, state.safetyRisk, state.killTime = timing.factor, timing.risk, timing.killTime
  state.predictionSource = value.predictionSource or "visual_fallback"
  if not timing.ready then return false end
  if state.fired then return false end
  return request("redirect_return")
end
function AutoParry.resetState() detach("reset") end
function AutoParry.detachCharacter() detach("detach") end
function AutoParry.teardown()
  detach("teardown"); utils, gameInfo, remote, cooldownInfo, state.player, autoSpam = nil, nil, nil, nil, nil, nil
end

-- ball-sync
function AutoParry.onBallSync(data)
  if activeRuntime then
    if type(data) == "table" and (data.Source == "packet" or data.Source == "replicator" or data.Source == nil) then
      local now = clock()
      if lastSyncAt and now > lastSyncAt then syncInterval = now - lastSyncAt end
      lastSyncAt = now; lastAcceptedSample = parrySnapshot(now)
    end
    return true
  end
  if type(data) ~= "table" or not state.alive or not state.bound then return end
  if gameInfo.isTrainingArea() then return true end
  local sequence = data.Sequence or data.TeleportSequence
  if sequence == nil and gameInfo.getSyncSequence and data == gameInfo.getSyncData() then sequence = gameInfo.getSyncSequence() end
  local order = sequenceOrder(sequence)
  if order == "old" then return true end
  if order == "same" and (data.Teleported ~= true or state.teleported) then return true end
  if data.Source == "packet" or data.Source == "replicator" or data.Source == nil then
    local receivedAt = clock()
    if lastSyncAt and receivedAt > lastSyncAt then
      local interval = receivedAt - lastSyncAt
      if interval <= CONFIG.SNAPSHOT_MAX_AGE then syncInterval = math.max(interval, (syncInterval or interval) * 0.9) end
    end
    lastSyncAt = receivedAt
  end
  if order == "new" then state.sequence = sequence end
  if data.Teleported == true then
    state.teleported, state.teleportSequence = true, sequence; state.lastBall = nil
    state.packetBall, state.packetTarget, state.packetAwayAt, state.packetAwayTarget = nil, nil, nil, nil; state.cycle += 1
    state.fired, state.awaySeen, state.targetKnown, state.target = false, false, false, -1; state.retryPending, state.retryCooldownSeen, state.retryReady = false, false, false
    state.resetPending = true; state.speed, state.distance, state.approaching = 0, 0, false
    state.autoParryCps, state.lastAutoParryClickAt, state.windowFactor = 0, nil, CONFIG.DEFAULT_WINDOW_FACTOR; state.nextAttemptAt = 0
    state.lastPosition, state.lastSampleAt = nil, 0; state.awayAt, state.awayTarget = nil, nil
    table.clear(state.clicks); table.clear(state.returns)
    phase("waiting", "teleport_lock"); return true
  end
  if state.teleported and state.teleportSequence then
    local current = gameInfo.getSyncSequence()
    if type(current) ~= "number" or (current - state.teleportSequence) % 65536 >= 32768 then return true end
  end
  state.teleported, state.teleportSequence = false, nil; local now, target = clock(), gameInfo.getTargetId()
  if order == "new" and (data.Source == "packet" or data.Source == "replicator" or data.Source == nil) then observePacketReturn(data, now) end
  observeTarget(target or -1, now)
  if state.character and state.root then tick(state.character, state.root, state.generation) end
  return true
end

-- status
function AutoParry.getTargetStatus()
  return {
    armed = not state.fired,
    firedForTarget = state.fired,
    lastTargeted = state.lastTargeted,
    targeted = state.targetKnown and state.player ~= nil and state.target == state.player.UserId,
    approaching = state.approaching,
    targetId = state.target,
    targetKnown = state.targetKnown,
    cooldown = gameInfo and cooldownInfo.getDeflectCooldownState() or nil,
  }
end
function AutoParry.getPressureDetector()
  return {
    enabled = state.alive and state.bound and utils ~= nil and utils.getConfigValue("AutoParry") ~= false,
    ball = state.lastBall,
    targetId = state.target,
    cycle = state.cycle,
    firedForTarget = state.fired,
    attemptAt = state.lastFireAt,
    frameTime = CONFIG.FRAME_BASE + state.frameAllowance,
    syncInterval = syncInterval,
    ping = state.ping,
    retryAt = state.nextAttemptAt,
    lastAcceptedSample = lastAcceptedSample and table.clone(lastAcceptedSample) or nil,
  }
end
function AutoParry.getDefenseState(value)
  if not utils or not gameInfo then return nil end
  samplePing(); local cooldown = safeCooldown()
  local timing = value and AutoParry.getTiming(value)
  return {
    enabled = state.alive and state.bound and utils.getConfigValue("AutoParry") ~= false,
    armed = not state.fired,
    fired = state.fired,
    cycle = state.cycle,
    lastRequestAt = state.lastFireAt,
    retryAt = state.nextAttemptAt,
    lastParriedAt = cooldown and cooldown.lastParriedAt or 0,
    blocking = cooldown and cooldown.blocking == true or false,
    reason = state.reason,
    triggerDistance = timing and timing.triggerDistance,
    distance = timing and timing.distance,
    closingSpeed = timing and timing.closingSpeed,
    timeToKill = timing and timing.timeToKill,
    safetyRisk = timing and timing.safetyRisk,
    windowFactor = timing and timing.windowFactor,
  }
end
local function rootPosition()
  if state.root and state.root.Parent then return gameInfo.getRootPosition(state.root) end
  local character = state.player and state.player.Character; local root = character and character:FindFirstChild("HumanoidRootPart")
  return root and root.Parent and gameInfo.getRootPosition(root) or nil
end
local function runtimeTiming(value)
  if not activeRuntime then return nil end
  local v = activeRuntime.getSnapshot()
  if not v or not finite(v.window) or not finite(v.speed) or (value and value.ball ~= v.ball) then return nil end
  local radius, factor, speed, ping = v.radius or 8.5, v.factor or 0.45, v.speed, v.ping or 0; local lead = v.window * factor + ping
  local closing = v.closing or speed; local threshold = v.threshold or radius + math.max(0, closing) * lead
  local tti = v.tti or (closing > 0 and math.max(0, (v.distance or 0) - radius) / closing or math.huge)
  return {
    distance = v.distance or 0,
    speed = speed,
    parryRadius = threshold,
    fullRadius = threshold,
    pureRadius = 8.5,
    noWindowParryRadius = radius,
    pingRadius = math.max(0, closing) * ping,
    resilienceBonus = radius - 8.5,
    deflectWindow = v.window,
    effectiveWindow = lead,
    leadTime = lead,
    windowFactor = factor,
    adaptiveWindowFactor = factor,
    triggerPadding = 0,
    triggerDistance = threshold,
    distanceToParryRadius = (v.distance or 0) - threshold,
    timeToRange = tti,
    defenseRadius = radius + speed * ping,
    radiusGateLead = v.window,
    predictionTimeToRange = tti,
    timeToTrigger = math.max(0, tti - lead),
    tti = tti,
    approaching = closing > 0,
    targeted = v.targeted == true,
    predictionSource = "v14_runtime",
    noWindowRadius = radius,
    training = v.mode == "training",
  }
end
function AutoParry.getTiming(value, time, root, factor, baseWindow)
  local live = runtimeTiming(value)
  if live and factor == nil and baseWindow == nil then return live end
  if type(value) ~= "table" or not gameInfo then return nil end
  time = finite(time) and time or clock()
  if value.mode ~= "training" and type(gameInfo.getParrySnapshot) == "function" then
    local live = parrySnapshot(time)
    if live and live.ball == value.ball then value = live end
  end
  root = vector(root) and root or rootPosition(); local position, velocity = value.position, value.velocity
  if gameInfo and typeof(value.ball) == "Instance" and value.ball.Parent and value.ball:IsA("BasePart") then
    if not vector(position) then position = gameInfo.getBallPosition(value.ball) end
    if value.ball == state.lastBall then
      local current = gameInfo.getBallVelocity(value.ball)
      if vector(current) and current.Magnitude > 0.1 then velocity = current end
    end
    if not vector(velocity) then velocity = gameInfo.getBallVelocity(value.ball) end
  end
  if not vector(position) or not vector(root) then return nil end
  velocity = vector(velocity) and velocity or Vector3.zero; local speed = tonumber(value.syncSpeed)
  if not finite(speed) or speed <= 0 then speed = velocity.Magnitude > 0.1 and velocity.Magnitude or tonumber(value.speed) or 0 end
  if not validBallSpeed(speed) then return nil end
  samplePing(); local geometry = value.mode == "training" and trainingGeometry(speed, factor) or radius(speed, factor, baseWindow)
  if not geometry then return nil end
  local match = value.mode ~= "training" and matchTiming(value, time, root, factor) or nil
  if match then geometry, velocity = match.geometry, match.velocity end
  local distance, closing, triggerDistance, entry = trajectory(position, velocity, root, speed, geometry); local lead, adaptiveFactor = adaptiveLead(geometry, entry, closing)
  triggerDistance = geometry.training and deflectGeometry.getProjectedTriggerRadius(geometry, closing) or geometry.fullRadius; local distanceToRadius = distance - triggerDistance
  local radiusEntry, defenseRadius, gateLead = radiusTiming(position, velocity, root, speed, geometry, state.ping)
  local timeToTrigger = math.min(math.max(entry - lead, 0), math.max(radiusEntry - gateLead, 0))
  if not geometry.training then timeToTrigger = match and match.ready and 0 or math.max(0, entry - lead) end
  local killRadius = match and match.killRadius or deflectGeometry.getKillRadius(deflectGeometry.getDefensePhysics()); local killTime = match and match.killTime
  if not finite(killTime) then
    local ownVelocity = state.root and state.root.Parent and state.root.AssemblyLinearVelocity; local danger = deflectGeometry.getDanger(position, velocity, root, speed, killRadius, 0, ownVelocity)
    killTime = danger and danger.entryTime or math.huge
  end
  return {
    distance = distance,
    speed = speed,
    velocity = velocity,
    parryRadius = geometry.fullRadius,
    fullRadius = geometry.fullRadius,
    pureRadius = geometry.pureRadius,
    noWindowParryRadius = geometry.noWindowParryRadius,
    pingRadius = geometry.pingRadius,
    resilienceBonus = geometry.resilienceBonus,
    leadTime = geometry.leadTime,
    deflectWindow = geometry.deflectWindow,
    effectiveWindow = lead,
    windowFactor = geometry.windowFactor,
    adaptiveWindowFactor = adaptiveFactor,
    triggerPadding = geometry.triggerPadding,
    distanceToParryRadius = distanceToRadius,
    timeToRange = radiusEntry,
    defenseRadius = defenseRadius,
    radiusGateLead = gateLead,
    predictionTimeToRange = entry,
    triggerDistance = triggerDistance,
    timeToTrigger = timeToTrigger,
    tti = radiusEntry,
    approaching = closing > 0 and speed >= CONFIG.MIN_PARRY_SPEED,
    timeToKill = killTime,
    killRadius = killRadius,
    danger = match and match.danger or nil,
    safetyRisk = match and match.risk or nil,
    predictionSource = value.predictionSource or "visual_fallback",
    targeted = value.targeted == true,
  }
end
function AutoParry.getRadius(mode, factor, speedOverride, baseWindow)
  local live = runtimeTiming()
  if live and factor == nil and speedOverride == nil and baseWindow == nil then
    live.mode, live.resilience = mode or "geometry", resilience(); live.value = mode == "tti" and live.tti or live.fullRadius
    return live
  end
  if not gameInfo then return nil end
  if mode ~= "tti" and mode ~= "speed_distance" then mode = "geometry" end
  local speed = tonumber(speedOverride)
  if not finite(speed) or speed < 0 then speed = state.speed end
  samplePing(); local result = radius(speed, factor, baseWindow)
  if not result then return nil end
  local time = clock(); local value, own = parrySnapshot(time), rootPosition()
  local tti = math.huge; result.defenseRadius = guaranteedRadius(result, speed, state.ping)
  if gameInfo.isSnapshotValid(value) and vector(own) then
    if value.mode ~= "training" then
      local timing = matchTiming(value, time, own, factor)
      if timing then result = timing.geometry; result.defenseRadius = guaranteedRadius(result, speed, state.ping) end
    end
    local velocity = resolveVelocity(value, value.position, speed, time); tti = radiusTiming(value.position, velocity, own, speed, result, state.ping)
  end
  result.mode, result.speed, result.distance, result.tti, result.resilience = mode, speed, state.distance, tti, resilience()
  result.value = mode == "tti" and tti or (mode == "speed_distance" and { speed = speed, distance = state.distance } or result.fullRadius); return result
end
function AutoParry.getPressure()
  local time, count, factors, configured, speeds, ratios = clock(), 0, 0, 0, 0, 0
  for i = #state.clicks, 1, -1 do
    local item = state.clicks[i]
    if time < item.at or time - item.at > CONFIG.PRESSURE_WINDOW then
      table.remove(state.clicks, i)
    else
      count += 1
      factors += item.factor
      configured += item.configured; speeds += item.speed
      ratios += math.clamp(item.factor / item.configured, 0, 1)
    end
  end
  local returns, intervals = 0, 0
  for i = #state.returns, 1, -1 do
    local item = state.returns[i]
    if time < item.at or time - item.at > CONFIG.PRESSURE_WINDOW then table.remove(state.returns, i) else returns += 1; intervals += item.interval end
  end
  local latest, lastReturn = state.clicks[#state.clicks], state.returns[#state.returns]
  local currentLevel, factorDrop
  if latest and time >= latest.at and time - latest.at <= 1 and finite(latest.configured) and latest.configured > 0 then
    local ratio = math.clamp(latest.factor / latest.configured, 0, 1); currentLevel = 1 - ratio
    if count >= 3 then
      local previous, older = state.clicks[#state.clicks - 1], state.clicks[#state.clicks - 2]
      local earlier = (math.clamp(previous.factor / previous.configured, 0, 1) + math.clamp(older.factor / older.configured, 0, 1)) / 2; factorDrop = math.max(0, earlier - ratio)
    end
  end
  return {
    samples = count,
    cps = count / CONFIG.PRESSURE_WINDOW,
    averageFactor = count > 0 and factors / count or nil,
    configuredFactor = count > 0 and configured / count or nil,
    averageSpeed = count > 0 and speeds / count or nil,
    returnSamples = returns,
    averageReturnTime = returns > 0 and intervals / returns or nil,
    level = count >= 3 and returns >= 2 and math.clamp(1 - ratios / count, 0, 1) or nil,
    currentFactor = latest and latest.factor or nil,
    currentLevel = currentLevel,
    factorDrop = factorDrop,
    latestReturnTime = lastReturn and lastReturn.interval or nil,
  }
end
function AutoParry.getStatus()
  local geometry = AutoParry.getRadius("geometry", utils and activeWindowFactor(clock()) or CONFIG.DEFAULT_WINDOW_FACTOR)
  if not geometry then return { available = false, lifecycle = { phase = state.phase, bound = state.bound, alive = state.alive } } end
  local target = AutoParry.getTargetStatus()
  return {
    schema = utils and utils.apiVersion() or nil,
    api = {
      name = "AutoParry",
      version = 14,
      endpoints = { "getRadius", "getTiming", "getStatus", "getTargetStatus" },
      radiusModes = { "geometry", "tti", "speed_distance" },
      defaultWindowFactor = state.mode == "training" and CONFIG.DEFAULT_WINDOW_FACTOR or CONFIG.MATCH_WINDOW_FACTOR,
      windowFactorRange = { min = 0, max = CONFIG.MAX_WINDOW_FACTOR },
    },
    lifecycle = {
      phase = state.phase,
      reason = state.reason,
      bound = state.bound,
      alive = state.alive,
      generation = state.generation,
      lifeGeneration = state.lifeGeneration,
    },
    radius = geometry,
    resilience = geometry.resilience,
    timing = {
      tti = geometry.tti,
      ti = geometry.tti,
      speed = state.speed,
      distance = state.distance,
      distanceToRadius = state.distance - state.triggerDistance,
      triggerDistance = state.triggerDistance,
      closingSpeed = state.closingSpeed,
      timeToRange = geometry.tti,
      predictionTimeToRange = state.timeToRange,
      defenseRadius = geometry.defenseRadius,
      radiusGateLead = geometry.deflectWindow,
      adaptiveWindow = state.adaptiveWindow,
      adaptiveFactor = state.adaptiveFactor,
      frameAllowance = state.frameAllowance,
      deflectWindow = geometry.deflectWindow,
      effectiveWindow = state.adaptiveWindow > 0 and state.adaptiveWindow or geometry.effectiveWindow,
      leadTime = geometry.leadTime,
      noWindowParryRadius = geometry.noWindowParryRadius,
      pingRadius = geometry.pingRadius,
      approaching = state.approaching,
      timeToKill = state.killTime,
      danger = state.danger and table.clone(state.danger) or nil,
      safetyRisk = state.safetyRisk,
      predictionSource = state.predictionSource,
    },
    ping = {
      oneWay = state.ping,
      raw = state.pingRaw,
      samples = state.pingCount,
    },
    cps = state.autoParryCps,
    maxObservedCps = maxObservedCps,
    windowFactor = state.windowFactor,
    cpsGate = {
      adaptive = false,
    },
    target = target,
    mode = state.mode,
    training = {
      active = state.mode == "training",
      triggerDistance = state.mode == "training" and state.triggerDistance or nil,
      nextAttemptIn = 0,
      stateAge = state.mode == "training" and (state.trainingLastValidAt > 0 and clock() - state.trainingLastValidAt or nil) or nil,
    },
    pressure = AutoParry.getPressure(),
    cycle = {
      fired = state.fired,
      armed = not state.fired,
      lastFireAt = state.lastFireAt,
      lastTTI = geometry.tti,
    },
    config = {
      baseRadius = geometry.pureRadius,
      baseWindow = geometry.deflectWindow,
      defaultWindowFactor = state.mode == "training" and CONFIG.DEFAULT_WINDOW_FACTOR or CONFIG.MATCH_WINDOW_FACTOR,
      windowFactorRange = { min = 0, max = CONFIG.MAX_WINDOW_FACTOR },
      adaptiveMaxWindowFactor = CONFIG.MAX_WINDOW_FACTOR,
      minBallSpeed = CONFIG.MIN_PARRY_SPEED,
    },
    timestamp = clock(),
  }
end

-- contract
AutoParry.__contract = {
  requires = {
    DeflectGeometry = "deflectgeometry",
    Remote = "remote",
    GameInfo = "gameinfo",
    Utils = "utils",
    Cooldown = "cooldown",
    AutoSpam = "autospam",
  },
  requiresMethods = {
    AutoSpam = { "onDefenseOpportunity" },
    DeflectGeometry = {
      "getKillRadius",
      "getDeflectRangeParameters",
      "getDeflectGeometry",
      "getTrainingGeometry",
      "getAutoParryGeometry",
      "getGuaranteedRadius",
      "getTrajectory",
      "getDanger",
      "withAutoParryFactor",
      "getTrainingLatency",
      "getTrainingTrigger",
      "getProjectedTriggerRadius",
    },
    Remote = { "fireParry" },
    Cooldown = { "getDeflectCooldownState", "recordDeflectAttempt", "recordTrainingDeflectAttempt", "getTrainingCooldownState" },
    GameInfo = {
      "getExodusClashContext",
      "isTrainingArea",
      "getDeflectAbility",
      "observeTraining",
      "getSnapshotAt",
      "getParrySnapshot",
      "isSnapshotValid",
      "getSyncData",
      "getTargetId",
      "getParryTargetStatus",
      "getSyncSequence",
      "getAveragePing",
      "getBallPosition",
      "getBallVelocity",
      "getRootPosition",
      "getAutoSpamDelay",
    },
    Utils = {
      "apiVersion",
      "getLocalPlayer",
      "getRunService",
      "getConfigValue",
      "isActive",
      "isSpamActive",
      "trackCharacter",
      "untrackCharacter",
      "recordError",
      "recordTransition",
    },
  },
  provides = {
    "getDefenseState",
    "getPressureDetector",
    "setup",
    "bindCharacter",
    "detachCharacter",
    "teardown",
    "onBallSync",
    "fire",
    "tryRedirectReturn",
    "beginFierce",
    "cancelFierce",
    "resetState",
    "getRadius",
    "getTiming",
    "getTargetStatus",
    "getPressure",
    "getStatus",
  },
  onBallSync = true,
  bindCharacter = true,
  version = 14,
}

return AutoParry
