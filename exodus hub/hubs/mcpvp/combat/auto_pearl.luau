-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics, tuning
local outsideSince, pending, nextPlan = nil, nil, 0
local sessionCharacter, pursuit, spent = nil, nil, {}
function Pearl.setup(deps)
  native, target, ballistics, tuning = deps.Native, deps.Target, deps.Ballistics, deps.Options.tuning
  return true
end
-- Clearing transient state never grants another throw.
function Pearl.reset() outsideSince, pending, pursuit = nil, nil, nil end
function Pearl.busy() return pending ~= nil end
local function filters(snap)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  local ignored = { snap.camera }
  for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
    if other.Character then ignored[#ignored + 1] = other.Character end
  end
  for _, name in ipairs({ "LocalItemVisuals", "PredictedBlocks", "ArenaPvPBots" }) do
    local folder = workspace:FindFirstChild(name)
    if folder then ignored[#ignored + 1] = folder end
  end
  params.FilterDescendantsInstances = ignored
  return params
end
local function solve(snap, chosen)
  local params = filters(snap)
  local velocity = chosen.root.AssemblyLinearVelocity
  if math.abs(velocity.Y) > 8 or velocity.Magnitude > 45 then return nil end
  local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
  local flight, direction, destination = 0.25, nil, nil
  for _ = 1, 4 do
    local predicted = chosen.root.Position + horizontal * flight
    local floor = workspace:Raycast(predicted + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
    if not floor or floor.Normal.Y < 0.65 then return nil end
    destination = floor.Position
    local duration
    direction, duration = ballistics.solve(snap.eye, destination, tuning.pearlSpeed, tuning.pearlGravity, params)
    if not direction or not duration or duration > 0.75 then return nil end
    if math.abs(duration - flight) < 0.015 then return direction, destination end
    flight = duration
  end
  -- Refuse unstable interception instead of throwing at a stale position.
  return nil
end
local function fleeing(snap, chosen)
  local delta = chosen.root.Position - snap.root.Position
  if delta.Magnitude < 0.01 then return false end
  local velocity = chosen.root.AssemblyLinearVelocity
  local relative = velocity - snap.root.AssemblyLinearVelocity
  return velocity:Dot(delta.Unit) >= 2 and relative:Dot(delta.Unit) >= 1
end
local function cancel(now)
  pending = nil
  nextPlan = now + 0.6
end
function Pearl.step(snap, chosen)
  if sessionCharacter ~= snap.character then
    Pearl.reset()
    sessionCharacter, spent, nextPlan = snap.character, {}, 0
  end
  local token, hitAt, hitTarget = target.hitToken()
  if pursuit then
    if pursuit.target ~= chosen.character or (hitTarget == chosen.character and token > pursuit.token) then
      pursuit = nil
    elseif snap.now >= pursuit.deadline then
      Pearl.reset()
      target.reset()
      return false
    end
  end
  if pending then
    if pending.character ~= snap.character or pending.target ~= chosen.character then cancel(snap.now) return false end
    if pending.phase == "confirm" then
      if not pending.tool.Parent or (tonumber(pending.tool:GetAttribute("Count")) or 0) < pending.count or not native.pearlReady() then
        pending = nil
        return true
      end
      if snap.now >= pending.deadline then cancel(snap.now) end
      return false
    end
    if native.canHit(snap, chosen) or not fleeing(snap, chosen) or snap.now > pending.deadline then cancel(snap.now) return false end
    if snap.tool ~= pending.tool or snap.now < pending.ready then return false end
    local direction = solve(snap, chosen)
    if not direction then cancel(snap.now) return false end
    pending.count = tonumber(pending.tool:GetAttribute("Count")) or 0
    -- Spend the authorization before sending, even if the game rejects the use.
    spent[chosen.character] = pending.token
    pursuit = { target = chosen.character, token = pending.token, deadline = snap.now + tuning.pearlGiveUp }
    if native.usePearl(snap, pending.tool, direction) then
      pending.phase, pending.deadline = "confirm", snap.now + 0.6
    else
      cancel(snap.now)
    end
    return true
  end
  if native.canHit(snap, chosen) then outsideSince = nil return false end
  outsideSince = outsideSince or snap.now
  local gap = (chosen.root.Position - snap.root.Position).Magnitude
  if pursuit or not fleeing(snap, chosen) or hitTarget ~= chosen.character or token <= (spent[chosen.character] or -1)
    or snap.now - hitAt > tuning.pearlHitAge or gap < tuning.pearlMinGap or gap > tuning.pearlMaxGap
    or snap.now - outsideSince < tuning.pearlDelay or snap.now < nextPlan
    or not native.pearlReady() or native.blocked(snap) then return false end
  nextPlan = snap.now + 0.6
  local tool = native.findPearl(snap)
  if not tool then return false end
  local direction = solve(snap, chosen)
  if not direction then return false end
  if not native.equip(snap, tool) then return false end
  pending = { tool = tool, target = chosen.character, character = snap.character, token = token, ready = snap.now + 0.16, deadline = snap.now + 0.6, phase = "equip" }
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Options = "mcpoptions" },
  requiresMethods = { Native = { "equip", "canHit", "findPearl", "usePearl", "pearlReady", "blocked" }, Target = { "hitToken", "reset" }, Ballistics = { "solve" } },
  requiresData = { Options = { "tuning" } },
}
return Pearl
