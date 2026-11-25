-- [[ autoattacksword ]]
--!optimize 2
local Sword = {}
local native, target, tuning
local nextAttack, selected, equipAt = 0, nil, 0
function Sword.setup(deps)
  native, target, tuning = deps.Native, deps.Target, deps.Options.tuning
  return true
end
function Sword.reset() nextAttack, selected, equipAt = 0, nil, 0 end
function Sword.aim(snap, chosen, dt)
  if native.blocked(snap) or (chosen.root.Position - snap.root.Position).Magnitude > tuning.aimRange then return end
  local camera = snap.camera
  local eye = camera.CFrame.Position
  local point = chosen.root.Position + Vector3.new(0, chosen.character:GetAttribute("Sneaking") and 0.15 or 0.5, 0)
  -- Check from the actual camera too: a wall must stop the camera pull immediately.
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  params.FilterDescendantsInstances = { snap.character, camera }
  local hit = workspace:Raycast(eye, point - eye, params)
  if hit and not hit.Instance:IsDescendantOf(chosen.character) then return end
  if not native.visible(snap, point, chosen.character) then return end
  local delta = point - eye
  if delta.Magnitude <= 0.01 then return end
  local desired, forward = delta.Unit, camera.CFrame.LookVector
  local angle = math.acos(math.clamp(forward:Dot(desired), -1, 1))
  if angle < 0.006 then return end
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 30)
  local turn = math.min(angle * (1 - math.exp(-tuning.aimPull * elapsed)), tuning.aimMaxSpeed * elapsed)
  local axis = forward:Cross(desired)
  if axis.Magnitude < 0.00001 then axis = camera.CFrame.UpVector end
  local direction = CFrame.fromAxisAngle(axis.Unit, turn):VectorToWorldSpace(forward)
  camera.CFrame = CFrame.lookAt(eye, eye + direction)
end
function Sword.step(snap, chosen)
  if native.blocked(snap) then return false end
  local tool = native.findSword(snap)
  if not tool or not native.canHit(snap, chosen, tool) then return false end
  local speed = native.stats(tool).speed
  if type(speed) ~= "number" or speed <= 0 then return false end
  if snap.tool ~= tool then
    if selected ~= tool or snap.now - equipAt >= 0.75 then
      if native.equip(snap, tool) then
        selected, equipAt = tool, snap.now
        nextAttack = math.max(nextAttack, snap.now + 1 / speed)
      end
    end
    return false
  end
  if snap.now < nextAttack then return false end
  local lastSwing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or -math.huge
  if snap.now - lastSwing < 1 / speed then return false end
  if native.attack(snap, chosen) then
    nextAttack = snap.now + 1 / speed
    target.touch(snap.now)
    return true
  end
  nextAttack = snap.now + 0.25
  return false
end
Sword.__contract = {
  provides = { "setup", "reset", "aim", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget", Options = "mcpoptions" },
  requiresMethods = { Native = { "visible", "blocked", "findSword", "equip", "canHit", "stats", "attack" }, Target = { "touch" } },
  requiresData = { Options = { "tuning" } },
}
return Sword
