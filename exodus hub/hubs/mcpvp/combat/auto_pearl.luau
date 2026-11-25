-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics, tuning
local outsideSince, nextUse, pending = nil, 0, nil
local function restore(snap)
  if pending and snap and snap.character == pending.character and snap.tool == pending.tool then
    native.equip(snap, pending.previous)
  end
  pending = nil
end
function Pearl.setup(deps)
  native, target, ballistics, tuning = deps.Native, deps.Target, deps.Ballistics, deps.Options.tuning
  return true
end
function Pearl.reset()
  restore(native.snapshot())
  outsideSince, nextUse = nil, 0
end
function Pearl.busy() return pending ~= nil end
function Pearl.step(snap, chosen)
  if pending then
    if pending.character ~= snap.character or snap.now > pending.expires then
      restore(snap)
      return false
    end
    if snap.now < pending.ready then
      return false
    end
    if snap.tool ~= pending.tool then
      restore(snap)
      return false
    end
    if native.usePearl(snap, pending.tool, pending.direction) then
      nextUse = snap.now + native.pearlCooldown()
      target.touch(snap.now)
    end
    restore(snap)
    return true
  end
  if native.canHit(snap, chosen) then
    outsideSince = nil
    return false
  end
  outsideSince = outsideSince or snap.now
  if snap.now - outsideSince < tuning.pearlDelay or snap.now < nextUse then
    return false
  end
  local tool = native.findPearl(snap)
  if not tool then
    return false
  end
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = { snap.character }
  local direction = ballistics.solve(snap.eye, chosen.root.Position, tuning.pearlSpeed, tuning.pearlGravity, params)
  if not direction then
    return false
  end
  local previous = snap.tool
  if not native.equip(snap, tool) then
    return false
  end
  pending = { tool = tool, previous = previous, character = snap.character, direction = direction, ready = snap.now + 0.05, expires = snap.now + 0.4 }
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Options = "mcpoptions" },
  requiresMethods = { Native = { "snapshot", "equip", "canHit", "findPearl", "usePearl", "pearlCooldown" }, Target = { "touch" }, Ballistics = { "solve" } },
  requiresData = { Options = { "tuning" } },
}
return Pearl
