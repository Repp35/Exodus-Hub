-- [[ anti fling ]]
--!optimize 2
-- @modules antifling

local AntiFling = {}
local controller, utils, scope
local players = game:GetService("Players")
local bindings = {}
local ownCharacter, ownRoot, safeCFrame
local ignoreUntil = 0
local CONFIG = { schema = { UniversalAntiFling = "boolean" }, defaults = { UniversalAntiFling = false } }
local function clear()
  for player, binding in pairs(bindings) do
    binding.destroy()
    bindings[player] = nil
  end
  ownCharacter, ownRoot, safeCFrame = nil, nil, nil
end
local function track(player)
  if player == utils.getLocalPlayer() or bindings[player] then
    return
  end
  local binding = scope.child()
  bindings[player] = binding
  local characterScope
  local function bind(character)
    if characterScope then
      characterScope.destroy()
    end
    characterScope = binding.child()
    if not character then
      return
    end
    local seen = {}
    local function add(part)
      if not part:IsA("BasePart") or seen[part] then
        return
      end
      local partScope = characterScope.child()
      seen[part] = partScope
      local original, writing = part.CanCollide, false
      local function apply()
        if writing or not part.Parent or not part.CanCollide then
          return
        end
        writing = true
        part.CanCollide = false
        writing = false
      end
      partScope.add(function()
        seen[part] = nil
        if part.Parent and part.CanCollide == false then
          part.CanCollide = original
        end
      end)
      partScope.connect(part:GetPropertyChangedSignal("CanCollide"), function()
        if not writing and part.CanCollide then
          original = part.CanCollide
          apply()
        end
      end)
      apply()
    end
    characterScope.connect(character.DescendantAdded, add)
    characterScope.connect(character.DescendantRemoving, function(part)
      if seen[part] then
        seen[part].destroy()
      end
    end)
    for _, part in ipairs(character:GetDescendants()) do
      add(part)
    end
  end
  binding.connect(player.CharacterAdded, bind)
  binding.connect(player.CharacterRemoving, function() bind(nil) end)
  bind(player.Character)
end
local function finite(vector)
  return vector.X == vector.X
    and vector.Y == vector.Y
    and vector.Z == vector.Z
    and math.abs(vector.X) < math.huge
    and math.abs(vector.Y) < math.huge
    and math.abs(vector.Z) < math.huge
end
local function guard()
  local player = utils.getLocalPlayer()
  local character = player and player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  if character ~= ownCharacter or root ~= ownRoot then
    ownCharacter, ownRoot, safeCFrame = character, root, nil
  end
  if not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
    return
  end
  local now = os.clock()
  if now < ignoreUntil or utils.getConfigValue("UniversalFly") == true or humanoid.Sit or humanoid.PlatformStand then
    safeCFrame = nil
    return
  end
  local linear, angular = root.AssemblyLinearVelocity, root.AssemblyAngularVelocity
  local maxSpeed = math.max(250, humanoid.WalkSpeed * 5, humanoid.JumpPower * 3)
  local horizontal = Vector3.new(linear.X, 0, linear.Z).Magnitude
  -- Freefall alone is not a fling. Preserve ordinary falls, jumps and game teleports.
  local violent = not finite(linear) or not finite(angular) or horizontal > maxSpeed or angular.Magnitude > 100
  if violent then
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if safeCFrame then
      root.CFrame = safeCFrame
    end
    ignoreUntil = now + 0.25
  elseif humanoid.FloorMaterial ~= Enum.Material.Air and finite(root.Position) then
    safeCFrame = root.CFrame
  end
end
function AntiFling.allowTeleport(duration)
  ignoreUntil = os.clock() + math.clamp(tonumber(duration) or 0.5, 0, 5)
  safeCFrame = nil
end
function AntiFling.setEnabled(value)
  if not controller then
    return false, "recurso indisponível"
  end
  return controller.setEnabled(value)
end
function AntiFling.teardown()
  if controller then
    controller.destroy()
    controller = nil
  end
  clear()
  utils, scope, ignoreUntil = nil, nil, 0
  return true
end
function AntiFling.setup(deps)
  AntiFling.teardown()
  utils = deps.Utils
  controller = deps.Controller.create(utils, deps.Lifetime, {
    key = "UniversalAntiFling",
    start = function(activeScope)
      scope = activeScope
      scope.connect(players.PlayerAdded, track)
      scope.connect(players.PlayerRemoving, function(player)
        if bindings[player] then
          bindings[player].destroy()
          bindings[player] = nil
        end
      end)
      for _, player in ipairs(players:GetPlayers()) do
        track(player)
      end
      local run = game:GetService("RunService")
      scope.connect(run.PreSimulation or run.Stepped, guard)
    end,
    stop = clear,
  })
  return controller.sync()
end
AntiFling.__config = CONFIG
AntiFling.__contract = {
  access = { methods = { allowTeleport = "world.write" } },
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "trackGlobal", "untrackGlobal", "recordError" },
    Lifetime = { "scope" },
    Controller = { "create" },
  },
  provides = { "setup", "teardown", "setEnabled", "allowTeleport" },
}
return AntiFling
