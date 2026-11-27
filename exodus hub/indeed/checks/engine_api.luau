-- [[ engine api ]]

-- code
local function signal()
  local event, listeners = {}, {}
  function event:Connect(callback)
    local connection = { Connected = true }
    listeners[connection] = callback
    function connection:Disconnect()
      self.Connected = false
      listeners[self] = nil
    end
    return connection
  end
  function event:Fire(...)
    for connection, callback in pairs(listeners) do
      if connection.Connected then
        callback(...)
      end
    end
  end
  return event
end
local function node(name)
  local object = {
    Name = name,
    Parent = true,
    ChildAdded = signal(),
    ChildRemoved = signal(),
    DescendantAdded = signal(),
    DescendantRemoving = signal(),
    AncestryChanged = signal(),
  }

  function object:FindFirstChild() return nil end
  function object:FindFirstChildOfClass() return nil end
  function object:GetAttribute() return nil end
  function object:GetAttributeChangedSignal() return signal() end
  function object:GetPropertyChangedSignal() return signal() end
  function object:GetChildren() return {} end
  function object:IsA(kind) return kind == self.Name end
  function object:GetServerTimeNow() return os.clock() end
  return object
end
local services = {}
local player = node("Player")
player.UserId = 1
player.Idled = signal()
player.CharacterAdded = signal()
player.CharacterRemoving = signal()
services.Players = node("Players")
services.Players.LocalPlayer = player
services.Players.PlayerAdded = signal()
services.Players.PlayerRemoving = signal()
function services.Players:GetPlayers() return { player } end
function services.Players:GetPlayerByUserId(id) return id == player.UserId and player or nil end
services.RunService = node("RunService")
for _, name in ipairs({ "Heartbeat", "PostSimulation", "PreSimulation", "PreRender", "RenderStepped", "Stepped" }) do
  services.RunService[name] = signal()
end
local game = { PlaceId = 0 }
function game:GetService(name)
  if not services[name] then
    services[name] = node(name)
  end
  return services[name]
end
local input = game:GetService("UserInputService")
for _, name in ipairs({ "InputBegan", "InputEnded", "InputChanged", "WindowFocusReleased", "LastInputTypeChanged", "JumpRequest" }) do
  input[name] = signal()
end
function input:GetFocusedTextBox() return nil end
local teleport = game:GetService("TeleportService")
teleport.TeleportInitFailed = signal()
local collection = game:GetService("CollectionService")
function collection:GetTagged() return {} end
function collection:GetInstanceAddedSignal() return signal() end
function collection:GetInstanceRemovedSignal() return signal() end
local workspace = game:GetService("Workspace")
local enumCache = {}
local Enum = setmetatable({}, {
  __index = function(_, group)
    if not enumCache[group] then
      enumCache[group] = setmetatable({}, {
        __index = function(self, key)
          local item = { Name = key, EnumType = self, __kind = "EnumItem" }
          rawset(self, key, item)
          return item
        end,
      })
    end
    return enumCache[group]
  end,
})
local function constructor() return {} end
local Color3 = { new = constructor, fromRGB = constructor }
local Vector3 = { new = constructor, zero = {} }
local Vector2 = { new = constructor, zero = {} }
local UDim = { new = constructor }
local UDim2 = { new = constructor, fromOffset = constructor, fromScale = constructor }
local CFrame = { new = constructor }
local NumberSequence = { new = constructor }
local ColorSequence = { new = constructor }
local ColorSequenceKeypoint = { new = constructor }
local NumberRange = { new = constructor }
local Random = { new = constructor }
local TweenInfo = { new = constructor }
local _G = {}
local task = { delay = function() end, defer = function() end, spawn = function() end }
local function warn() end
local loaded = {}
local nativeTypeof = typeof
local function typeof(value) return type(value) == "table" and value.__kind or nativeTypeof(value) end
local environment = getfenv()
local environmentMeta = table.clone(getmetatable(environment) or {})
environmentMeta.__newindex = function(_, key) error("Module assigned an undeclared global: " .. tostring(key)) end
setmetatable(environment, environmentMeta)
