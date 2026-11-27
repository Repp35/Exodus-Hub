-- [[ MM2 runtime composition ]]
--!optimize 2
local Runtime = {}
local api, owner, scope, modules
function Runtime.setup() return true end
function Runtime.teardown()
  if owner then
    owner.ShuttingDown = true
  end
  if scope then
    scope.destroy()
  end
  api, owner, scope, modules = nil, nil, nil, nil
  return true
end
function Runtime.bind(loaded)
  Runtime.teardown()
  modules, scope = loaded, loaded.lifetime.scope()
  owner = { ShuttingDown = false, Tasks = {}, Connections = {} }
  function owner:Track(connection)
    if not connection then
      return nil
    end
    self.Connections[connection] = true
    scope.add(connection)
    return connection
  end
  function owner:TrackTask(thread)
    if not thread then
      return nil
    end
    self.Tasks[thread] = true
    scope.add(thread, function()
      if coroutine.status(thread) ~= "dead" then
        pcall(task.cancel, thread)
      end
    end)
    return thread
  end
  function owner:OnShutdown(callback) scope.add(callback) end
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
    "HttpService",
  }) do
    services[name] = game:GetService(name)
  end
  local pending = {}
  local function notify(title, message, options)
    options = options or { duration = 5 }
    if not loaded.ui.notifyCorner(title, message, options) then
      if #pending >= 6 then
        table.remove(pending, 1)
      end
      pending[#pending + 1] = { title, message, options, os.clock() }
    end
  end
  api = {
    Roblox = services,
    Player = loaded.utils.getLocalPlayer(),
    Runtime = owner,
    Config = { MapRefreshInterval = 1 },
    Features = {},
    Services = {},
    Notify = notify,
    IsActive = loaded.utils.isActive,
    Get = loaded.utils.getConfigValue,
    Util = {
      FormatError = function(message) return debug.traceback(tostring(message), 2) end,
      DestroySafely = function(instance)
        if instance then
          pcall(function() instance:Destroy() end)
        end
      end,
      IsFiniteVector3 = function(v)
        return typeof(v) == "Vector3"
          and v.X == v.X
          and v.Y == v.Y
          and v.Z == v.Z
          and math.abs(v.X) < 1000000
          and math.abs(v.Y) < 1000000
          and math.abs(v.Z) < 1000000
      end,
    },
  }
  api.Features.Noclip = {
    Acquire = function(_, lease) return loaded.noclip.acquire(lease) end,
    Release = function(_, lease) return loaded.noclip.release(lease) end,
  }
  api.Features.Invisicam = { SetSource = function(_, source, value) return loaded.invisicam.setSource(source, value) end }
  for _, entry in ipairs({ { "Coin", "mm2coin" }, { "Match", "mm2match" }, { "Drops", "mm2drops" }, { "Map", "mm2map" } }) do
    api.Services[entry[1]] = loaded[entry[2]].create(api)
  end
  for _, entry in ipairs({
    { "ESP", "mm2esp" },
    { "AutoFarm", "mm2farm" },
    { "AutoGunPickup", "mm2pickup" },
    { "MapTools", "mm2maptools" },
    { "MurderCombat", "mm2combat" },
    { "ShootMurder", "mm2shoot" },
    { "Alerts", "mm2alerts" },
  }) do
    api.Features[entry[1]] = loaded[entry[2]].create(api)
  end
  local f = api.Features
  local function toggle(target, value)
    if value then
      target:Start()
    else
      target:Stop()
    end
  end
  local bindings = {
    AutoFarm = function(v)
      if v then
        f.AutoFarm:Start()
      else
        f.AutoFarm:Stop(true)
      end
    end,
    AvoidMurdererCoins = function(v) f.AutoFarm.AvoidMurderer = v == true end,
    ResetWhenBagFull = function(v) f.AutoFarm:SetResetWhenBagFull(v) end,
    FarmSpeed = function(v) f.AutoFarm.Speed = math.clamp(tonumber(v) or 40, 5, 100) end,
    ManualShootMurder = function(v) f.ShootMurder:SetManualEnabled(v) end,
    ManualShootMurderAccuracy = function(v) f.ShootMurder:SetManualAccuracy(v) end,
    AutoShootMurder = function(v) f.ShootMurder:SetAutoEnabled(v) end,
    AutoShootMurderAccuracy = function(v) f.ShootMurder:SetAutoAccuracy(v) end,
    LegitSheriff = function(v) f.ShootMurder:SetWaitForKnife(v) end,
    AutoKnifeAttack = function(v) f.MurderCombat:SetAutoAttack(v) end,
    AutoKnifeAttackTargets = function(v) f.MurderCombat:SetAttackTargets(v) end,
    AutoKnifeThrow = function(v) f.MurderCombat:SetAutoThrow(v) end,
    AutoKnifeThrowTargets = function(v) f.MurderCombat:SetThrowTargets(v) end,
    AutoGunPickup = function(v) toggle(f.AutoGunPickup, v) end,
    GunPickupSafety = function(v) f.AutoGunPickup:SetSafetyEnabled(v) end,
    AutoTeleportToGun = function(v) f.MapTools:SetAutoGunTeleport(v) end,
    FavoriteMap = function(v) f.MapTools:SetFavoriteMaps(v) end,
    ESPEnabled = function(v) toggle(f.ESP, v) end,
    ESPShowIdentity = function(v) f.ESP.ShowIdentity = v == true end,
    ESPShowUsername = function(v) f.ESP.ShowUsername = v == true end,
    ESPShowSelf = function(v) f.ESP:SetShowSelf(v) end,
    ESPShowDistance = function(v) f.ESP.ShowDistance = v == true end,
    AlertRoleAndMurderer = function(v) f.Alerts:SetRoleAndMurdererEnabled(v) end,
    AlertGunDropped = function(v) f.Alerts:SetGunDroppedEnabled(v) end,
  }
  for _, filter in ipairs({ "Murderer", "Sheriff", "Innocent", "CandyCoin", "Gun" }) do
    bindings["ESP" .. filter] = function(value) f.ESP:SetFilter(filter, value) end
  end
  local function apply(key, value)
    if not bindings[key] then
      return
    end
    local ok, err = pcall(bindings[key], value)
    if not ok then
      loaded.utils.recordError("MM2." .. key, tostring(err))
    end
  end
  for key in pairs(bindings) do
    if key ~= "AutoFarm" and key ~= "ESPEnabled" and key ~= "AutoGunPickup" then
      apply(key, loaded.utils.getConfigValue(key))
    end
  end
  for _, key in ipairs({ "ESPEnabled", "AutoGunPickup", "AutoFarm" }) do
    apply(key, loaded.utils.getConfigValue(key))
  end
  scope.add(loaded.utils.observeConfig(function(changes)
    for key, value in pairs(changes) do
      apply(key, value)
      if value == true and key == "ManualShootMurder" then
        notify("Shoot Murder manual", "A Mini UI só aparece durante a partida quando você for Xerife ou Herói.", {
          id = "mm2.manual-shoot-role",
          duration = 5,
          color = Color3.fromRGB(70, 155, 255),
        })
      elseif value == true and key == "ManualKnifeThrow" then
        notify("Lançamento manual", "A Mini UI só aparece durante a partida quando você for Assassino.", {
          id = "mm2.manual-knife-role",
          duration = 5,
          color = Color3.fromRGB(255, 65, 65),
        })
      end
    end
  end))
  local elapsed = 0
  scope.connect(services.RunService.Heartbeat, function(dt)
    elapsed += dt
    if elapsed < 1 then
      return
    end
    elapsed = 0
    for connection in pairs(owner.Connections) do
      if connection.Connected == false then
        owner.Connections[connection] = nil
        scope.forget(connection)
      end
    end
    for thread in pairs(owner.Tasks) do
      if coroutine.status(thread) == "dead" then
        owner.Tasks[thread] = nil
        scope.forget(thread)
      end
    end
    for i = #pending, 1, -1 do
      local notice = pending[i]
      if os.clock() - notice[4] > 8 or loaded.ui.notifyCorner(notice[1], notice[2], notice[3]) then
        table.remove(pending, i)
      end
    end
  end)
  return { mode = "mm2" }
end
function Runtime.createAPI(loaded)
  local function feature(name) return api and api.Features[name] end
  local function shoot()
    local f = feature("ShootMurder")
    if not f then
      return false, "Combate ainda não carregou."
    end
    if f:TryShoot(false) then
      return true
    end
    return false, "Nenhum disparo disponível: confira o papel, a visibilidade do alvo e o intervalo da arma."
  end
  local function throw()
    local f = feature("MurderCombat")
    if not f then
      return false, "Combate ainda não carregou."
    end
    if f:ThrowManual() then
      return true
    end
    return false, "Nenhum alvo disponível na mira, ou a faca ainda está no intervalo de lançamento."
  end
  return {
    getUIConfig = function() return loaded.gameui.definition end,
    getChoices = function(name)
      local map = feature("MapTools")
      if not map then
        return { "None" }
      end
      if name == "mm2Players" then
        return map:GetPlayerOptions()
      end
      if name == "mm2Maps" then
        return map:GetFavoriteMapOptions()
      end
      return {}
    end,
    getAbilityAvailability = function(name)
      if not api then
        return false
      end
      local match = api.Services.Match
      local data = match:GetPlayerData()
      local mine = data and data[api.Player.Name]
      if not match:IsAlive(api.Player, mine) or not match:GetRoundContext() then
        return false
      end
      if name == "mm2Shoot" then
        return mine.Role == "Sheriff" or mine.Role == "Hero"
      end
      if name == "mm2Throw" then
        return mine.Role == "Murderer"
      end
      return false
    end,
    controls = { onMM2Shoot = shoot, onMM2Throw = throw },
    createActions = function()
      local function mapCall(method, ...)
        local map = feature("MapTools")
        if map then
          return map[method](map, ...)
        end
      end
      local function selected() return game:GetService("Players"):FindFirstChild(loaded.utils.getConfigValue("MapTargetPlayer") or "") end
      return {
        callbacks = {
          mm2Shoot = shoot,
          mm2Throw = throw,
          mm2Map = function() return mapCall("TeleportToMap") end,
          mm2Lobby = function() return mapCall("TeleportToLobby") end,
          mm2Murderer = function() return mapCall("TeleportToRole", "Murderer") end,
          mm2Gun = function() return mapCall("TeleportToGun") end,
          mm2GunHolder = function() return mapCall("TeleportToRole", "GunHolder") end,
          mm2Player = function() return mapCall("TeleportToPlayer", selected()) end,
          mm2Walk = function() return mapCall("WalkToPlayer", selected()) end,
        },
      }
    end,
    updateBlockers = {
      function()
        local f = feature("AutoFarm")
        return f and f.Farming
      end,
      function()
        local f = feature("AutoGunPickup")
        return f and f.Busy
      end,
    },
  }
end
Runtime.__contract = {
  provides = { "setup", "teardown", "bind", "createAPI" },
  requires = {},
}
return Runtime
