-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics, tuning
local outsideSince, nextUse, pending = nil, 0, nil
function Pearl.setup(deps)
  native, target, ballistics, tuning = deps.Native, deps.Target, deps.Ballistics, deps.Options.tuning
  return true
end
-- Cancelling never selects another item and never erases the attempt cooldown.
function Pearl.reset() outsideSince, pending = nil, nil end
function Pearl.busy() return pending ~= nil end
local function solve(snap, chosen)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  -- Native projectile simulation excludes character models.
  local ignored = { snap.camera }
  for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
    if other.Character then ignored[#ignored + 1] = other.Character end
  end
  for _, name in ipairs({ "LocalItemVisuals", "PredictedBlocks", "ArenaPvPBots" }) do
    local folder = workspace:FindFirstChild(name)
    if folder then ignored[#ignored + 1] = folder end
  end
  params.FilterDescendantsInstances = ignored
  return ballistics.solve(snap.eye, chosen.root.Position, tuning.pearlSpeed, tuning.pearlGravity, params)
end
function Pearl.step(snap, chosen)
  if pending then
    if pending.character ~= snap.character or pending.target ~= chosen.character then Pearl.reset() return false end
    if pending.phase == "confirm" then
      local count = tonumber(pending.tool:GetAttribute("Count")) or 0
      if not native.pearlReady() or count < pending.count or not pending.tool.Parent then
        nextUse = math.max(nextUse, snap.now + native.pearlCooldown())
        target.touch(snap.now)
        pending, outsideSince = nil, snap.now
        return true
      end
      if snap.now >= pending.deadline then
        nextUse = math.max(nextUse, snap.now + 1)
        pending = nil
      end
      return false
    end
    if snap.now > pending.deadline or native.canHit(snap, chosen) then pending = nil return false end
    if snap.tool ~= pending.tool then return false end
    if snap.now < pending.ready then return false end
    -- Recompute after equip, using the opponent's latest position.
    local direction = solve(snap, chosen)
    if not direction then pending = nil nextUse = snap.now + 0.5 return false end
    pending.count = tonumber(pending.tool:GetAttribute("Count")) or 0
    nextUse = snap.now + math.max(1, native.pearlCooldown())
    if native.usePearl(snap, pending.tool, direction) then
      pending.phase, pending.deadline = "confirm", snap.now + 0.9
    else
      pending = nil
    end
    return true
  end
  if native.canHit(snap, chosen) then outsideSince = nil return false end
  outsideSince = outsideSince or snap.now
  if snap.now - outsideSince < tuning.pearlDelay or snap.now < nextUse or not native.pearlReady() or native.blocked(snap) then return false end
  local tool = native.findPearl(snap)
  if not tool then return false end
  local direction = solve(snap, chosen)
  if not direction then nextUse = snap.now + 0.25 return false end
  -- Rate-limit before switching, even if equip is rejected.
  nextUse = snap.now + 1
  if not native.equip(snap, tool) then return false end
  pending = { tool = tool, character = snap.character, target = chosen.character, phase = "equip", ready = snap.now + 0.12, deadline = snap.now + 0.75 }
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Options = "mcpoptions" },
  requiresMethods = { Native = { "equip", "canHit", "findPearl", "usePearl", "pearlCooldown", "pearlReady", "blocked" }, Target = { "touch" }, Ballistics = { "solve" } },
  requiresData = { Options = { "tuning" } },
}
return Pearl
