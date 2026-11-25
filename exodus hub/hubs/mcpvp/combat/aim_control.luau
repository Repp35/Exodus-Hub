-- [[ aimcontrol ]]
--!optimize 2
local Aim = {}
local native, utils, tuning
local character, target, readyAt, angularSpeed, lastSeen = nil, nil, 0, 0, -math.huge
local input = game:GetService("UserInputService")
local gui = game:GetService("GuiService")
function Aim.setup(deps)
  native, utils, tuning = deps.Native, deps.Utils, deps.Options.tuning
  return true
end
function Aim.reset()
  character, target, readyAt, angularSpeed, lastSeen = nil, nil, 0, 0, -math.huge
end
function Aim.step(snap, chosen, dt)
  local lock = utils.getConfigValue("MCAimLock") == true
  local assist = utils.getConfigValue("MCAimAssist") == true
  if not lock and not assist or input:GetFocusedTextBox() or gui.MenuIsOpen or native.blocked(snap) then
    Aim.reset()
    return
  end
  if not chosen or not chosen.root.Parent or chosen.humanoid.Health <= 0 or native.aerialMace(snap, chosen) then
    Aim.reset()
    return
  end
  local legit = utils.getConfigValue("MCAimLegit") == true
  local strength = math.clamp(tonumber(utils.getConfigValue("MCAimStrength")) or 45, 0, 100) / 100
  if strength == 0 then
    Aim.reset()
    return
  end
  if character ~= snap.character or target ~= chosen.character then
    Aim.reset()
    character, target, readyAt = snap.character, chosen.character, snap.now + (legit and 0.22 or 0)
  end
  local camera = snap.camera
  local position = chosen.root.Position + Vector3.new(0, 0.6, 0)
  local projected, onScreen = camera:WorldToViewportPoint(position)
  local eye, delta = camera.CFrame.Position, position - camera.CFrame.Position
  if delta.Magnitude < 0.01 or (chosen.root.Position - snap.root.Position).Magnitude > tuning.aimRange * 3.2 then
    return
  end
  local angle = math.acos(math.clamp(camera.CFrame.LookVector:Dot(delta.Unit), -1, 1))
  if (legit or not lock) and (not onScreen or projected.Z <= 0 or not lock and angle > math.rad(tuning.acquireAngle)) then
    readyAt, angularSpeed, lastSeen = snap.now + (legit and 0.25 or 0), 0, -math.huge
    return
  end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
  params.FilterDescendantsInstances = { snap.character, camera }
  local hit = workspace:Raycast(eye, delta, params)
  if hit and not hit.Instance:IsDescendantOf(chosen.character) or not native.visible(snap, position, chosen.character) then
    readyAt, angularSpeed, lastSeen = snap.now + (legit and 0.22 or 0), 0, -math.huge
    return
  end
  if lastSeen > 0 and snap.now - lastSeen > 0.15 then
    readyAt, angularSpeed = snap.now + (legit and 0.22 or 0), 0
  end
  lastSeen = snap.now
  if snap.now < readyAt or angle <= math.rad(0.08) then
    angularSpeed = 0
    return
  end
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 20)
  local maxSpeed = math.rad((lock and 360 or 160) * strength * (legit and 0.6 or 1))
  local desired = math.min(maxSpeed, angle * (lock and 18 or 7) * strength)
  angularSpeed = legit and math.min(desired, angularSpeed + math.rad(540) * strength * elapsed) or desired
  camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, position), math.min(1, angularSpeed * elapsed / angle))
end
Aim.__contract = {
  provides = { "setup", "reset", "step" },
  requires = { Native = "mcpnative", Utils = "utils", Options = "mcpoptions" },
  requiresMethods = { Native = { "aerialMace", "blocked", "visible" }, Utils = { "getConfigValue" } },
  requiresData = { Options = { "tuning" } },
}
return Aim
