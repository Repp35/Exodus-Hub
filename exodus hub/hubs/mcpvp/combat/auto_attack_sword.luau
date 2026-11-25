-- [[ autoattacksword ]]
--!optimize 2
local Sword = {}
local native, target
local nextAttack, selected, equipAt = 0, nil, 0
function Sword.setup(deps)
  native, target = deps.Native, deps.Target
  return true
end
function Sword.reset() nextAttack, selected, equipAt = 0, nil, 0 end
function Sword.aim(snap, chosen)
  local eye = snap.camera.CFrame.Position
  local point = chosen.root.Position
  if (point - eye).Magnitude > 0.01 then snap.camera.CFrame = CFrame.lookAt(eye, point) end
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
  requires = { Native = "mcpnative", Target = "mcptarget" },
  requiresMethods = { Native = { "blocked", "findSword", "equip", "canHit", "stats", "attack" }, Target = { "touch" } },
}
return Sword
