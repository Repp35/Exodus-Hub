-- [[ mm2 bridge ]]
--!optimize 2

-- module
local Bridge = {}
local factories
function Bridge.setup(deps)
  factories = deps
  return true
end

-- runtime
function Bridge.create(modules)
  local owner = modules.lifetime.scope()
  local runtime = { ShuttingDown = false }
  local connections = setmetatable({}, { __mode = "k" })
  local tasks = setmetatable({}, { __mode = "k" })
  function runtime:Track(connection)
    if not connection then
      return nil
    end
    if self.ShuttingDown then
      connection:Disconnect()
    else
      connections[connection] = true
    end
    return connection
  end
  function runtime:TrackTask(thread)
    if not thread then
      return nil
    end
    if self.ShuttingDown then
      pcall(task.cancel, thread)
    else
      tasks[thread] = true
    end
    return thread
  end
  function runtime:OnShutdown(callback)
    if self.ShuttingDown then
      pcall(callback)
      return false
    end
    owner.add(callback)
    return true
  end
  function runtime:Shutdown()
    if self.ShuttingDown then
      return
    end
    self.ShuttingDown = true
    modules.mm2native.reset()
    owner.destroy()
  end
  owner.add(function()
    for connection in pairs(connections) do
      pcall(connection.Disconnect, connection)
    end
    for thread in pairs(tasks) do
      if thread ~= coroutine.running() then
        pcall(task.cancel, thread)
      end
    end
    table.clear(connections)
    table.clear(tasks)
  end)

  -- dependencies
  local services = {}
  for _, name in ipairs({
    "Players",
    "RunService",
    "UserInputService",
    "Workspace",
    "TweenService",
    "PathfindingService",
    "ReplicatedStorage",
    "CollectionService",
    "CoreGui",
    "HttpService",
  }) do
    services[name] = game:GetService(name)
  end
  local deps = {
    player = modules.utils.getLocalPlayer(),
    services = services,
    runtime = runtime,
    noclip = {
      Acquire = function(_, source) return modules.noclip.acquire(source) end,
      Release = function(_, source) return modules.noclip.release(source) end,
    },
    antifling = { AllowTeleport = function(_, duration) modules.antifling.allowTeleport(duration) end },
    notify = function(title, content) modules.ui.notifyCorner(title, content, { duration = 5 }) end,
  }
  deps.throwKnife = function(knife, data, character)
    if runtime.ShuttingDown or modules.mm2native.busy() or not modules.utils.isActive() then
      return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
      return false
    end
    return modules.mm2native.throw(
      { character = character, humanoid = humanoid, root = root },
      knife,
      CFrame.new(data.Aim),
      function()
        return not runtime.ShuttingDown
          and data.Entry.Character.Parent ~= nil
          and data.Entry.Humanoid.Health > 0
          and data.Entry.Player:GetAttribute("Alive") == true
      end
    )
  end

  -- construction
  local features = {}
  local ok, reason = xpcall(function()
    deps.util = factories.Util.create(deps)
    deps.coin = factories.Coin.create(deps)
    deps.match = factories.Match.create(deps)
    deps.map = factories.Map.create(deps)
    deps.camera = factories.Camera.create(deps)
    features.ESP = factories.ESP.create(deps)
    features.AutoFarm = factories.Farm.create(deps)
    features.AutoGunPickup = factories.Pickup.create(deps)
    features.MurderCombat = factories.Combat.create(deps)
    features.ShootMurder = factories.Shoot.create(deps)
    features.MapTools = factories.Tools.create(deps)
    features.Alerts = factories.Alerts.create(deps)

    -- settings
    local function get(key) return modules.utils.getConfigValue(key) end
    local function enabled(object, value)
      if value then
        object:Start()
      else
        object:Stop()
      end
    end
    local setters = {
      MM2AutoFarm = function(value)
        if value then
          features.AutoFarm:Start()
        else
          features.AutoFarm:Stop(true)
        end
      end,
      MM2FarmSpeed = function(value) features.AutoFarm.Speed = tonumber(value) or 40 end,
      MM2AvoidMurderer = function(value) features.AutoFarm.AvoidMurderer = value == true end,
      MM2ResetFull = function(value) features.AutoFarm:SetResetWhenBagFull(value) end,
      MM2AutoPickup = function(value) enabled(features.AutoGunPickup, value) end,
      MM2PickupSafety = function(value) features.AutoGunPickup:SetSafetyEnabled(value) end,
      MM2ManualShoot = function(value) features.ShootMurder:SetManualEnabled(value) end,
      MM2AutoShoot = function(value) features.ShootMurder:SetAutoEnabled(value) end,
      MM2ManualAccuracy = function(value) features.ShootMurder:SetManualAccuracy(value) end,
      MM2AutoAccuracy = function(value) features.ShootMurder:SetAutoAccuracy(value) end,
      MM2LegitSheriff = function(value) features.ShootMurder:SetWaitForKnife(value) end,
      MM2AutoStab = function(value) features.MurderCombat:SetAutoAttack(value) end,
      MM2AutoThrow = function(value) features.MurderCombat:SetAutoThrow(value) end,
      MM2StabTargets = function(value) features.MurderCombat:SetAttackTargets(value) end,
      MM2ThrowTargets = function(value) features.MurderCombat:SetThrowTargets(value) end,
      MM2ESP = function(value) enabled(features.ESP, value) end,
      MM2ESPIdentity = function(value) features.ESP.ShowIdentity = value == true end,
      MM2ESPUsername = function(value) features.ESP.ShowUsername = value == true end,
      MM2ESPDistance = function(value) features.ESP.ShowDistance = value == true end,
      MM2ESPSelf = function(value) features.ESP:SetShowSelf(value) end,
      MM2ESPMurderer = function(value) features.ESP:SetFilter("Murderer", value) end,
      MM2ESPSheriff = function(value) features.ESP:SetFilter("Sheriff", value) end,
      MM2ESPInnocent = function(value) features.ESP:SetFilter("Innocent", value) end,
      MM2ESPCoins = function(value) features.ESP:SetFilter("CandyCoin", value) end,
      MM2ESPGun = function(value) features.ESP:SetFilter("Gun", value) end,
      MM2AlertRoles = function(value) features.Alerts:SetRoleAndMurdererEnabled(value) end,
      MM2AlertGun = function(value) features.Alerts:SetGunDroppedEnabled(value) end,
      MM2TeleportGun = function(value) features.MapTools:SetAutoGunTeleport(value) end,
      MM2FavoriteMap = function(value) features.MapTools:SetFavoriteMaps(value) end,
    }
    for key, setter in pairs(setters) do
      if key ~= "MM2AutoFarm" and key ~= "MM2AutoPickup" and key ~= "MM2ESP" then
        setter(get(key))
      end
    end
    for _, key in ipairs({ "MM2AutoFarm", "MM2AutoPickup", "MM2ESP" }) do
      setters[key](get(key))
    end
    owner.add(modules.utils.observeConfig(function(changes)
      for key, value in pairs(changes) do
        if setters[key] then
          setters[key](value)
        end
      end
    end))

    owner.connect(services.RunService.Heartbeat, function() modules.mm2native.step() end)
  end, function(message) return tostring(message) end)
  if not ok then
    runtime:Shutdown()
    error(reason, 0)
  end
  return { features = features, destroy = function() runtime:Shutdown() end }
end

-- contract
Bridge.__contract = {
  provides = { "setup", "create" },
  requires = {
    Util = "mm2util",
    Coin = "mm2coin",
    Map = "mm2map",
    Match = "mm2match",
    Camera = "mm2farmcamera",
    ESP = "mm2visuals",
    Farm = "mm2farm",
    Pickup = "mm2pickup",
    Combat = "mm2weapons",
    Shoot = "mm2shoot",
    Tools = "mm2maptools",
    Alerts = "mm2alerts",
  },
  requiresMethods = {
    Util = { "create" },
    Coin = { "create" },
    Map = { "create" },
    Match = { "create" },
    Camera = { "create" },
    ESP = { "create" },
    Farm = { "create" },
    Pickup = { "create" },
    Combat = { "create" },
    Shoot = { "create" },
    Tools = { "create" },
    Alerts = { "create" },
  },
}
return Bridge
