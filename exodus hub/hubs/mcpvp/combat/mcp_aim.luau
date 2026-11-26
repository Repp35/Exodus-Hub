-- [[ mcpaim ]]
--!optimize 2
local Aim = {}
local native, utils, tuning, units, input, gui, world, scope, nativeAssist
local humanoids, assisted, lockModel, lockSpeed = {}, nil, nil, 0
-- Native touch profile is 30 degrees / Pull 9 / 72 degrees per second.
local PROFILE = { Cone = math.rad(35), Pull = 7, MaxSpeed = math.rad(60), LockBias = math.rad(3) }
function Aim.reset()
  assisted, lockModel, lockSpeed = nil, nil, 0
end
function Aim.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  humanoids, nativeAssist = {}, nil
  Aim.reset()
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
  local distance = units.distance(root.Position, snap.root.Position)
  if distance > (lock and tuning.focusRangeBlocks or tuning.assistRangeBlocks) then
    return nil
  end
  local point = native.aimPoint(model, root)
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
  return delta.Unit, distance
end
local function assistTarget(snap, look)
  local best, direction, score, bestDistance
  -- Native-style angular selection, across all living humanoids: no player/selected-target whitelist.
  for human in pairs(humanoids) do
    local model = human.Parent
    local root = model and model:FindFirstChild("HumanoidRootPart")
    local aim, distance = directionTo(snap, model, human, root, false)
    if not aim then
      continue
    end
    local angle = math.acos(math.clamp(look:Dot(aim), -1, 1))
    if angle > PROFILE.Cone then
      continue
    end
    local rank = angle - (model == assisted and PROFILE.LockBias or 0)
    if score == nil or rank < score then
      best, direction, score, bestDistance = model, aim, rank, distance
    end
  end
  assisted = best
  return direction, bestDistance
end
local function assistStep(look, target, dt, distance)
  local falloff = 1 - 0.65 * math.clamp((distance - tuning.focusRangeBlocks) / (tuning.assistRangeBlocks - tuning.focusRangeBlocks), 0, 1)
  local profile = { Pull = PROFILE.Pull * falloff, MaxSpeed = PROFILE.MaxSpeed * falloff }
  if nativeAssist then
    local ok, direction = pcall(nativeAssist.Step, look, target, dt, profile)
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
  local turn = math.min(angle * (1 - math.exp(-profile.Pull * elapsed)), profile.MaxSpeed * elapsed)
  local axis = look:Cross(target)
  if axis.Magnitude < 1e-6 then
    return look
  end
  return CFrame.fromAxisAngle(axis.Unit, turn):VectorToWorldSpace(look)
end
local function apply(camera, direction, maxTurn)
  local look, eye = camera.CFrame.LookVector, camera.CFrame.Position
  local angle = math.acos(math.clamp(look:Dot(direction), -1, 1))
  if angle < 1e-6 then
    return
  end
  angle = math.min(angle, maxTurn or angle)
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
  -- Fixed tuning with eased, acceleration-limited turns; never snap to a new focus.
  if lock and focus then
    local direction = directionTo(snap, focus.character, focus.humanoid, focus.root, true)
    if direction then
      if lockModel ~= focus.character then
        lockModel, lockSpeed = focus.character, 0
      end
      local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 15)
      local angle = math.acos(math.clamp(snap.camera.CFrame.LookVector:Dot(direction), -1, 1))
      lockSpeed = math.min(math.rad(150), lockSpeed + math.rad(600) * elapsed)
      local turn = math.min(angle * (1 - math.exp(-10 * elapsed)), lockSpeed * elapsed)
      apply(snap.camera, direction, turn)
      assisted = focus.character
      return
    end
  end
  lockModel, lockSpeed = nil, 0
  if not assist then
    Aim.reset()
    return
  end
  local look = snap.camera.CFrame.LookVector
  local direction, distance = assistTarget(snap, look)
  if direction then
    apply(snap.camera, assistStep(look, direction, dt, distance))
  end
end
Aim.__contract = {
  provides = { "setup", "reset", "teardown", "step" },
  requires = { Native = "mcpnative", Utils = "utils", Options = "mcpoptions", Units = "mcpunits", Lifetime = "lifetime" },
  requiresData = { Options = { "tuning" } },
  requiresMethods = {
    Units = { "distance", "toBlocks" },
    Native = { "blocked", "visible", "aimPoint" },
    Utils = { "getConfigValue", "getWorkspace" },
    Lifetime = { "scope" },
  },
}
return Aim
