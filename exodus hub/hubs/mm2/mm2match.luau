--!optimize 2
-- @modules mm2match
-- [[ shared MM2 round state ]]
local function create(API)
  local services, player, runtime = API.Roblox, API.Player, API.Runtime
  local Match = { Data = nil, DataAt = 0, NextPoll = 0, Polling = false }
  function Match:GetRoundContext()
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
    if self.Polling or now < self.NextPoll or runtime.ShuttingDown then
      return
    end
    self.NextPoll = now + 0.5
    local remote = services.ReplicatedStorage:FindFirstChild("GetPlayerData", true)
    if not remote or not remote:IsA("RemoteFunction") then
      return
    end
    self.Polling = true
    runtime:TrackTask(task.spawn(function()
      local ok, data = pcall(function() return remote:InvokeServer() end)
      if not runtime.ShuttingDown and ok and type(data) == "table" then
        self.Data, self.DataAt = data, os.clock()
      end
      self.Polling = false
    end))
  end
  function Match:GetPlayerData()
    self:Poll()
    if os.clock() - self.DataAt <= 3 then
      return self.Data
    end
    return nil
  end
  function Match:IsAlive(target, profile)
    if not target or target:GetAttribute("Alive") == false or type(profile) ~= "table" or profile.Dead or profile.Killed then
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
  local changed
  runtime:TrackTask(task.spawn(function()
    while not runtime.ShuttingDown do
      Match:Poll()
      if not changed or not changed.Connected then
        local event = services.ReplicatedStorage:FindFirstChild("PlayerDataChanged", true)
        if event and event:IsA("RemoteEvent") then
          changed = runtime:Track(event.OnClientEvent:Connect(function(patch)
            if type(patch) ~= "table" then
              return
            end
            local data = Match.Data or {}
            for name, profile in pairs(patch) do
              if type(name) == "string" and type(profile) == "table" then
                data[name] = profile
              end
            end
            Match.Data, Match.DataAt = data, os.clock()
          end))
        end
      end
      task.wait(0.5)
    end
  end))
  return Match
end
local Module = { create = create }
function Module.setup() return true end
Module.__contract = { provides = { "setup", "create" }, requires = {} }
return Module
