-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics, tuning
local swapping, heldPearl = false, nil
local function restoreSword()
  local snap = native and native.snapshot()
  if not snap then return end
  local sword = native.findSword(snap)
  if sword and snap.tool ~= sword and (heldPearl or (snap.tool and snap.tool:GetAttribute("ClassItem") == "Pearl")) then
    native.equip(snap, sword)
  end
  if sword and sword.Parent == snap.character then heldPearl = nil end
end
local enemyPearl, projectile = nil, { speed = 96, gravity = 38.4, drag = 0.99 }
local outsideSince, pending, nextPlan = nil, nil, 0
local sessionCharacter, pursuit, spent = nil, nil, {}
function Pearl.setup(deps)
  native, target, ballistics, tuning = deps.Native, deps.Target, deps.Ballistics, deps.Options.tuning
  return true
end
-- Clearing transient state never grants another throw.
function Pearl.reset()
  if heldPearl then restoreSword() end
  local locked = target and target.locked()
  if locked then target.release(locked.character) end
  outsideSince, pending, pursuit = nil, nil, nil
end
function Pearl.busy() return swapping or (pending ~= nil and pending.phase == "confirm") end
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
local function enemyState(snap, chosen)
  if not enemyPearl or enemyPearl.target ~= chosen.character or snap.now - enemyPearl.at > 6 then return nil end
  local position = chosen.root.Position
  if enemyPearl.lastPosition then
    local dt = math.max(0.001, snap.now - enemyPearl.lastSample)
    if (position - enemyPearl.lastPosition).Magnitude > math.max(10, dt * 60) then
      enemyPearl.stableSince = snap.now
      enemyPearl.confirmed = false
      enemyPearl.moved = true
    end
  end
  enemyPearl.lastPosition, enemyPearl.lastSample = position, snap.now
  if enemyPearl.moved and (position - enemyPearl.launchPosition).Magnitude <= 6 then
    enemyPearl.cancelled = true
    enemyPearl.confirmed = false
    if enemyPearl.stableSince and snap.now - enemyPearl.stableSince < 0.3 then return "waiting" end
    return "cancelled"
  end
  local nearLanding = (position - enemyPearl.landing).Magnitude <= 9
  if nearLanding and not enemyPearl.stableSince then enemyPearl.stableSince = snap.now end
  if (nearLanding or enemyPearl.moved) and enemyPearl.stableSince and snap.now - enemyPearl.stableSince >= 0.3 then
    enemyPearl.confirmed = true
  end
  if enemyPearl.cancelled then return "cancelled" end
  return enemyPearl.confirmed and "ready" or "waiting"
end
local function worthFollowing(snap, chosen)
  return chosen.humanoid.Health > 0 and snap.humanoid.Health > 0
end
function Pearl.observeProjectile(action, id, kind, position, velocity, gravity, drag)
  local snap = native.snapshot()
  local chosen = target.locked()
  if not snap or not chosen then return end
  if pursuit and pursuit.id == id and action == "ProjectileEnd" and typeof(kind) == "Vector3" then
    pursuit.actualLanding, pursuit.impactedAt = kind, snap.now
    return
  end
  if action == "Projectile" and kind == "Pearl" and pursuit and not pursuit.id and snap.now - pursuit.sentAt < 0.7
    and typeof(position) == "Vector3" then
    local ownDistance = (position - pursuit.launchEye).Magnitude
    local unique = ownDistance <= 5
    for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
      local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
      if other ~= snap.player and root and (position - (root.Position + Vector3.new(0, 1.184, 0))).Magnitude <= ownDistance + 1 then unique = false end
    end
    if unique then
      pursuit.id, pursuit.accepted = id, true
      return
    end
  end
  if action == "ProjectileEnd" and enemyPearl and enemyPearl.id == id and typeof(kind) == "Vector3" then
    enemyPearl.landing, enemyPearl.at, enemyPearl.arrived = kind, snap.now, true
    return
  end
  if action == "ProjectileMove" and enemyPearl and enemyPearl.id == id and typeof(position) == "Vector3" and typeof(velocity) == "Vector3" then
    local landing = ballistics.landing(position, velocity, projectile.gravity, projectile.drag, filters(snap))
    if landing then enemyPearl.landing = landing end
    return
  end
  if action ~= "Projectile" or kind ~= "Pearl" or typeof(position) ~= "Vector3" or typeof(velocity) ~= "Vector3" then return end
  if velocity.Magnitude < 0.01 then return end
  projectile = { speed = velocity.Magnitude, gravity = tonumber(gravity) or 38.4, drag = tonumber(drag) or 0.99 }
  local distance = (position - (chosen.root.Position + Vector3.new(0, 1.184, 0))).Magnitude
  if distance > 5 or distance + 1 >= (position - snap.eye).Magnitude or not worthFollowing(snap, chosen) then return end
  for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
    if other ~= snap.player and other ~= chosen.player and other.Character then
      local root = other.Character:FindFirstChild("HumanoidRootPart")
      if root and (position - (root.Position + Vector3.new(0, 1.184, 0))).Magnitude < distance + 1 then return end
    end
  end
  local landing, flight = ballistics.landing(position, velocity, projectile.gravity, projectile.drag, filters(snap))
  if not landing then return end
  enemyPearl = { target = chosen.character, id = id, landing = landing, at = snap.now, launchPosition = chosen.root.Position, lastPosition = chosen.root.Position, lastSample = snap.now }
  target.hold(chosen.character, math.huge)
end
local function solve(snap, chosen)
  if enemyState(snap, chosen) == "waiting" then return nil end
  local params = filters(snap)
  local velocity = chosen.root.AssemblyLinearVelocity
  local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
  if horizontal.Magnitude > 45 then horizontal = Vector3.zero end
  local ping = 0.05
  local ok, value = pcall(snap.player.GetNetworkPing, snap.player)
  if ok and type(value) == "number" then ping = math.clamp(value, 0, 0.25) end
  local flight = 0.3
  for _ = 1, 16 do
    local predicted = chosen.root.Position + horizontal * (flight + ping)
    local floor = workspace:Raycast(predicted + Vector3.new(0, 8, 0), Vector3.new(0, -128, 0), params)
    if not floor then break end
    local aim, duration = ballistics.solve(snap.eye, floor.Position, projectile.speed, projectile.gravity, params, 6, projectile.drag)
    if not aim then break end
    if math.abs(duration - flight) * math.max(1, horizontal.Magnitude) < 0.5 then return aim, floor.Position, duration end
    flight = duration
  end
  local delta = chosen.root.Position - snap.root.Position
  for _, distance in ipairs({ 160, 128, 96, 64, 40, 24 }) do
    if delta.Magnitude <= distance then continue end
    local point = snap.root.Position + delta.Unit * distance
    local floor = workspace:Raycast(point + Vector3.new(0, 32, 0), Vector3.new(0, -256, 0), params)
    if floor and (floor.Position - chosen.root.Position).Magnitude + 8 < delta.Magnitude then
      local aim, time = ballistics.solve(snap.eye, floor.Position, projectile.speed, projectile.gravity, params, 6, projectile.drag)
      if aim then return aim, floor.Position, time end
    end
  end
  return nil
end
local function fleeing(snap, chosen)
  if enemyState(snap, chosen) == "ready" then return true end
  local delta = chosen.root.Position - snap.root.Position
  if delta.Magnitude < 0.01 then return false end
  local velocity = chosen.root.AssemblyLinearVelocity
  local relative = velocity - snap.root.AssemblyLinearVelocity
  return velocity:Dot(delta.Unit) >= 2 and relative:Dot(delta.Unit) >= 1
end
local function cancel(now)
  restoreSword()
  pending = nil
  nextPlan = now + 0.6
end
function Pearl.step(snap, chosen)
  if not pending or pending.phase ~= "confirm" then restoreSword() end
  local nearby = target.nearThreat(snap)
  if nearby and nearby.character ~= chosen.character and (not pending or pending.phase ~= "confirm") then
    Pearl.reset()
    return false
  end
  if sessionCharacter ~= snap.character then
    Pearl.reset()
    sessionCharacter, spent, nextPlan = snap.character, {}, 0
  end
  target.hold(chosen.character, math.huge)
  local token = target.hitToken()
  local enemyStatus = enemyState(snap, chosen)
  if pursuit and pursuit.target ~= chosen.character then pursuit = nil end
  if pursuit and pursuit.phase == "flight" then
    local actual = pursuit.actualLanding or pursuit.landing
    local arrived = (snap.root.Position - actual).Magnitude <= 12 and (snap.root.Position - pursuit.launch).Magnitude > 8
    if native.canHit(snap, chosen) or arrived or snap.now >= pursuit.deadline
      or (pursuit.impactedAt and snap.now - pursuit.impactedAt >= 0.4) then
      pursuit = nil
      nextPlan = math.max(nextPlan, snap.now + 0.25)
    end
  end
  if pending then
    if pending.character ~= snap.character or (pending.phase ~= "confirm" and pending.target ~= chosen.character) then cancel(snap.now) return false end
    if pending.phase == "confirm" then
      if (pursuit and pursuit.accepted) or not pending.tool.Parent or (tonumber(pending.tool:GetAttribute("Count")) or 0) < pending.count or not native.pearlReady() then
        if pursuit then pursuit.accepted = true end
        restoreSword()
        pending = nil
        return true
      end
      if snap.now >= pending.deadline then pursuit = nil cancel(snap.now) end
      return false
    end
    if native.canHit(snap, chosen) 
      or snap.now > pending.deadline or native.blocked(snap) or not native.pearlReady() then cancel(snap.now) return false end
    if snap.now < pending.ready then return false end
    -- Preparation and the final trajectory calculation happen with the sword still selected.
    local direction, landing, flight = solve(snap, chosen, pending.recovery)
    if not direction then cancel(snap.now) return false end
    local nearbyNow = target.nearThreat(snap)
    if nearbyNow and nearbyNow.character ~= chosen.character then cancel(snap.now) pursuit = nil return false end
    local tool = pending.tool
    if not tool or not tool.Parent then cancel(snap.now) return false end
    pending.count = tonumber(tool:GetAttribute("Count")) or 0
    local ok, sent = pcall(function()
      swapping, heldPearl = true, tool
      if not native.equip(snap, tool) then return false end
      local fresh = native.snapshot()
      if not fresh or fresh.tool ~= tool then return false end
      spent[chosen.character] = pending.token
      pursuit = { target = chosen.character, token = pending.token, phase = "flight", landing = landing,
        launch = fresh.root.Position, launchEye = fresh.eye, sentAt = fresh.now,
        corrections = pending.recovery and 1 or 0, deadline = fresh.now + math.max(1.5, flight + 0.9) }
      target.hold(chosen.character, math.huge)
      return native.usePearl(fresh, tool, direction)
    end)
    swapping = false
    if not ok or not sent then
      pursuit = nil
      cancel(snap.now)
      if not ok then error(sent) end
      return false
    end
    -- Keep the pearl selected until the server confirms its launch.
    pending.phase, pending.deadline = "confirm", snap.now + 0.9
    return true
  end
  if native.canHit(snap, chosen) then outsideSince = nil return false end
  outsideSince = outsideSince or snap.now
  if pursuit or snap.now < nextPlan or not native.pearlReady() or native.blocked(snap) then return false end
  if enemyStatus == "waiting" then return false end
  local recovery = true
  nextPlan = snap.now + 0.6
  local tool = native.findPearl(snap)
  if not tool then return false end
  local direction = solve(snap, chosen, recovery)
  if not direction then return false end
  pending = { tool = tool, target = chosen.character, character = snap.character, token = token, recovery = recovery, ready = snap.now + 0.16, deadline = snap.now + 0.6, phase = "plan" }
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step", "observeProjectile" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Options = "mcpoptions" },
  requiresMethods = { Native = { "snapshot", "findSword", "equip", "canHit", "findPearl", "usePearl", "pearlReady", "blocked" }, Target = { "hitToken", "reset", "hold", "locked", "nearThreat", "release" }, Ballistics = { "solve", "landing" } },
  requiresData = { Options = { "tuning" } },
}
return Pearl
