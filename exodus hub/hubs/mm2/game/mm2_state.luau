-- [[ mm2 state ]]
--!optimize 2

local State = {}
local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local scope, data, bags, revision, epoch = nil, {}, {}, 0, 0
local cachedMap, mapScanAt = nil, 0
local function remote(name)
  local remotes = Storage:FindFirstChild("Remotes")
  local gameplay = remotes and remotes:FindFirstChild("Gameplay")
  return gameplay and gameplay:FindFirstChild(name)
end
local function accept(value)
  if type(value) ~= "table" then
    return
  end
  local clean = {}
  for name, profile in pairs(value) do
    if type(name) == "string" and type(profile) == "table" then
      clean[name] = { Role = profile.Role, Dead = profile.Dead == true, Killed = profile.Killed == true }
    end
  end
  data, revision = clean, revision + 1
end
function State.setup() return true end
function State.teardown()
  epoch += 1
  if scope then
    scope.destroy()
    scope = nil
  end
  data, bags, revision = {}, {}, 0
  cachedMap, mapScanAt = nil, 0
end
function State.bind(lifetime)
  State.teardown()
  scope = lifetime.child()
  local owner, generation = scope, epoch
  local bound = {}
  local fetched = false
  local function attach(name, callback)
    local source = remote(name)
    if source == bound[name] then
      return
    end
    if bound[name .. "Connection"] then
      owner.remove(bound[name .. "Connection"])
    end
    bound[name] = source
    if source and source:IsA("RemoteEvent") then
      bound[name .. "Connection"] = owner.connect(source.OnClientEvent, callback)
    end
  end
  local function discover()
    attach("PlayerDataChanged", accept)
    attach("RoundEndFade", function()
      data, bags = {}, {}
      revision += 1
    end)
    attach("CoinsStarted", function(currencies)
      bags = {}
      if type(currencies) == "table" then
        for name in pairs(currencies) do
          bags[name] = false
        end
      end
    end)
    attach("CoinCollected", function(currency, count, limit)
      if type(currency) == "string" and type(count) == "number" and type(limit) == "number" then
        bags[currency] = limit > 0 and count >= limit
      end
    end)
    local source = remote("GetCurrentPlayerData")
    if not fetched and source and source:IsA("RemoteFunction") then
      fetched = true
      local version = revision
      local thread = task.defer(function()
        local ok, result = pcall(function() return source:InvokeServer() end)
        if owner.alive and epoch == generation and revision == version and ok then
          accept(result)
        end
      end)
      owner.add(thread, function() pcall(task.cancel, thread) end)
    end
  end
  owner.connect(Storage.DescendantAdded, function(object)
    if
      object.Name == "Gameplay"
      or object.Name == "GetCurrentPlayerData"
      or object:IsA("RemoteEvent") and object.Parent and object.Parent.Name == "Gameplay"
    then
      discover()
    end
  end)
  owner.connect(workspace.ChildAdded, function()
    cachedMap, mapScanAt = nil, 0
  end)
  owner.connect(workspace.ChildRemoved, function(object)
    if object == cachedMap then
      cachedMap, mapScanAt = nil, 0
    end
  end)
  discover()
end
function State.map()
  if cachedMap and cachedMap.Parent == workspace and cachedMap:GetAttribute("MapID") ~= nil then
    return cachedMap
  end
  if os.clock() < mapScanAt then
    return
  end
  cachedMap, mapScanAt = nil, os.clock() + 0.25
  for _, object in ipairs(workspace:GetChildren()) do
    if object:IsA("Model") and object:GetAttribute("MapID") ~= nil then
      cachedMap = object
      return object
    end
  end
end
function State.profile(player) return player and data[player.Name] end
function State.role(player)
  local profile = State.profile(player)
  return profile and profile.Role
end
function State.live(player, round)
  if not player then
    return
  end
  local character = player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") or not character:IsDescendantOf(workspace) then
    return
  end
  if round then
    local profile = State.profile(player)
    if not State.map() or player:GetAttribute("Alive") ~= true or not profile or profile.Dead or profile.Killed then
      return
    end
  end
  return { player = player, character = character, humanoid = humanoid, root = root, role = State.role(player) }
end
function State.findRole(role)
  for _, player in ipairs(Players:GetPlayers()) do
    if State.role(player) == role then
      local target = State.live(player, true)
      if target then
        return target
      end
    end
  end
end
function State.full()
  local any = false
  for _, full in pairs(bags) do
    any = true
    if not full then
      return false
    end
  end
  return any
end
function State.tool(snap, name, equip)
  local tool = snap.character:FindFirstChild(name)
  local backpack = snap.player:FindFirstChildOfClass("Backpack")
  tool = tool or backpack and backpack:FindFirstChild(name)
  if not tool or not tool:IsA("Tool") then
    return
  end
  if equip and tool.Parent ~= snap.character then
    snap.humanoid:EquipTool(tool)
  end
  return tool
end
State.__contract = { provides = { "setup", "teardown", "bind", "map", "profile", "role", "live", "findRole", "full", "tool" }, requires = {} }
return State
