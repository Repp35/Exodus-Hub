-- [[ autoattacksword ]]
--!optimize 2
local Sword = {}
local native, target
local nextAttack = 0
function Sword.setup(deps)
  native, target = deps.Native, deps.Target
  return true
end
function Sword.reset() nextAttack = 0 end
function Sword.aim(snap, chosen)
  local eye = snap.camera.CFrame.Position
  local point = chosen.root.Position
  if (point - eye).Magnitude > 0.01 then
    snap.camera.CFrame = CFrame.lookAt(eye, point)
  end
end
function Sword.step(snap, chosen)
  if snap.now < nextAttack or not native.canHit(snap, chosen) then
    return false
  end
  local speed = native.stats(snap.tool).speed
  if type(speed) ~= "number" or speed <= 0 then
    return false
  end
  local lastSwing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or -math.huge
  if snap.now - lastSwing < 1 / speed then
    return false
  end
  if native.attack(snap, chosen) then
    nextAttack = snap.now + 1 / speed
    target.touch(snap.now)
    return true
  end
  return false
end
Sword.__contract = {
  provides = { "setup", "reset", "aim", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget" },
  requiresMethods = { Native = { "canHit", "stats", "attack" }, Target = { "touch" } },
}
return Sword
