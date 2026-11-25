-- [[ autoattacksword ]]
--!optimize 2
local Sword = {}
local native, target, tuning, crit
local nextAttack, selected, equipAt = 0, nil, 0
function Sword.setup(deps)
  native, target, tuning, crit = deps.Native, deps.Target, deps.Options.tuning, deps.Crit
  return true
end
function Sword.reset() nextAttack, selected, equipAt = 0, nil, 0 if crit then crit.reset() end end
function Sword.aim(snap, chosen, dt)
  if native.aerialMace(snap, chosen) then return end
  if game:GetService("UserInputService"):GetFocusedTextBox() or game:GetService("GuiService").MenuIsOpen then return end
  local close = native.canHit(snap, chosen)
  local weapon = native.findSword(snap)
  local reach = weapon and native.stats(weapon).reach or 9.6
  if (chosen.root.Position - snap.root.Position).Magnitude > reach * 6 then return end
  local camera = snap.camera
  local eye = camera.CFrame.Position
  local root = chosen.root.Position
  local closest = eye + camera.CFrame.LookVector * math.max(0, (root - eye):Dot(camera.CFrame.LookVector))
  local point = root + Vector3.new(math.clamp(closest.X - root.X, -0.26, 0.26), math.clamp(closest.Y - root.Y, -1.2, 1.6), math.clamp(closest.Z - root.Z, -0.26, 0.26))
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
  local angle = math.acos(math.clamp(camera.CFrame.LookVector:Dot(delta.Unit), -1, 1))
  local alpha = angle < 0.001 and 1 or math.min(1, math.rad(close and 720 or 600) * math.clamp(dt or 1 / 60, 0, 1 / 30) / angle)
  camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, point), alpha)
end
function Sword.step(snap, chosen)
  if native.aerialMace(snap, chosen) then crit.reset() return false end
  crit.observe(snap)
  if native.blocked(snap) then return false end
  local tool = native.findSword(snap)
  if not tool then return false end
  if not native.canHit(snap, chosen, tool) and (chosen.root.Position - snap.root.Position).Magnitude > native.stats(tool).reach + 3.2 then return false end
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
  local lastSwing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or -math.huge
  local readyAt = math.max(nextAttack, lastSwing + 1 / speed)
  crit.plan(snap, chosen, tool, readyAt)
  if not native.canHit(snap, chosen, tool, snap.camera.CFrame.LookVector) then return false end
  if not crit.ready(snap, chosen, tool, readyAt) then return false end
  target.noteAttack(snap, chosen)
  if native.attack(snap, chosen) then
    nextAttack = snap.now + 1 / speed
    return true
  end
  nextAttack = snap.now + 0.25
  return false
end
Sword.__contract = {
  provides = { "setup", "reset", "aim", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget", Options = "mcpoptions", Crit = "autocrit" },
  requiresMethods = { Native = { "aerialMace", "visible", "blocked", "findSword", "equip", "canHit", "stats", "attack" }, Target = { "noteAttack" }, Crit = { "reset", "observe", "plan", "ready" } },
  requiresData = { Options = { "tuning" } },
}
return Sword
