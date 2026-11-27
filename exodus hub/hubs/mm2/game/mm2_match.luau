-- [[ mm2 match ]]
--!optimize 2

-- module
local Match = {}
function Match.setup() return true end

-- instance
function Match.create(deps)
  local services, player, runtime = deps.services, deps.player, deps.runtime
  local match = {}
  local profiles, nextRead, pending, revision = nil, 0, false, 0
  local changedRemote

  -- rounds
  function match:GetRoundContext()
    for _, map in ipairs(services.Workspace:GetChildren()) do
      if map:IsA("Model") and map:GetAttribute("MapID") ~= nil then
        local coins = map:FindFirstChild("CoinContainer")
        if coins and not (coins:IsA("Folder") or coins:IsA("Model")) then
          coins = nil
        end
        return true, map, coins
      end
    end
    return false
  end
  function match:GetContext()
    local active, _, coins = self:GetRoundContext()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if
      not active
      or not coins
      or player:GetAttribute("Alive") ~= true
      or not character
      or not character:IsDescendantOf(services.Workspace)
      or not humanoid
      or humanoid.Health <= 0
      or not root
      or not root:IsA("BasePart")
    then
      return false
    end
    return true, character, humanoid, root, coins
  end

  -- profiles
  local function invalidate()
    revision += 1
    profiles, nextRead = nil, 0
  end
  local function bindChanges()
    local remote = services.ReplicatedStorage:FindFirstChild("PlayerDataChanged", true)
    if not remote or not remote:IsA("RemoteEvent") or remote == changedRemote then
      return
    end
    changedRemote = remote
    runtime:Track(remote.OnClientEvent:Connect(function(changes)
      if runtime.ShuttingDown or type(changes) ~= "table" then
        return
      end
      revision += 1
      profiles = profiles or {}
      for name, profile in pairs(changes) do
        if type(name) == "string" and type(profile) == "table" then
          profiles[name] = profile
        end
      end
      nextRead = 0
    end))
  end
  function match:GetPlayerData()
    if runtime.ShuttingDown then
      return nil
    end
    bindChanges()
    if pending or os.clock() < nextRead then
      return profiles
    end
    nextRead = os.clock() + 0.5
    local remote = services.ReplicatedStorage:FindFirstChild("GetPlayerData", true)
    if not remote or not remote:IsA("RemoteFunction") then
      return profiles
    end
    local started = revision
    pending = true
    runtime:TrackTask(task.defer(function()
      local ok, data = pcall(remote.InvokeServer, remote)
      pending = false
      if runtime.ShuttingDown then
        return
      end
      if started == revision then
        profiles = ok and type(data) == "table" and data or nil
      end
      nextRead = os.clock() + 0.5
    end))
    return profiles
  end
  function match:GetLocalRole()
    local data = self:GetPlayerData()
    local profile = data and data[player.Name]
    if type(profile) == "table" and profile.Dead ~= true and profile.Killed ~= true then
      return profile.Role
    end
    return nil
  end

  -- lifecycle
  local bound = setmetatable({}, { __mode = "k" })
  local function bindRound(instance)
    if bound[instance] or not instance:IsA("RemoteEvent") then
      return
    end
    if instance.Name ~= "RoundStart" and instance.Name ~= "RoundEndFade" and instance.Name ~= "CoinsStarted" then
      return
    end
    local gameplay = instance.Parent
    if not gameplay or gameplay.Name ~= "Gameplay" then
      return
    end
    bound[instance] = true
    runtime:Track(instance.OnClientEvent:Connect(invalidate))
  end
  local remotes = services.ReplicatedStorage:FindFirstChild("Remotes")
  local gameplay = remotes and remotes:FindFirstChild("Gameplay")
  if gameplay then
    for _, event in ipairs(gameplay:GetChildren()) do
      bindRound(event)
    end
  end
  runtime:Track(services.ReplicatedStorage.DescendantAdded:Connect(bindRound))
  runtime:Track(player.CharacterAdded:Connect(invalidate))
  runtime:OnShutdown(invalidate)
  return match
end

-- contract
Match.__contract = { provides = { "setup", "create" }, requires = {} }
return Match
