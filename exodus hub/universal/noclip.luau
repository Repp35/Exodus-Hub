-- [[ noclip ]]
--!optimize 2
-- @modules noclip

local Noclip = {}
local controller, state, scope
local CONFIG = { schema = { UniversalNoclip = "boolean" }, defaults = { UniversalNoclip = false } }
local function create(utils, resources, connectPhysics)
  local Services = { RunService = game:GetService("RunService") }
  local Player = utils.getLocalPlayer()
  local Runtime = {
    ShuttingDown = false,
    ConnectPhysics = function(_, callback)
      local physics = resources.child()
      connectPhysics(physics, callback, Services.RunService.Stepped)
      return { Disconnect = physics.destroy }
    end,
    Track = function(_, connection) return resources.add(connection) end,
    OnShutdown = function(_, cleanup) resources.add(cleanup) end,
  }
  local State = {
    Enabled = false,
    Owners = {},
    Character = nil,
    SteppedConnection = nil,
    DescendantConnection = nil,
    RemovingConnection = nil,
    OriginalCanCollide = {},
    BindGeneration = 0,
    BindThread = nil,
  }

  local function hasOwners() return next(State.Owners) ~= nil end
  local function disconnect(connection)
    if connection then
      pcall(function() connection:Disconnect() end)
    end
  end
  local function cancelPendingBind()
    local thread = State.BindThread
    State.BindThread = nil
    if thread then
      pcall(task.cancel, thread)
    end
  end
  local function disablePart(part)
    if not part:IsA("BasePart") then
      return
    end
    local readOk, canCollide = pcall(function() return part.CanCollide end)
    if not readOk then
      return
    end
    if State.OriginalCanCollide[part] == nil then
      State.OriginalCanCollide[part] = canCollide
    end
    pcall(function() part.CanCollide = false end)
  end
  function State:_RestoreBinding()
    cancelPendingBind()
    disconnect(self.SteppedConnection)
    self.SteppedConnection = nil
    disconnect(self.DescendantConnection)
    self.DescendantConnection = nil
    disconnect(self.RemovingConnection)
    self.RemovingConnection = nil
    for part, canCollide in pairs(self.OriginalCanCollide) do
      if part.Parent then
        pcall(function() part.CanCollide = canCollide end)
      end
    end
    table.clear(self.OriginalCanCollide)
    self.Character = nil
  end
  function State:_BindCharacter(character)
    self.BindGeneration += 1
    local generation = self.BindGeneration
    if character and self.Character == character then
      return
    end
    self:_RestoreBinding()
    if not character or not hasOwners() then
      return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
      local thread
      thread = task.defer(function()
        local candidate = character:WaitForChild("Humanoid", 10)
        if self.BindThread == thread then
          self.BindThread = nil
        end
        if candidate and candidate:IsA("Humanoid") and self.BindGeneration == generation and hasOwners() and Player.Character == character then
          self:_BindCharacter(character)
        end
      end)
      self.BindThread = thread
      return
    end
    if humanoid.Health <= 0 then
      return
    end
    self.Character = character
    for _, descendant in ipairs(character:GetDescendants()) do
      disablePart(descendant)
    end
    self.DescendantConnection = character.DescendantAdded:Connect(function(descendant)
      if self.Character == character and hasOwners() then
        disablePart(descendant)
      end
    end)
    self.RemovingConnection = character.DescendantRemoving:Connect(function(part)
      local previous = self.OriginalCanCollide[part]
      if previous ~= nil then
        self.OriginalCanCollide[part] = nil
        pcall(function() part.CanCollide = previous end)
      end
    end)
    self.SteppedConnection = Runtime:ConnectPhysics(function()
      if self.Character ~= character or not hasOwners() then
        self:_RestoreBinding()
        return
      end
      if Player.Character ~= character then
        return
      end
      for part in pairs(self.OriginalCanCollide) do
        if part.Parent then
          pcall(function() part.CanCollide = false end)
        else
          self.OriginalCanCollide[part] = nil
        end
      end
    end)
  end
  function State:Acquire(owner)
    if owner == nil then
      return false
    end
    self.Owners[owner] = true
    self:_BindCharacter(Player.Character)
    return true
  end
  function State:Release(owner)
    if owner ~= nil then
      self.Owners[owner] = nil
    end
    if not hasOwners() then
      self:_RestoreBinding()
    elseif not self.Character then
      self:_BindCharacter(Player.Character)
    end
  end
  function State:Start()
    if self.Enabled or Runtime.ShuttingDown then
      return
    end
    self.Enabled = true
    self:Acquire(self)
  end
  function State:Stop()
    self.Enabled = false
    self:Release(self)
  end
  Runtime:Track(Player.CharacterAdded:Connect(function(character)
    if hasOwners() then
      State:_BindCharacter(character)
    end
  end))
  Runtime:Track(Player.CharacterRemoving:Connect(function(character)
    if State.Character == character or State.BindThread then
      State:_BindCharacter(nil)
    end
  end))
  Runtime:OnShutdown(function() State:Stop() end)

  resources.add(function()
    Runtime.ShuttingDown = true
    table.clear(State.Owners)
    State:_BindCharacter(nil)
  end)
  return State
end
function Noclip.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function Noclip.acquire(owner) return state and state:Acquire(owner) or false end
function Noclip.release(owner)
  if not state then
    return false
  end
  state:Release(owner)
  return true
end
function Noclip.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  if scope then
    scope.destroy()
    scope = nil
  end
  state = nil
  return true
end
function Noclip.setup(deps)
  Noclip.teardown()
  local utils = deps.Utils
  scope = deps.Lifetime.scope()
  state = create(utils, scope, deps.Controller.connectPhysics)
  local cleanup = { Disconnect = scope.destroy }
  utils.trackGlobal(cleanup)
  scope.add(function() utils.untrackGlobal(cleanup) end)
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "UniversalNoclip",
    start = function() state:Start() end,
    stop = function() state:Stop() end,
  })
  return controller.sync()
end
Noclip.__config = CONFIG
Noclip.__contract = {
  access = { methods = { acquire = "world.write", release = "world.write" } },
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create", "connectPhysics" },
  },
  provides = { "setup", "teardown", "setEnabled", "acquire", "release" },
}
return Noclip
