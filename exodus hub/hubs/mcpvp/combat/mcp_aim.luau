-- [[ mcpaim ]]
--!optimize 2
local Aim = {}
local geometry, utils, units, tuning, input, gui, world, scope
local humanoids, held, lastLook, lastCamera = {}, nil, nil, nil
local manualAt, resumeAt, stick = -math.huge, 0, false
local manualSerial, checkedSerial = 0, 0
local lockRoot, lockSide
function Aim.reset()
  held, lastLook, lastCamera, resumeAt = nil, nil, nil, 0
  checkedSerial = manualSerial
  lockRoot, lockSide = nil, nil
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
    elseif
      not processed
      and event.UserInputType == Enum.UserInputType.MouseMovement
      and event.Delta.Magnitude > 0.5
      and (input.MouseBehavior ~= Enum.MouseBehavior.Default or input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
    then
      manualAt, manualSerial = os.clock(), manualSerial + 1
    elseif not processed and event.UserInputType == Enum.UserInputType.Touch and event.Delta.Magnitude > 0.1 then
      local camera = world.CurrentCamera
      if camera and event.Position.X >= camera.ViewportSize.X * 0.5 then
        manualAt, manualSerial = os.clock(), manualSerial + 1
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
function Aim.looking(snap, value)
  if not value or not value.root.Parent then
    return false
  end
  -- Direction only: terrain and trees do not count as looking away.
  local point = snap.camera:WorldToViewportPoint(value.root.Position)
  local size = snap.camera.ViewportSize
  local margin = tuning.pursuitScreenMargin
  return point.Z > 0 and point.X >= -size.X * margin and point.X <= size.X * (1 + margin) and point.Y >= -size.Y * margin and point.Y <= size.Y * (1 + margin)
end
function Aim.canTurn(snap, direction, margin)
  if snap.now < resumeAt then
    return false
  end
  local localDirection = snap.camera.CFrame:VectorToObjectSpace(direction)
  if localDirection.Z >= -1e-5 then
    return false
  end
  local size = snap.camera.ViewportSize
  local vertical = math.tan(math.rad(snap.camera.FieldOfView) / 2) * (1 + 2 * (margin or 0))
  return math.abs(localDirection.Y / -localDirection.Z) <= vertical * 0.98
    and math.abs(localDirection.X / -localDirection.Z) <= vertical * size.X / math.max(1, size.Y) * 0.98
end
local function intent(snap, value)
  local manual = manualSerial ~= checkedSerial or stick
  if not manual or not value or lastCamera ~= snap.camera or not lastLook then
    return 0
  end
  local delta = value.root.Position - snap.camera.CFrame.Position
  if delta.Magnitude < 0.001 then
    return 0
  end
  local desired, look = delta.Unit, snap.camera.CFrame.LookVector
  if lastLook:Dot(look) > math.cos(math.rad(0.1)) then
    return 0
  end
  checkedSerial = manualSerial
  local before = math.acos(math.clamp(lastLook:Dot(desired), -1, 1))
  local after = math.acos(math.clamp(look:Dot(desired), -1, 1))
  if after > before + math.rad(0.35) then
    return 1
  end
  if after < before - math.rad(0.35) then
    return -1
  end
  return 0
end
function Aim.yielding(snap, value) return intent(snap, value) == 1 end
function Aim.returning(snap, value) return intent(snap, value) == -1 end
function Aim.pause(snap)
  Aim.reset()
  resumeAt = snap.now + 0.75
  checkedSerial = manualSerial
end
function Aim.turn(snap, desired, dt, emergency, margin)
  if snap.now < resumeAt or not emergency and not Aim.canTurn(snap, desired, margin) then
    return false
  end
  local frame = snap.camera.CFrame
  local angle = math.acos(math.clamp(frame.LookVector:Dot(desired), -1, 1))
  local turn = math.min(angle, math.rad(360) * math.clamp(dt or 1 / 60, 0, 1 / 15))
  local axis = frame.LookVector:Cross(desired)
  if axis.Magnitude < 1e-6 and angle > 0.001 then
    axis = frame.UpVector
  end
  if axis.Magnitude > 1e-6 then
    snap.camera.CFrame = CFrame.new(frame.Position) * CFrame.fromAxisAngle(axis.Unit, turn) * frame.Rotation
  end
  lastLook, lastCamera = snap.camera.CFrame.LookVector, snap.camera
  return lastLook:Dot(desired) >= math.cos(math.rad(0.75))
end
function Aim.observe(snap)
  lastLook, lastCamera = snap.camera.CFrame.LookVector, snap.camera
end
local function lockPoint(snap, focus)
  local root = focus.root
  local forward = root.CFrame.LookVector * Vector3.new(1, 0, 1)
  if forward.Magnitude < 1e-5 then
    return geometry.point(focus.character, root)
  end
  forward = forward.Unit
  local facing = units.toBlocks(snap.root.Position - root.Position):Dot(forward)
  if lockRoot ~= root then
    lockRoot, lockSide = root, facing >= 0 and 1 or -1
  elseif facing > 0.5 then
    lockSide = 1
  elseif facing < -0.5 then
    lockSide = -1
  end
  local side = geometry.blocking(focus.character) and -1 or lockSide
  -- Keep the torso point inside the body, without chasing its lateral edges.
  return root.Position + units.offset(0, focus.character:GetAttribute("Sneaking") and 3 / 64 or 5 / 32, 0) + forward * units.toWorld(side / 8)
end
local function direction(snap, model, range, point)
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
  point = point or geometry.point(model, root)
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
  if snap.now < resumeAt then
    return
  end
  if not (lock or enabled) or input:GetFocusedTextBox() or gui.MenuIsOpen then
    Aim.reset()
    return
  end
  local aim, pull, speed, radius
  if lock and focus then
    local point = lockPoint(snap, focus)
    local distance
    aim, distance = direction(snap, focus.character, tuning.focusRangeBlocks, point)
    if aim then
      held, pull = focus.character, 24
      -- Close crossings must not whip the camera around and redirect forward input into an orbit.
      speed = math.rad(360) * math.clamp((distance - 0.45) / 1.55, 0, 1)
      radius = math.atan(0.1 / math.max(0.1, units.distance(point, snap.camera.CFrame.Position)))
    end
  else
    lockRoot, lockSide = nil, nil
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
    local turn = math.min(math.max(0, angle - (radius or 0)) * (1 - math.exp(-pull * elapsed)), speed * elapsed)
    local axis = frame.LookVector:Cross(aim)
    if axis.Magnitude < 1e-6 then
      axis = frame.UpVector
    end
    snap.camera.CFrame = CFrame.new(frame.Position) * CFrame.fromAxisAngle(axis.Unit, turn) * frame.Rotation
  end
  lastLook, lastCamera = snap.camera.CFrame.LookVector, snap.camera
end
Aim.__contract = {
  provides = { "setup", "reset", "step", "teardown", "looking", "canTurn", "yielding", "pause", "turn", "observe", "returning" },
  requires = { Geometry = "mcpgeometry", Utils = "utils", Units = "mcpunits", Options = "mcpoptions", Lifetime = "lifetime" },
  requiresMethods = {
    Geometry = { "point", "visible", "blocking" },
    Utils = { "getWorkspace", "isActive", "getConfigValue" },
    Units = { "distance", "toBlocks", "toWorld", "offset" },
    Lifetime = { "scope" },
  },
  requiresData = { Options = { "tuning" } },
}
return Aim
