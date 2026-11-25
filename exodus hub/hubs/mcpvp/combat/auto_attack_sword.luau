-- [[ autoattacksword ]]
--!optimize 2
local Sword = {}
local native, target
local nextAttack, selected, equipAt = 0, nil, 0
function Sword.setup(deps)
  native, target = deps.Native, deps.Target
  return true
end
function Sword.reset()
  nextAttack, selected, equipAt = 0, nil, 0
end
function Sword.step(snap, chosen)
  if native.blocked(snap) then
    return false
  end
  local tool = native.findWeapon(snap)
  if not tool then
    return false
  end
  if not native.canHit(snap, chosen, tool) and (chosen.root.Position - snap.root.Position).Magnitude > native.stats(tool).reach + 3.2 then
    return false
  end
  local speed = native.stats(tool).speed
  if type(speed) ~= "number" or speed <= 0 then
    return false
  end
  if snap.tool ~= tool then
    if selected ~= tool or snap.now - equipAt >= 0.1 then
      if native.equip(snap, tool) then
        selected, equipAt = tool, snap.now
        nextAttack = math.max(nextAttack, snap.now + math.max(0, 1 / speed - 0.025))
      end
    end
    return false
  end
  local lastSwing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or -math.huge
  local readyAt = math.max(nextAttack, lastSwing + math.max(1 / 15, 1 / speed - 0.025))
  if not native.canHit(snap, chosen, tool) then
    return false
  end
  if snap.now < readyAt then
    return false
  end
  target.noteAttack(snap, chosen)
  if native.attack(snap, chosen) then
    nextAttack = snap.now + math.max(1 / 15, 1 / speed - 0.025)
    return true
  end
  nextAttack = snap.now + 1 / 60
  return false
end
Sword.__contract = {
  provides = { "setup", "reset", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget" },
  requiresMethods = {
    Native = { "blocked", "findWeapon", "equip", "canHit", "stats", "attack" },
    Target = { "noteAttack" },
  },
}
return Sword
