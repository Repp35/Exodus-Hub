-- [[ autoattacksword ]]
--!optimize 2
local Sword = {}
local native, target, crit
local nextAttack, selected, equipAt = 0, nil, 0
function Sword.setup(deps)
  native, target, crit = deps.Native, deps.Target, deps.Crit
  return true
end
function Sword.reset()
  nextAttack, selected, equipAt = 0, nil, 0
  if crit then
    crit.reset()
  end
end
function Sword.step(snap, chosen)
  if native.aerialMace(snap, chosen) then
    crit.reset()
    return false
  end
  crit.observe(snap)
  if native.blocked(snap) then
    return false
  end
  local tool = native.findSword(snap)
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
  if not native.canHit(snap, chosen, tool, snap.camera.CFrame.LookVector) then
    return false
  end
  if not crit.ready(snap, chosen, tool, readyAt) then
    return false
  end
  target.noteAttack(snap, chosen)
  if native.attack(snap, chosen) then
    nextAttack = snap.now + 1 / speed
    return true
  end
  nextAttack = snap.now + 0.25
  return false
end
Sword.__contract = {
  provides = { "setup", "reset", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget", Crit = "autocrit" },
  requiresMethods = {
    Native = { "aerialMace", "visible", "blocked", "findSword", "equip", "canHit", "stats", "attack" },
    Target = { "noteAttack" },
    Crit = { "reset", "observe", "plan", "ready" },
  },
}
return Sword
