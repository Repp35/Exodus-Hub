-- [[ mcpaim ]]
--!optimize 2
local Aim = {}
local geometry, utils, units, tuning, input, gui, world, scope
local humanoids, held, lastLook, lastCamera = {}, nil, nil, nil
local resumeAt, stick = 0, false
local manualSerial, checkedSerial = 0, 0
local ignored = setmetatable({}, { __mode = "k" })
function Aim.reset()
  held, lastLook, lastCamera, resumeAt = nil, nil, nil, 0
  checkedSerial = manualSerial
end
function Aim.dismiss(character)
  ignored[character] = true
  if held == character then
    held = nil
  end
end
function Aim.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  humanoids, stick, ignored = {}, false, setmetatable({}, { __mode = "k" })
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
      if utils.isActive() and (utils.getConfigValue("MCAimAssist") or utils.getConfigValue("MCAimLock")) then
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
      manualSerial += 1
    elseif not processed and event.UserInputType == Enum.UserInputType.Touch and event.Delta.Magnitude > 0.1 then
      local camera = world.CurrentCamera
      if camera and event.Position.X >= camera.ViewportSize.X * 0.5 then
        manualSerial += 1
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
function Aim.pause(snap)
  Aim.reset()
  resumeAt = snap.now + 0.75
  checkedSerial = manualSerial
end
function Aim.observe(snap)
  lastLook, lastCamera = snap.camera.CFrame.LookVector, snap.camera
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
  return delta.Unit, distance
end
local function assist(snap)
  if held and not ignored[held] then
    local aim = direction(snap, held, tuning.assistRangeBlocks)
    if aim then
      return aim
    end
    held = nil
  end
  local best, nearest
  for human in pairs(humanoids) do
    local aim, distance
    if not ignored[human.Parent] then
      aim, distance = direction(snap, human.Parent, tuning.assistRangeBlocks)
    end
    if aim and (not nearest or distance < nearest) then
      held, best, nearest = human.Parent, aim, distance
    end
  end
  return best
end
function Aim.step(snap, focus)
  local lock, enabled = utils.getConfigValue("MCAimLock"), utils.getConfigValue("MCAimAssist")
  if snap.now < resumeAt then
    return
  end
  if not (lock or enabled) or input:GetFocusedTextBox() or gui.MenuIsOpen then
    Aim.reset()
    return
  end
  local desired
  if focus and (lock or enabled) then
    ignored[focus.character] = nil
    desired = direction(snap, focus.character, tuning.assistRangeBlocks, geometry.point(focus.character, focus.root))
    if desired then
      held = focus.character
    end
  end
  if not desired and enabled then
    desired = assist(snap)
  end
  if desired then
    local frame = snap.camera.CFrame
    -- One camera writer, no pearl arc tracking or close-range speed limiter.
    snap.camera.CFrame = CFrame.lookAt(frame.Position, frame.Position + desired)
  end
  lastLook, lastCamera = snap.camera.CFrame.LookVector, snap.camera
end
Aim.__contract = {
  provides = { "setup", "reset", "step", "teardown", "looking", "yielding", "pause", "observe", "dismiss" },
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
