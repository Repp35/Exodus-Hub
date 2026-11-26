-- [[ mcpaim ]]
--!optimize 2
local Aim = {}
local geometry, utils, units, tuning, input, gui, world, scope
local humanoids, held, lastLook, lastCamera = {}, nil, nil, nil
local manualAt, resumeAt, stick = -math.huge, 0, false
function Aim.reset()
  held, lastLook, lastCamera, resumeAt = nil, nil, nil, 0
end
function Aim.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  humanoids, stick = {}, false
  Aim.reset()
end
function Aim.setup(deps)
  Aim.teardown()
  geometry, utils, units, tuning = deps.Geometry, deps.Utils, deps.Units, deps.Options.tuning
  input, gui, world = game:GetService("UserInputService"), game:GetService("GuiService"), utils.getWorkspace()
  scope = deps.Lifetime.scope()
  local source = game:GetService("ReplicatedStorage"):FindFirstChild("MobileAimAssist")
  local ok, base = pcall(function() return source and require(source) end)
  if ok and type(base) == "table" and type(base.Adjust) == "function" then
    local original = base.Adjust
    local function adjust(frame)
      if utils.isActive() and utils.getConfigValue("MCAimAssist") then
        return frame
      end
      return original(frame)
    end
    base.Adjust = adjust
    scope.add(function()
      if base.Adjust == adjust then
        base.Adjust = original
      end
    end)
  end
  local function add(value)
    if value:IsA("Humanoid") then
      humanoids[value] = true
    end
  end
  scope.connect(world.DescendantAdded, add)
  scope.connect(world.DescendantRemoving, function(value) humanoids[value] = nil end)
  for _, value in ipairs(world:GetDescendants()) do
    add(value)
  end
  scope.connect(input.InputChanged, function(event, processed)
    if event.KeyCode == Enum.KeyCode.Thumbstick2 then
      stick = event.Position.Magnitude > 0.12
    elseif event.UserInputType == Enum.UserInputType.MouseMovement and event.Delta.Magnitude > 0.1 then
      manualAt = os.clock()
    elseif not processed and event.UserInputType == Enum.UserInputType.Touch and event.Delta.Magnitude > 0.1 then
      local camera = world.CurrentCamera
      if camera and event.Position.X >= camera.ViewportSize.X * 0.5 then
        manualAt = os.clock()
      end
    end
  end)
  scope.connect(input.InputEnded, function(event)
    if event.KeyCode == Enum.KeyCode.Thumbstick2 then
      stick = false
    end
  end)
  return true
end
local function direction(snap, model, range)
  local human = model and model:FindFirstChildOfClass("Humanoid")
  local root = model and model:FindFirstChild("HumanoidRootPart")
  if
    not model
    or model == snap.character
    or not model.Parent
    or model:IsDescendantOf(snap.camera)
    or model:GetAttribute("Invisible") == true
    or not human
    or human.Health <= 0
    or not root
    or model:FindFirstChildOfClass("ForceField")
  then
    return nil
  end
  local distance = units.distance(root.Position, snap.root.Position)
  if distance > range then
    return nil
  end
  local point = geometry.point(model, root)
  if not geometry.visible(snap, point, model, snap.camera.CFrame.Position) then
    return nil
  end
  local delta = point - snap.camera.CFrame.Position
  if delta.Magnitude < 0.001 then
    return nil
  end
  local projected, visible = snap.camera:WorldToViewportPoint(point)
  return delta.Unit, distance, visible and projected.Z > 0
end
local function assist(snap)
  if snap.now < resumeAt then
    return nil
  end
  local look = snap.camera.CFrame.LookVector
  if held then
    local aim, distance, visible = direction(snap, held, tuning.assistRangeBlocks)
    if aim then
      local manual = snap.now - manualAt < 0.15 or input.PreferredInput == Enum.PreferredInput.Gamepad and stick
      if manual and lastCamera == snap.camera and lastLook then
        local before = math.acos(math.clamp(lastLook:Dot(aim), -1, 1))
        if math.acos(math.clamp(look:Dot(aim), -1, 1)) > before + math.rad(0.2) then
          held, resumeAt = nil, snap.now + 0.35
          return nil
        end
      end
      if distance <= tuning.focusRangeBlocks or visible and look:Dot(aim) >= math.cos(math.rad(20)) then
        return aim
      end
    end
    held = nil
  end
  local best, score
  for human in pairs(humanoids) do
    local aim, _, visible = direction(snap, human.Parent, tuning.assistRangeBlocks)
    local rank = aim and look:Dot(aim)
    if visible and rank >= math.cos(math.rad(20)) and (not score or rank > score) then
      held, best, score = human.Parent, aim, rank
    end
  end
  return best
end
function Aim.step(snap, focus, dt)
  local lock, enabled = utils.getConfigValue("MCAimLock"), utils.getConfigValue("MCAimAssist")
  if not (lock or enabled) or input:GetFocusedTextBox() or gui.MenuIsOpen then
    Aim.reset()
    return
  end
  local aim, pull, speed
  if lock and focus then
    aim = direction(snap, focus.character, tuning.focusRangeBlocks)
    if aim then
      held, pull, speed = focus.character, 32, math.rad(900)
    end
  end
  if not aim and enabled then
    aim = assist(snap)
    pull, speed = 10, math.rad(84)
    if input.PreferredInput == Enum.PreferredInput.Gamepad then
      pull, speed = 2.9, math.rad(24)
    end
  end
  local frame = snap.camera.CFrame
  if aim then
    local angle = math.acos(math.clamp(frame.LookVector:Dot(aim), -1, 1))
    local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 15)
    local turn = math.min(angle * (1 - math.exp(-pull * elapsed)), speed * elapsed)
    local axis = frame.LookVector:Cross(aim)
    if axis.Magnitude < 1e-6 then
      axis = frame.UpVector
    end
    snap.camera.CFrame = CFrame.new(frame.Position) * CFrame.fromAxisAngle(axis.Unit, turn) * frame.Rotation
  end
  lastLook, lastCamera = snap.camera.CFrame.LookVector, snap.camera
end
Aim.__contract = {
  provides = { "setup", "reset", "step", "teardown" },
  requires = { Geometry = "mcpgeometry", Utils = "utils", Units = "mcpunits", Options = "mcpoptions", Lifetime = "lifetime" },
  requiresMethods = {
    Geometry = { "point", "visible" },
    Utils = { "getWorkspace", "isActive", "getConfigValue" },
    Units = { "distance" },
    Lifetime = { "scope" },
  },
  requiresData = { Options = { "tuning" } },
}
return Aim
