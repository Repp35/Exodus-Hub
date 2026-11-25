-- [[ aimcontrol ]]
--!optimize 2
local Aim = {}
local native, utils, tuning
local character, target, readyAt, angularSpeed, lastView, inputUntil = nil, nil, 0, 0, nil, 0
local input = game:GetService("UserInputService")
local gui = game:GetService("GuiService")
function Aim.setup(deps) native, utils, tuning = deps.Native, deps.Utils, deps.Options.tuning return true end
function Aim.reset() character, target, readyAt, angularSpeed, lastView, inputUntil = nil, nil, 0, 0, nil, 0 end
function Aim.step(snap, chosen, dt)
  local lock, assist = utils.getConfigValue("MCAimLock") == true, utils.getConfigValue("MCAimAssist") == true
  if not lock and not assist or input:GetFocusedTextBox() or gui.MenuIsOpen or native.blocked(snap)
    or not native.isWeapon(snap.tool) or not chosen or not chosen.root.Parent or chosen.humanoid.Health <= 0 then Aim.reset() return end
  local distance = (chosen.root.Position - snap.root.Position).Magnitude
  local range = lock and tuning.lockRange or tuning.assistRange
  if distance > range then Aim.reset() return end
  local strength = math.clamp(tonumber(utils.getConfigValue("MCAimStrength")) or 45, 0, 100) / 100
  if strength == 0 then Aim.reset() return end
  local camera = snap.camera
  local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
  local userMoved = input:GetMouseDelta().Magnitude > 0 or lastView and lastView:Dot(look) < 0.999999
  if character ~= snap.character or target ~= chosen.character then
    Aim.reset()
    character, target, readyAt = snap.character, chosen.character, snap.now + (lock and 0 or 0.1)
  end
  if userMoved then inputUntil = snap.now + 0.15 end
  lastView = look
  -- Like the original aim: correct towards the nearest part of the body, not its center.
  local root = chosen.root.Position
  local closest = eye + look * math.max(0, (root - eye):Dot(look))
  local sneak = chosen.character:GetAttribute("Sneaking") == true and 0.96 or 0
  local point = root + Vector3.new(math.clamp(closest.X - root.X, lock and -0.35 or -0.96, lock and 0.35 or 0.96),
    math.clamp(closest.Y - root.Y, -1.2, 1.6 - sneak), math.clamp(closest.Z - root.Z, lock and -0.35 or -0.96, lock and 0.35 or 0.96))
  local projected, onScreen = camera:WorldToViewportPoint(point)
  local delta = point - eye
  if delta.Magnitude < 0.01 then return end
  local angle = math.acos(math.clamp(look:Dot(delta.Unit), -1, 1))
  local cone = math.rad(lock and tuning.lockCone or tuning.assistCone)
  if not onScreen or projected.Z <= 0 or angle > cone then readyAt, angularSpeed = snap.now + (lock and 0 or 0.15), 0 return end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
  params.FilterDescendantsInstances = { snap.character, camera }
  local hit = workspace:Raycast(eye, delta, params)
  if hit and not hit.Instance:IsDescendantOf(chosen.character) or not native.visible(snap, point, chosen.character) then
    readyAt, angularSpeed = snap.now + (lock and 0 or 0.15), 0
    return
  end
  -- Assist only supports the player's movement. It does not keep pulling an idle camera.
  if not lock and (distance > tuning.assistRange or snap.now > inputUntil and snap.humanoid.MoveDirection.Magnitude < 0.1) then angularSpeed = 0 return end
  local deadzone = math.rad(lock and 0.15 or 1.5)
  if snap.now < readyAt or angle <= deadzone then angularSpeed = 0 return end
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 30)
  -- Bounded exponential pull, matching MobileAimAssist.Step's design in the dump.
  local pull = lock and (14 + 10 * strength) or 1.5 * strength
  local maxSpeed = lock and math.rad(170 + 330 * strength) or math.rad(20) * strength
  local desired = math.min(maxSpeed, (angle - deadzone) * (1 - math.exp(-pull * elapsed)) / elapsed)
  angularSpeed = math.min(desired, angularSpeed + math.rad(lock and (900 + 900 * strength) or 60 * strength) * elapsed)
  local turn = math.min(angle - deadzone, angularSpeed * elapsed)
  local axis = look:Cross(delta.Unit)
  if axis.Magnitude < 0.000001 then return end
  local direction = CFrame.fromAxisAngle(axis.Unit, turn):VectorToWorldSpace(look)
  camera.CFrame = CFrame.lookAt(eye, eye + direction)
  lastView = direction
end
Aim.__contract = {
  provides = { "setup", "reset", "step" },
  requires = { Native = "mcpnative", Utils = "utils", Options = "mcpoptions" },
  requiresMethods = { Native = { "isWeapon", "blocked", "visible" }, Utils = { "getConfigValue" } },
  requiresData = { Options = { "tuning" } },
}
return Aim
