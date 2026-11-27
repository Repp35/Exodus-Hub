-- [[ shared dropped gun index ]]
--!optimize 2
local Module = {}
function Module.setup() return true end
function Module.create(API)
  local workspace, collection = API.Roblox.Workspace, API.Roblox.CollectionService
  local runtime, players = API.Runtime, API.Roblox.Players
  local records, tagged, listeners = {}, {}, {}
  local Drops = {}
  local function held(object)
    for _, player in ipairs(players:GetPlayers()) do
      local model = player.Character
      if model and object:IsDescendantOf(model) then
        return true
      end
    end
    return false
  end
  local function add(object)
    if records[object] or not object.Parent or object.Name ~= "GunDrop" and not tagged[object] then
      return
    end
    if not object:IsDescendantOf(workspace) or held(object) then
      return
    end
    records[object] = true
    for connection, callback in pairs(listeners) do
      if connection.Connected then
        callback(object)
      end
    end
  end
  function Drops:GetPart(object)
    if not object or not object.Parent then
      return nil
    end
    if object:IsA("BasePart") then
      return object
    end
    if object:IsA("Model") and object.PrimaryPart then
      return object.PrimaryPart
    end
    return object:FindFirstChildWhichIsA("BasePart", true)
  end
  function Drops:GetAll()
    local result = {}
    for object in pairs(records) do
      if object.Parent and object:IsDescendantOf(workspace) and not held(object) then
        result[#result + 1] = object
      else
        records[object] = nil
      end
    end
    return result
  end
  function Drops:ObserveAdded(callback)
    local connection = { Connected = true }
    listeners[connection] = callback
    function connection:Disconnect()
      self.Connected = false
      listeners[self] = nil
    end
    return connection
  end
  runtime:Track(workspace.DescendantAdded:Connect(add))
  runtime:Track(workspace.DescendantRemoving:Connect(function(object) records[object] = nil end))
  runtime:Track(collection:GetInstanceAddedSignal("GunDrop"):Connect(function(object)
    tagged[object] = true
    add(object)
  end))
  runtime:Track(collection:GetInstanceRemovedSignal("GunDrop"):Connect(function(object)
    tagged[object] = nil
    if object.Name ~= "GunDrop" then
      records[object] = nil
    end
  end))
  for _, object in ipairs(collection:GetTagged("GunDrop")) do
    tagged[object] = true
    add(object)
  end
  if type(workspace.GetDescendants) == "function" then
    for _, object in ipairs(workspace:GetDescendants()) do
      if object.Name == "GunDrop" then
        add(object)
      end
    end
  end
  runtime:OnShutdown(function()
    table.clear(records)
    table.clear(tagged)
    table.clear(listeners)
  end)
  return Drops
end
Module.__contract = { provides = { "setup", "create" }, requires = {} }
return Module
