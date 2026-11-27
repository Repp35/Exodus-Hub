--!optimize 2
-- @modules mm2match
-- [[ shared MM2 round state ]]
local function create(API)
  local services, player, runtime = API.Roblox, API.Player, API.Runtime
  local Match = { Data = nil, DataAt = 0, NextPoll = 0, Polling = false, Generation = 0, RoundEnded = false }
  local request, requestTimer
  local function gameplay()
    local remotes = services.ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Gameplay")
  end
  function Match:GetRemote(names, class)
    local folder = gameplay()
    for _, name in ipairs(names) do
      local remote = folder and folder:FindFirstChild(name)
      if remote and remote:IsA(class) then
        return remote
      end
      remote = services.ReplicatedStorage:FindFirstChild(name, true)
      if remote and remote:IsA(class) then
        return remote
      end
    end
    return nil
  end
  local function normalize(data)
    if type(data) ~= "table" then
      return nil
    end
    data = type(data.PlayerData) == "table" and data.PlayerData or data
    local profiles = {}
    for key, profile in pairs(data) do
      if type(profile) == "table" then
        local target = services.Players:FindFirstChild(tostring(key))
        local id = tonumber(key)
        if not target and id then
          target = services.Players:GetPlayerByUserId(id)
        end
        local name = target and target.Name or type(key) == "string" and key
        if name then
          profiles[name] = profile
        end
      end
    end
    return profiles
  end
  function Match:Invalidate(ended)
    self.Generation += 1
    self.Data, self.DataAt, self.NextPoll, self.Polling = nil, 0, 0, false
    if ended ~= nil then
      self.RoundEnded = ended
    end
    if request then
      pcall(task.cancel, request)
      request = nil
    end
    if requestTimer then
      pcall(task.cancel, requestTimer)
      requestTimer = nil
    end
  end
  function Match:GetRoundContext()
    if self.RoundEnded then
      return false
    end
    for _, map in ipairs(services.Workspace:GetChildren()) do
      if map:IsA("Model") and (map:GetAttribute("MapID") ~= nil or map:FindFirstChild("CoinContainer")) then
        local container = map:FindFirstChild("CoinContainer")
        if container and not (container:IsA("Folder") or container:IsA("Model")) then
          container = nil
        end
        return true, map, container
      end
    end
    return false
  end
  function Match:Poll()
    local now = os.clock()
    if self.Polling or now < self.NextPoll or runtime.ShuttingDown or self.RoundEnded then
      return
    end
    self.NextPoll = now + 0.5
    local remote = self:GetRemote({ "GetCurrentPlayerData", "GetPlayerData" }, "RemoteFunction")
    if not remote then
      return
    end
    self.Polling = true
    local generation = self.Generation
    request = runtime:TrackTask(task.spawn(function()
      local ok, data = pcall(function() return remote:InvokeServer() end)
      if self.Generation ~= generation or runtime.ShuttingDown then
        return
      end
      if ok and type(data) == "table" then
        self.Data, self.DataAt = normalize(data), os.clock()
      end
      self.Polling = false
      if requestTimer then
        pcall(task.cancel, requestTimer)
        requestTimer = nil
      end
    end))
    if self.Polling then
      requestTimer = runtime:TrackTask(task.delay(4, function()
        requestTimer = nil
        if self.Generation == generation and self.Polling then
          self:Invalidate()
        end
      end))
    end
  end
  function Match:GetPlayerData()
    self:Poll()
    if os.clock() - self.DataAt <= 3 then
      return self.Data
    end
    return nil
  end
  function Match:IsAlive(target, profile)
    if not target or target:GetAttribute("Alive") == false or type(profile) ~= "table" or profile.Dead == true or profile.Killed == true then
      return false
    end
    local character = target.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return character ~= nil and character:IsDescendantOf(services.Workspace) and humanoid ~= nil and humanoid.Health > 0
  end
  function Match:GetLocalRole()
    local data = self:GetPlayerData()
    local mine = data and data[player.Name]
    return type(mine) == "table" and mine.Role or nil
  end
  function Match:GetContext()
    local active, _, container = self:GetRoundContext()
    local data = self:GetPlayerData()
    if not active or not self:IsAlive(player, data and data[player.Name]) then
      return false
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
      return false
    end
    return true, character, character:FindFirstChildOfClass("Humanoid"), root, container
  end
  local events = {}
  local function bind(name, callback)
    local event = Match:GetRemote({ name }, "RemoteEvent")
    local previous = events[name]
    if previous and previous.remote == event then
      return
    end
    if previous then
      previous.connection:Disconnect()
      events[name] = nil
    end
    if event then
      events[name] = { remote = event, connection = runtime:Track(event.OnClientEvent:Connect(callback)) }
    end
  end
  runtime:TrackTask(task.spawn(function()
    while not runtime.ShuttingDown do
      Match:Poll()
      bind("RoundEndFade", function() Match:Invalidate(true) end)
      bind("RoundStart", function() Match:Invalidate(false) end)
      bind("PlayerDataChanged", function(patch)
        if Match.RoundEnded then
          return
        end
        local data = normalize(patch)
        if not data then
          return
        end
        -- CurrentRoundClient publishes a complete snapshot, not a delta.
        if not Match:GetRemote({ "GetCurrentPlayerData" }, "RemoteFunction") then
          local merged = table.clone(Match.Data or {})
          for name, profile in pairs(data) do
            merged[name] = profile
          end
          data = merged
        end
        Match.Data, Match.DataAt = data, os.clock()
      end)
      task.wait(0.5)
    end
  end))
  runtime:OnShutdown(function() Match:Invalidate(true) end)
  return Match
end
local Module = { create = create }
function Module.setup() return true end
Module.__contract = { provides = { "setup", "create" }, requires = {} }
return Module
