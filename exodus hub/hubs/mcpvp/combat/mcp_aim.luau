-- [[ mcpaim ]]
--!optimize 2
local Aim = {}
local native, utils, tuning, units, input, gui, world, scope
local humanoids, assisted = {}, nil
local ASSIST_PULL, ASSIST_SPEED = 20, math.rad(480)
local LOCK_PULL, LOCK_SPEED = 32, math.rad(900)
local ACQUIRE_DOT = math.cos(math.rad(20))
function Aim.reset()
  assisted = nil
end
function Aim.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  humanoids = {}
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
  return delta.Unit, distance, point
end
local function onScreen(snap, point)
  local projected, visible = snap.camera:WorldToViewportPoint(point)
  return visible and projected.Z > 0
end
local function assistTarget(snap)
  -- Only an already acquired nearby target may be followed outside the screen.
  if assisted then
    local human = assisted:FindFirstChildOfClass("Humanoid")
    local root = assisted:FindFirstChild("HumanoidRootPart")
    local aim, distance, point = directionTo(snap, assisted, human, root, false)
    if aim and (distance <= tuning.focusRangeBlocks or onScreen(snap, point)) then
      return aim
    end
    assisted = nil
  end
  local best, direction, score
  local look = snap.camera.CFrame.LookVector
  for human in pairs(humanoids) do
    local model = human.Parent
    local root = model and model:FindFirstChild("HumanoidRootPart")
    local aim, _, point = directionTo(snap, model, human, root, false)
    if not aim or not onScreen(snap, point) then
      continue
    end
    local rank = look:Dot(aim)
    if rank < ACQUIRE_DOT then
      continue
    end
    if score == nil or rank > score then
      best, direction, score = model, aim, rank
    end
  end
  assisted = best
  return direction
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
  local direction
  local pull, speed = ASSIST_PULL, ASSIST_SPEED
  if lock and focus then
    direction = directionTo(snap, focus.character, focus.humanoid, focus.root, true)
    if direction then
      pull, speed = LOCK_PULL, LOCK_SPEED
      assisted = focus.character
    end
  end
  if not direction and assist then
    direction = assistTarget(snap)
  end
  if not direction then
    Aim.reset()
    return
  end
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 15)
  local angle = math.acos(math.clamp(snap.camera.CFrame.LookVector:Dot(direction), -1, 1))
  local turn = math.min(angle * (1 - math.exp(-pull * elapsed)), speed * elapsed)
  -- apply also resolves the exactly-behind case where the cross product is zero.
  apply(snap.camera, direction, turn)
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
