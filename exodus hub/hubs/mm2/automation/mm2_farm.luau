-- [[ mm2 farm ]]
--!optimize 2

-- module
local Farm = {}
function Farm.setup() return true end

-- instance
function Farm.create(deps)
  local player, services, runtime = deps.player, deps.services, deps.runtime
  local farm = { Enabled = false, Farming = false, Speed = 40, AvoidMurderer = false, ResetWhenBagFull = false, BagFull = false }
  local motion, connection, resetThread, resetTriggered, activation, route, passedContainer
  local passed = setmetatable({}, { __mode = "k" })
  local noRole = { unknown = true, none = true, norole = true, sempapel = true, unassigned = true, waiting = true, lobby = true }

  -- movement
  local function cancelRoute()
    if route then
      route.tween:Cancel()
      route = nil
    end
  end
  function farm:StopMotion()
    cancelRoute()
    self.Farming = false
    local saved = motion
    motion = nil
    if not saved then
      return
    end
    if saved.lease then
      deps.noclip:Release(self)
    end
    deps.util.DestroySafely(saved.gravity)
    if saved.root.Parent then
      pcall(function()
        saved.root.CFrame = saved.root.CFrame * CFrame.Angles(math.rad(-90), 0, 0) + Vector3.new(0, 2.5, 0)
        saved.root.AssemblyLinearVelocity = Vector3.zero
        saved.root.AssemblyAngularVelocity = Vector3.zero
      end)
    end
    if saved.humanoid.Parent then
      pcall(function()
        saved.humanoid.PlatformStand = saved.platform
        saved.humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, saved.falling)
        saved.humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, saved.ragdoll)
      end)
    end
  end
  local function beginMotion(character, humanoid, root)
    if motion and motion.character == character then
      return
    end
    farm:StopMotion()
    deps.antifling:AllowTeleport(0.35)
    motion = {
      character = character,
      humanoid = humanoid,
      root = root,
      platform = humanoid.PlatformStand,
      falling = humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
      ragdoll = humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
      lease = deps.noclip:Acquire(farm) == true,
    }
    local gravity = Instance.new("BodyPosition")
    motion.gravity = gravity
    gravity.Name = "ExodusFarmGravity"
    gravity.MaxForce = Vector3.new(0, math.huge, 0)
    gravity.D, gravity.P = 1000, 10000
    root.CFrame = (root.CFrame - Vector3.new(0, 2.5, 0)) * CFrame.Angles(math.rad(90), 0, 0)
    gravity.Position = root.Position
    gravity.Parent = root
    humanoid.PlatformStand = true
    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    farm.Farming = true
  end

  -- bag
  local function cancelReset()
    if resetThread then
      pcall(task.cancel, resetThread)
      resetThread = nil
    end
    resetTriggered = false
  end
  local function resetFullBag()
    if not farm.Enabled or not farm.BagFull or not farm.ResetWhenBagFull or resetTriggered or runtime.ShuttingDown then
      return
    end
    if deps.match:GetLocalRole() ~= "Innocent" then
      return
    end
    local ready, character, humanoid = deps.match:GetContext()
    if not ready then
      return
    end
    resetTriggered = true
    resetThread = task.delay(0.5, function()
      resetThread = nil
      if
        farm.Enabled
        and farm.BagFull
        and farm.ResetWhenBagFull
        and not runtime.ShuttingDown
        and player.Character == character
        and humanoid.Parent
        and humanoid.Health > 0
        and player:GetAttribute("Alive") == true
        and deps.match:GetLocalRole() == "Innocent"
      then
        humanoid.Health = 0
      else
        resetTriggered = false
      end
    end)
  end
  function farm:SetResetWhenBagFull(value)
    self.ResetWhenBagFull = value == true
    if self.ResetWhenBagFull then
      resetFullBag()
    else
      cancelReset()
    end
  end

  -- context
  local function assigned(profiles)
    local profile = profiles and profiles[player.Name]
    if type(profile) ~= "table" or profile.Dead == true or profile.Killed == true or type(profile.Role) ~= "string" then
      return false
    end
    local role = profile.Role:lower():gsub("[%s_%-]", "")
    return role ~= "" and not noRole[role]
  end
  local function murderer(profiles)
    if not farm.AvoidMurderer or not profiles or deps.match:GetLocalRole() == "Murderer" then
      return nil
    end
    for name, profile in pairs(profiles) do
      if type(profile) ~= "table" or profile.Role ~= "Murderer" or profile.Dead == true or profile.Killed == true then
        continue
      end
      local target = services.Players:FindFirstChild(name)
      local character = target and target.Character
      local humanoid = character and character:FindFirstChildOfClass("Humanoid")
      local root = character and character:FindFirstChild("HumanoidRootPart")
      if target and target ~= player and target:GetAttribute("Alive") == true and humanoid and humanoid.Health > 0 and root then
        return root
      end
    end
    return nil
  end

  -- collection
  local function step()
    if not farm.Enabled or runtime.ShuttingDown then
      return
    end
    local active, character, humanoid, root, container = deps.match:GetContext()
    local profiles = active and deps.match:GetPlayerData() or nil
    if not active or not assigned(profiles) or not deps.util.IsFiniteVector3(root.Position) then
      farm:StopMotion()
      return
    end
    if motion and motion.character ~= character then
      farm:StopMotion()
    end
    if farm.BagFull then
      farm:StopMotion()
      resetFullBag()
      return
    end
    if passedContainer ~= container then
      table.clear(passed)
      passedContainer = container
    end
    local threat = murderer(profiles)
    local function near(position, limit) return threat ~= nil and (threat.Position - position).Magnitude < limit end
    if near(root.Position, 40) then
      farm:StopMotion()
      return
    end
    if route and (route.container ~= container or not deps.coin:IsCollectable(route.coin, container) or near(route.point, 45)) then
      cancelRoute()
    end
    if route and route.tween.PlaybackState == Enum.PlaybackState.Completed then
      local touch = getfenv().firetouchinterest
      if type(touch) == "function" and (root.Position - route.coin.Position).Magnitude <= 3.5 then
        pcall(touch, root, route.coin, 0)
        pcall(touch, root, route.coin, 1)
      end
      passed[route.coin] = true
      cancelRoute()
    end
    if not route then
      local coin, _, point = deps.map:GetNearestCoin(container, root.Position, nil, passed, function(_, position) return not near(position, 45) end)
      if not coin then
        farm:StopMotion()
        return
      end
      beginMotion(character, humanoid, root)
      local destination = point - Vector3.new(0, 2.5, 0)
      local delta = destination - root.Position
      if delta.Magnitude > 0.001 then
        destination += delta.Unit * 1.5
      end
      local speed = tonumber(farm.Speed) or 40
      if speed ~= speed or math.abs(speed) == math.huge then
        speed = 40
      end
      local duration = math.max((destination - root.Position).Magnitude / math.max(speed, 1), 1 / 60)
      local tween = services.TweenService:Create(
        root,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { CFrame = CFrame.new(destination) * CFrame.Angles(math.rad(90), 0, 0) }
      )
      route = { coin = coin, point = point, container = container, tween = tween }
      tween:Play()
    end
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    motion.gravity.Position = root.Position
    humanoid.PlatformStand = true
    local touch = getfenv().firetouchinterest
    if type(touch) == "function" then
      for coin in pairs(deps.map:GetCoinPositions(container)) do
        if
          not passed[coin]
          and deps.coin:IsCollectable(coin, container)
          and (root.Position - coin.Position).Magnitude <= 3.5
          and not near(coin.Position, 45)
        then
          pcall(touch, root, coin, 0)
          pcall(touch, root, coin, 1)
        end
      end
    end
  end

  -- restoration
  local function restore()
    local saved = activation
    activation = nil
    if not saved or player.Character ~= saved.character or not saved.root.Parent then
      return
    end
    local humanoid = saved.character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
      return
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    params.IgnoreWater = true
    local ignored = {}
    for _, target in ipairs(services.Players:GetPlayers()) do
      if target.Character then
        table.insert(ignored, target.Character)
      end
    end
    params.FilterDescendantsInstances = ignored
    local position = saved.cframe.Position
    local floor = services.Workspace:Raycast(position + Vector3.new(0, 0.5, 0), Vector3.new(0, -8.5, 0), params)
    if not floor then
      return
    end
    deps.antifling:AllowTeleport(0.35)
    saved.root.CFrame = saved.cframe
    saved.root.AssemblyLinearVelocity, saved.root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
  end

  -- lifecycle
  function farm:Start()
    if self.Enabled or runtime.ShuttingDown then
      return
    end
    self.Enabled = true
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    activation = root and { character = character, root = root, cframe = root.CFrame } or nil
    table.clear(passed)
    passedContainer = nil
    deps.camera:SetSource("AutoFarm", true)
    local lastError = -math.huge
    connection = services.RunService.Heartbeat:Connect(function()
      local ok, reason = pcall(step)
      if not ok then
        self:StopMotion()
        if os.clock() - lastError >= 5 then
          lastError = os.clock()
          warn("[Exodus MM2] Farm: " .. tostring(reason))
        end
      end
    end)
  end
  function farm:Stop(restorePosition)
    self.Enabled = false
    if connection then
      connection:Disconnect()
      connection = nil
    end
    cancelReset()
    self:StopMotion()
    deps.camera:SetSource("AutoFarm", false)
    if restorePosition then
      restore()
    else
      activation = nil
    end
  end

  -- events
  local bound = setmetatable({}, { __mode = "k" })
  local function bind(event)
    if bound[event] or not event:IsA("RemoteEvent") or not event.Parent or event.Parent.Name ~= "Gameplay" then
      return
    end
    local name = event.Name
    if name ~= "CoinCollected" and name ~= "RoundStart" and name ~= "CoinsStarted" and name ~= "RoundEndFade" then
      return
    end
    bound[event] = true
    runtime:Track(event.OnClientEvent:Connect(function(kind, count, maximum)
      if name == "CoinCollected" then
        if not deps.coin:NormalizeKind(kind) then
          return
        end
        count, maximum = tonumber(count), tonumber(maximum)
        if count and maximum and maximum > 0 and count >= maximum then
          farm.BagFull = true
          farm:StopMotion()
          resetFullBag()
        end
      else
        cancelReset()
        farm.BagFull = false
        table.clear(passed)
        passedContainer = nil
        farm:StopMotion()
      end
    end))
  end
  local remotes = services.ReplicatedStorage:FindFirstChild("Remotes")
  local gameplay = remotes and remotes:FindFirstChild("Gameplay")
  if gameplay then
    for _, event in ipairs(gameplay:GetChildren()) do
      bind(event)
    end
  end
  runtime:Track(services.ReplicatedStorage.DescendantAdded:Connect(bind))
  runtime:Track(player.CharacterAdded:Connect(function()
    farm:StopMotion()
    cancelReset()
  end))
  runtime:Track(player:GetAttributeChangedSignal("Alive"):Connect(function()
    if player:GetAttribute("Alive") ~= true then
      farm:StopMotion()
      cancelReset()
    end
  end))
  runtime:OnShutdown(function() farm:Stop(false) end)
  return farm
end

-- contract
Farm.__contract = { provides = { "setup", "create" }, requires = {} }
return Farm
