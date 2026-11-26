-- [[ mcpaim ]]
--!optimize 2
local Aim = {}
local native, utils, tuning, units, input, gui, world, scope, nativeAssist
local humanoids, assisted = {}, nil
-- Native touch profile is 30 degrees / Pull 9 / 72 degrees per second.
local PROFILE = { Cone = math.rad(45), Pull = 18, MaxSpeed = math.rad(180), LockBias = math.rad(4) }
function Aim.reset() assisted = nil end
function Aim.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  humanoids, assisted, nativeAssist = {}, nil, nil
end
function Aim.setup(deps)
  Aim.teardown()
  native, utils, tuning, units = deps.Native, deps.Utils, deps.Options.tuning, deps.Units
  input, gui, world = game:GetService("UserInputService"), game:GetService("GuiService"), utils.getWorkspace()
  scope = deps.Lifetime.scope()
  local function add(instance)
    if instance:IsA("Humanoid") then
      humanoids[instance] = true
    end
  end
  scope.connect(world.DescendantAdded, add)
  scope.connect(world.DescendantRemoving, function(instance) humanoids[instance] = nil end)
  for _, instance in ipairs(world:GetDescendants()) do
    add(instance)
  end
  local source = game:GetService("ReplicatedStorage"):FindFirstChild("MobileAimAssist")
  local ok, library = pcall(function() return source and require(source) end)
  if ok and type(library) == "table" and type(library.Step) == "function" then
    nativeAssist = library
  end
  return true
end
local function directionTo(snap, model, humanoid, root, lock)
  if
    not model
    or not model.Parent
    or model == snap.character
    or not model:IsA("Model")
    or model:IsDescendantOf(snap.camera)
    or model:GetAttribute("Invisible") == true
    or not humanoid
    or humanoid.Health <= 0
    or model:FindFirstChildOfClass("ForceField")
    or not root
    or not root:IsA("BasePart")
    or not root.Parent
  then
    return nil
  end
  if units.distance(root.Position, snap.root.Position) > tuning.focusRangeBlocks then
    return nil
  end
  local point = root.Position + units.offset(0, model:GetAttribute("Sneaking") == true and 3 / 64 or 5 / 32, 0)
  local delta = point - snap.camera.CFrame.Position
  if units.toBlocks(delta).Magnitude < 1 / 320 then
    return nil
  end
  if not native.visible(snap, point, model, snap.camera.CFrame.Position) then
    return nil
  end
  if lock and not native.visible(snap, point, model) then
    return nil
  end
  return delta.Unit
end
local function assistTarget(snap, look)
  local best, direction, score
  -- Native-style angular selection, across all living humanoids: no player/selected-target whitelist.
  for human in pairs(humanoids) do
    local model = human.Parent
    local root = model and model:FindFirstChild("HumanoidRootPart")
    local aim = directionTo(snap, model, human, root, false)
    if not aim then
      continue
    end
    local angle = math.acos(math.clamp(look:Dot(aim), -1, 1))
    if angle > PROFILE.Cone then
      continue
    end
    local rank = angle - (model == assisted and PROFILE.LockBias or 0)
    if score == nil or rank < score then
      best, direction, score = model, aim, rank
    end
  end
  assisted = best
  return direction
end
local function assistStep(look, target, dt)
  if nativeAssist then
    local ok, direction = pcall(nativeAssist.Step, look, target, dt, PROFILE)
    if ok and typeof(direction) == "Vector3" and direction.Magnitude > 0.001 then
      return direction.Unit
    end
    nativeAssist = nil
  end
  -- Same stateless native Step formula when the shared module is unavailable.
  local angle = math.acos(math.clamp(look:Dot(target), -1, 1))
  if angle < math.rad(0.35) then
    return look
  end
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 15)
  local turn = math.min(angle * (1 - math.exp(-PROFILE.Pull * elapsed)), PROFILE.MaxSpeed * elapsed)
  local axis = look:Cross(target)
  if axis.Magnitude < 1e-6 then
    return look
  end
  return CFrame.fromAxisAngle(axis.Unit, turn):VectorToWorldSpace(look)
end
local function apply(camera, direction)
  local look, eye = camera.CFrame.LookVector, camera.CFrame.Position
  local angle = math.acos(math.clamp(look:Dot(direction), -1, 1))
  if angle < 1e-6 then
    return
  end
  local axis = look:Cross(direction)
  if axis.Magnitude < 1e-6 then
    axis = camera.CFrame.UpVector
  end
  camera.CFrame = CFrame.new(eye) * CFrame.fromAxisAngle(axis.Unit, angle) * camera.CFrame.Rotation
end
function Aim.step(snap, focus, dt)
  local lock, assist = utils.getConfigValue("MCAimLock"), utils.getConfigValue("MCAimAssist")
  if not (lock or assist) or input:GetFocusedTextBox() or gui.MenuIsOpen or native.blocked(snap) then
    Aim.reset()
    return
  end
  -- Lock is direct and fixed-strength. Assist never weakens an available combat lock.
  if lock and focus then
    local direction = directionTo(snap, focus.character, focus.humanoid, focus.root, true)
    if direction then
      apply(snap.camera, direction)
      assisted = focus.character
      return
    end
  end
  if not assist then
    Aim.reset()
    return
  end
  local look = snap.camera.CFrame.LookVector
  local direction = assistTarget(snap, look)
  if direction then
    apply(snap.camera, assistStep(look, direction, dt))
  end
end
Aim.__contract = {
  provides = { "setup", "reset", "teardown", "step" },
  requires = { Native = "mcpnative", Utils = "utils", Options = "mcpoptions", Units = "mcpunits", Lifetime = "lifetime" },
  requiresData = { Options = { "tuning" } },
  requiresMethods = {
    Units = { "distance", "offset", "toBlocks" },
    Native = { "blocked", "visible" },
    Utils = { "getConfigValue", "getWorkspace" },
    Lifetime = { "scope" },
  },
}
return Aim
