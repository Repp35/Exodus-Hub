-- [[ noclip ]]
--!optimize 2
-- @modules noclip

local Noclip = {}
local controller, rootScope, physicsScope, bindingScope
local utils, lifetime, scheduler, player, character
local owners, parts = {}, {}
local CONFIG = { schema = { UniversalNoclip = "boolean" }, defaults = { UniversalNoclip = false } }

local function restorePart(part)
  local entry = parts[part]
  if not entry then return end
  parts[part] = nil
  entry.scope.destroy()
  if part.Parent then
    pcall(function() part.CanCollide = entry.original end)
  end
end
local function restoreCharacter()
  if bindingScope then
    bindingScope.destroy()
    bindingScope = nil
  end
  character = nil
  for part in pairs(parts) do restorePart(part) end
end
local function enforce(part, entry)
  if parts[part] ~= entry or not character or not part:IsDescendantOf(character) then return end
  if part.CanCollide then part.CanCollide = false end
end
local function watchPart(part)
  if not part:IsA("BasePart") or parts[part] then return end
  local entry = { original = part.CanCollide, scope = bindingScope.child() }
  parts[part] = entry
  entry.scope.connect(part:GetPropertyChangedSignal("CanCollide"), function()
    enforce(part, entry)
  end)
  enforce(part, entry)
end
local function bindCharacter(nextCharacter)
  if character == nextCharacter then return end
  restoreCharacter()
  if not nextCharacter then return end
  character, bindingScope = nextCharacter, rootScope.child()
  bindingScope.connect(character.DescendantAdded, watchPart)
  bindingScope.connect(character.DescendantRemoving, restorePart)
  for _, part in ipairs(character:GetDescendants()) do watchPart(part) end
end
local function step()
  if not next(owners) then return end
  local current = player and player.Character
  if current and not current.Parent then current = nil end
  bindCharacter(current)
  for part, entry in pairs(parts) do
    if not part.Parent or not character or not part:IsDescendantOf(character) then
      restorePart(part)
    else
      enforce(part, entry)
    end
  end
end
local function stopPhysics()
  if physicsScope then
    physicsScope.destroy()
    physicsScope = nil
  end
  restoreCharacter()
end
function Noclip.isEnabled() return next(owners) ~= nil end
function Noclip.acquire(owner)
  if owner == nil or not rootScope or not rootScope.alive then return false end
  owners[owner] = true
  if not physicsScope then
    physicsScope = rootScope.child()
    scheduler.connectPhysics(physicsScope, step)
  end
  step()
  return true
end
function Noclip.release(owner)
  if owner ~= nil then owners[owner] = nil end
  if not next(owners) then stopPhysics() end
  return true
end
function Noclip.setEnabled(value)
  if value ~= true then table.clear(owners); stopPhysics() end
  if not controller then return false, "recurso indisponível" end
  return controller.setEnabled(value)
end
function Noclip.teardown()
  if controller then controller.destroy(); controller = nil end
  table.clear(owners)
  stopPhysics()
  if rootScope then rootScope.destroy(); rootScope = nil end
  utils, lifetime, scheduler, player = nil, nil, nil, nil
  return true
end
function Noclip.setup(deps)
  Noclip.teardown()
  utils, lifetime, scheduler = deps.Utils, deps.Lifetime, deps.Controller
  player, rootScope = utils.getLocalPlayer(), lifetime.scope()
  local cleanup = { Disconnect = rootScope.destroy }
  utils.trackGlobal(cleanup)
  rootScope.add(function() utils.untrackGlobal(cleanup) end)
  rootScope.add(function() table.clear(owners); stopPhysics() end)
  if player then
    rootScope.connect(player.CharacterAdded, function(current)
      if next(owners) then bindCharacter(current); step() end
    end)
    rootScope.connect(player.CharacterRemoving, function(current)
      if character == current then restoreCharacter() end
    end)
  end
  controller = scheduler.create(utils, lifetime, {
    key = "UniversalNoclip",
    start = function() return Noclip.acquire(Noclip) end,
    stop = function() table.clear(owners); stopPhysics() end,
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
  provides = { "setup", "teardown", "setEnabled", "isEnabled", "acquire", "release" },
}
return Noclip
