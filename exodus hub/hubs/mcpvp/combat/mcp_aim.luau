-- [[ mcp aim ]]
--!optimize 2
local Aim = {}
local geometry, native, utils, units, tuning, input, gui, world, scope, players, base
local held, lastLook, lastCamera
local recent, recentUntil, heldUntil, scanAt = nil, 0, 0, 0
local resumeAt, stick = 0, false
local manualSerial, checkedSerial, manualUntil = 0, 0, 0
local ignored = setmetatable({}, { __mode = "k" })
local yielded = setmetatable({}, { __mode = "k" })
function Aim.reset()
  held, lastLook, lastCamera, resumeAt = nil, nil, nil, 0
  recent, recentUntil, heldUntil, scanAt = nil, 0, 0, 0
  checkedSerial = manualSerial
end
function Aim.remember(character, now, explicit)
  if explicit then
    yielded[character] = nil
    ignored[character] = nil
  end
  recent, recentUntil = character, now + tuning.assistMemorySeconds
end
function Aim.dismiss(character)
  ignored[character] = true
  if recent == character then
    recent, recentUntil = nil, 0
  end
  if held == character then
    held = nil
  end
end
function Aim.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  stick, ignored, base = false, setmetatable({}, { __mode = "k" }), nil
  yielded = setmetatable({}, { __mode = "k" })
  Aim.reset()
end
function Aim.setup(deps)
  Aim.teardown()
  geometry, native, utils, units, tuning = deps.Geometry, deps.Native, deps.Utils, deps.Units, deps.Options.tuning
  players = game:GetService("Players")
  input, gui, world = game:GetService("UserInputService"), game:GetService("GuiService"), utils.getWorkspace()
  scope = deps.Lifetime.scope()
  local source = game:GetService("ReplicatedStorage"):FindFirstChild("MobileAimAssist")
  local ok, value = pcall(function() return source and require(source) end)
  base = ok and type(value) == "table" and value or nil
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
  scope.connect(input.InputChanged, function(event, processed)
    if event.KeyCode == Enum.KeyCode.Thumbstick2 then
      stick = event.Position.Magnitude > 0.12
    elseif event.UserInputType == Enum.UserInputType.MouseMovement and event.Delta.Magnitude > 0.05 then
      manualSerial += 1
      manualUntil = os.clock() + tuning.aimInputGraceSeconds
    elseif event.UserInputType == Enum.UserInputType.Touch and event.Delta.Magnitude > 0.05 then
      local camera = world.CurrentCamera
      if camera and event.Position.X >= camera.ViewportSize.X * 0.5 then
        manualSerial += 1
        manualUntil = os.clock() + tuning.aimInputGraceSeconds
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
  local point = snap.camera:WorldToViewportPoint(value.root.Position)
  local size = snap.camera.ViewportSize
  local margin = tuning.pursuitScreenMargin
  return point.Z > 0 and point.X >= -size.X * margin and point.X <= size.X * (1 + margin) and point.Y >= -size.Y * margin and point.Y <= size.Y * (1 + margin)
end
function Aim.yielding(snap) return stick or manualSerial ~= checkedSerial or snap.now < manualUntil end
function Aim.pause(snap) resumeAt = math.max(resumeAt, snap.now + tuning.aimInputGraceSeconds) end
function Aim.observe(snap)
  lastLook, lastCamera = snap.camera.CFrame.LookVector, snap.camera
  checkedSerial = manualSerial
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
local TOUCH = { Cone = math.rad(30), MaxSpeed = math.rad(72), Pull = 9, LockBias = math.rad(3) }
local GAMEPAD = { Cone = math.rad(12), MaxSpeed = math.rad(20), Pull = 2.5, LockBias = math.rad(1) }
local function profile()
  if base and type(base.Profile) == "function" then
    local ok, value = pcall(base.Profile, input.PreferredInput, true)
    if ok and type(value) == "table" then
      return value
    end
  end
  return input.PreferredInput == Enum.PreferredInput.Gamepad and GAMEPAD or TOUCH
end
local function assist(snap, settings, focus)
  local look = snap.camera.CFrame.LookVector
  local best, desired, score
  local function consider(model)
    if not model or ignored[model] or yielded[model] then
      return
    end
    local aim = direction(snap, model, tuning.assistRangeBlocks)
    if not aim then
      return
    end
    local angle = math.acos(math.clamp(look:Dot(aim), -1, 1))
    if angle > settings.Cone then
      return
    end
    local rank = angle - (model == held and settings.LockBias or 0)
    if not score or rank < score then
      best, desired, score = model, aim, rank
    end
  end
  consider(focus and focus.character)
  consider(recent)
  consider(held)
  if snap.now >= scanAt then
    scanAt = snap.now + 0.1
    for _, player in ipairs(players:GetPlayers()) do
      if player ~= snap.player then
        consider(player.Character)
      end
    end
    local bots = world:FindFirstChild("ArenaPvPBots")
    if bots then
      for _, model in ipairs(bots:GetChildren()) do
        consider(model)
      end
    end
  end
  if best then
    if held ~= best then
      heldUntil = 0
    end
    held = best
    if look:Dot(desired) >= math.cos(settings.Cone) then
      heldUntil = snap.now + tuning.assistMemorySeconds
    end
  else
    held, heldUntil = nil, 0
  end
  return desired
end
local function aimingAtCrystal(snap, settings)
  local folder = world:FindFirstChild("EndCrystals")
  if not folder then
    return false
  end
  local frame = snap.camera.CFrame
  for _, crystal in ipairs(folder:GetChildren()) do
    if crystal:IsA("PVInstance") then
      local delta = crystal:GetPivot().Position - frame.Position
      if
        delta.Magnitude > 0.1
        and units.distance(crystal:GetPivot().Position, frame.Position) <= 6
        and frame.LookVector:Dot(delta.Unit) >= math.cos(settings.Cone)
      then
        return true
      end
    end
  end
  return false
end
local function nudge(snap, desired, dt, settings)
  local frame = snap.camera.CFrame
  local angle = math.acos(math.clamp(frame.LookVector:Dot(desired), -1, 1))
  if angle < math.rad(0.35) then
    return
  end
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 15)
  local turn = math.min(angle * (1 - math.exp(-settings.Pull * elapsed)), settings.MaxSpeed * elapsed)
  local axis = frame.LookVector:Cross(desired)
  if axis.Magnitude < 1e-6 then
    axis = frame.UpVector
  end
  local rotation = CFrame.fromAxisAngle(axis.Unit, turn)
  snap.camera.CFrame = CFrame.new(frame.Position) * rotation * (frame - frame.Position)
end
function Aim.step(snap, focus, dt)
  local lock, enabled = utils.getConfigValue("MCAimLock"), utils.getConfigValue("MCAimAssist")
  if Aim.yielding(snap) then
    local look = snap.camera.CFrame.LookVector
    local function manual(model)
      local root = model and model:FindFirstChild("HumanoidRootPart")
      if not root then
        return
      end
      local delta = root.Position - snap.camera.CFrame.Position
      if delta.Magnitude < 0.001 then
        return
      end
      local toward = lastCamera == snap.camera and lastLook and look:Dot(delta.Unit) > lastLook:Dot(delta.Unit) + 1e-6
      yielded[model] = not toward and true or nil
    end
    manual(focus and focus.character)
    manual(held)
    manual(recent)
    for model in pairs(yielded) do
      manual(model)
    end
    held, heldUntil = nil, 0
    resumeAt = math.max(resumeAt, snap.now + tuning.aimInputGraceSeconds)
    Aim.observe(snap)
    return
  end
  if snap.now < resumeAt then
    return
  end
  if
    not (lock or enabled)
    or input:GetFocusedTextBox()
    or gui.MenuIsOpen
    or snap.camera.CameraType ~= Enum.CameraType.Custom
    or snap.character:FindFirstChildOfClass("ForceField")
    or snap.player:GetAttribute("ThirdPersonCamera") == true and snap.player:GetAttribute("CameraViewMode") == 2
  then
    Aim.reset()
    return
  end
  if focus then
    ignored[focus.character] = nil
    local weapon = native.weapon(snap, focus) or snap.tool
    if focus.distance <= tuning.focusRangeBlocks and geometry.direction(snap, focus, weapon) then
      Aim.remember(focus.character, snap.now)
      if lock then
        local desired = direction(snap, focus.character, tuning.focusRangeBlocks)
        local settings = profile()
        local look = snap.camera.CFrame.LookVector
        if desired and not yielded[focus.character] and look:Dot(desired) >= math.cos(settings.Cone) and not aimingAtCrystal(snap, settings) then
          nudge(snap, desired, dt, {
            Pull = settings.Pull * tuning.aimLockMultiplier,
            MaxSpeed = math.min(settings.MaxSpeed * tuning.aimLockMultiplier, math.rad(120)),
          })
          held, heldUntil = focus.character, snap.now + tuning.assistMemorySeconds
          Aim.observe(snap)
          return
        end
      end
    end
  end
  local weaponHeld = snap.tool and (snap.tool:GetAttribute("VoxelWeapon") == true or snap.tool.Name == "Bow")
  if enabled and weaponHeld then
    local settings = profile()
    if aimingAtCrystal(snap, settings) then
      held, heldUntil = nil, 0
      Aim.observe(snap)
      return
    end
    local desired = assist(snap, settings, focus)
    if desired then
      nudge(snap, desired, dt, settings)
    end
  end
  Aim.observe(snap)
end
Aim.__contract = {
  provides = { "setup", "reset", "step", "teardown", "looking", "yielding", "pause", "observe", "dismiss", "remember" },
  requires = { Geometry = "mcpgeometry", Native = "mcpnative", Utils = "utils", Units = "mcpunits", Options = "mcpoptions", Lifetime = "lifetime" },
  requiresMethods = {
    Geometry = { "point", "visible", "direction" },
    Native = { "weapon" },
    Utils = { "getWorkspace", "isActive", "getConfigValue" },
    Units = { "distance" },
    Lifetime = { "scope" },
  },
  requiresData = { Options = { "tuning" } },
}
return Aim
