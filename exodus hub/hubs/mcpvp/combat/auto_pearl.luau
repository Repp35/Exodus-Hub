-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, ballistics, tuning, units, target
local shot, track, retryAt = nil, nil, 0
local speed, gravity, drag, transportDelay = 30, 12, 0.99, 0.08
local HORIZONTAL = Vector3.new(1, 0, 1)
function Pearl.setup(deps)
  native, ballistics, tuning, units, target = deps.Native, deps.Ballistics, deps.Options.tuning, deps.Units, deps.Target
  return true
end
local function restore(snap)
  if not shot or not snap or snap.character ~= shot.character or snap.tool and snap.tool ~= shot.tool then
    return
  end
  local tool = shot.previous
  if not tool or not tool.Parent then
    tool = native.findSword(snap)
  end
  if tool then
    native.equip(snap, tool)
  end
end
function Pearl.reset()
  restore(native.snapshot())
  shot, track, retryAt = nil, nil, 0
end
local function finish(snap, delay)
  restore(snap)
  shot, retryAt = nil, snap.now + delay
end
function Pearl.busy() return shot ~= nil and shot.phase ~= "flight" end
function Pearl.pending() return shot ~= nil end
function Pearl.observeProjectile(action, _id, kind, _position, velocity, acceleration, resistance, sentAt)
  if action ~= "Projectile" or kind ~= "Pearl" or typeof(velocity) ~= "Vector3" then
    return
  end
  local observedSpeed = units.toBlocks(velocity.Magnitude)
  if observedSpeed > 0 and observedSpeed < 312.5 then
    speed = observedSpeed
  end
  if type(acceleration) == "number" and acceleration > 0 and units.toBlocks(acceleration) < 312.5 then
    gravity = units.toBlocks(acceleration)
  end
  if type(resistance) == "number" and resistance > 0 and resistance <= 1 then
    drag = resistance
  end
  if type(sentAt) == "number" then
    local lag = workspace:GetServerTimeNow() - sentAt
    if lag >= 0 and lag <= 0.5 then
      transportDelay = transportDelay * 0.5 + math.min(0.25, lag) * 0.5
    end
  end
end
local function observe(snap, chosen)
  local position = units.toBlocks(chosen.root.Position)
  local velocity = units.toBlocks(chosen.root.AssemblyLinearVelocity) * HORIZONTAL
  if velocity.Magnitude > 14 then
    velocity = velocity.Unit * 14
  end
  if not track or track.character ~= chosen.character then
    track = { character = chosen.character, position = position, velocity = velocity, at = snap.now }
    return velocity
  end
  local elapsed = snap.now - track.at
  if elapsed >= 0.04 then
    if elapsed <= 0.5 then
      local measured = (position - track.position) * HORIZONTAL / elapsed
      if measured.Magnitude <= 14 then
        velocity = (velocity + measured) * 0.5
      end
    end
    track.position, track.at = position, snap.now
  end
  track.velocity = track.velocity:Lerp(velocity, 0.7)
  return track.velocity
end
local function rayParams(snap)
  local ignored = { snap.camera }
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player.Character then
      ignored[#ignored + 1] = player.Character
    end
  end
  for _, name in ipairs({ "LocalItemVisuals", "PredictedBlocks", "ArenaPvPBots" }) do
    local folder = workspace:FindFirstChild(name)
    if folder then
      ignored[#ignored + 1] = folder
    end
  end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  return params
end
local function plan(snap, chosen, motion)
  local params = rayParams(snap)
  local origin, position = units.toBlocks(snap.eye), units.toBlocks(chosen.root.Position)
  local playerPosition = units.toBlocks(snap.root.Position)
  local rear = native.shieldBlocks(snap, chosen) and native.shieldRear(chosen.character, chosen.root)
  local forward = motion.Magnitude >= 0.5 and motion.Unit or (position - playerPosition) * HORIZONTAL
  if forward.Magnitude < 0.001 then
    return nil
  end
  forward = forward.Unit
  local approach = rear or forward
  local ahead = rear and 1.4 or math.clamp(0.75 + motion.Magnitude * 0.12, 0.75, 1.6)
  local side = Vector3.new(-approach.Z, 0, approach.X)
  local delay = transportDelay + 0.05
  local sword = native.findSword(snap)
  local reach = native.stats(sword or snap.tool).reachBlocks or 3
  for _, lateral in ipairs({ 0, 0.6, -0.6 }) do
    local flight = math.clamp((position - origin).Magnitude / speed, 0.1, tuning.pearlMaxFlight)
    for _ = 1, 8 do
      -- Lead by travel AND replication time, then stand ahead instead of at the old feet position.
      local future = position + motion * (flight + delay)
      local destination = future + approach * ahead + side * lateral
      if (destination - playerPosition).Magnitude > tuning.pearlRangeBlocks + reach then
        break
      end
      local floor = workspace:Raycast(units.toWorld(destination + Vector3.new(0, 1, 0)), units.offset(0, -20, 0), params)
      if not floor then
        break
      end
      local landing = units.toBlocks(floor.Position)
      local direction, duration = ballistics.solve(origin, landing, speed, gravity, params, tuning.pearlMaxFlight, drag)
      if not direction then
        break
      end
      local actualFuture = position + motion * (duration + delay)
      local gap = (landing - actualFuture) * HORIZONTAL
      local inFront = gap:Dot(approach) >= (rear and 0.5 or 0.4)
      local inReach = (landing + Vector3.new(0, 1.25, 0) - actualFuture).Magnitude <= reach
      if math.abs(duration - flight) * math.max(1, motion.Magnitude) <= 0.15 and inFront and inReach then
        return direction, duration, landing
      end
      flight = duration
    end
  end
  -- No throw is better than a fallback that repeatedly lands behind a runner.
  return nil
end
function Pearl.step(snap, chosen)
  if shot and shot.character ~= snap.character then
    finish(snap, 0.25)
  end
  local motion = chosen and observe(snap, chosen)
  if shot then
    if shot.phase == "equip" then
      if
        snap.now >= shot.deadline
        or not chosen
        or chosen.character ~= shot.target
        or chosen.sessionId ~= shot.sessionId
        or not target.isCurrent(snap, chosen)
        or units.distance(chosen.root.Position, snap.root.Position) > tuning.pearlRangeBlocks
      then
        finish(snap, 0.3)
        return false
      end
      if snap.tool ~= shot.tool or native.blocked(snap) then
        return false
      end
      local direction, duration, landing = plan(snap, chosen, motion)
      if not direction then
        finish(snap, 0.4)
        return false
      end
      shot.count, shot.landing = tonumber(shot.tool:GetAttribute("Count")) or 1, landing
      shot.phase, shot.sentAt, shot.duration = "confirm", snap.now, duration
      shot.deadline, shot.arrival = snap.now + 1.2, snap.now + duration + transportDelay + 0.6
      if not native.usePearl(snap, shot.tool, direction) then
        finish(snap, 0.4)
        return false
      end
      target.follow(snap, chosen)
      return true
    end
    if shot.phase == "confirm" then
      local consumed = not shot.tool.Parent or (tonumber(shot.tool:GetAttribute("Count")) or shot.count) < shot.count
      if not consumed and native.pearlReady() then
        if snap.now >= shot.deadline then
          finish(snap, math.max(0.5, native.pearlCooldown()))
        end
        return false
      end
      restore(snap)
      shot.phase = "flight"
    end
    -- An already sent pearl remains tracked even if focus changes. Never queue another during its flight.
    local teleported = snap.character:GetAttribute("PearlTeleportAt") ~= shot.teleportAt
    local arrived = snap.now - shot.sentAt >= shot.duration * 0.75
      and (units.toBlocks(snap.root.Position) - shot.landing - Vector3.new(0, 1.25, 0)).Magnitude < 0.75
    if teleported or arrived or snap.now >= shot.arrival then
      finish(snap, 0.3)
    end
    return false
  end
  if
    not chosen
    or not target.isCurrent(snap, chosen)
    or snap.now < retryAt
    or native.blocked(snap)
    or not native.pearlReady()
    or units.distance(chosen.root.Position, snap.root.Position) > tuning.pearlRangeBlocks
    or native.aerialMace(snap, chosen)
  then
    return false
  end
  if native.canHit(snap, chosen) and not native.shieldBlocks(snap, chosen) then
    return false
  end
  retryAt = snap.now + 0.4
  local tool = native.findPearl(snap)
  if not tool then
    return false
  end
  if not plan(snap, chosen, motion) then
    return false
  end
  shot = {
    character = snap.character,
    target = chosen.character,
    sessionId = chosen.sessionId,
    previous = snap.tool,
    tool = tool,
    phase = "equip",
    deadline = snap.now + 0.9,
    teleportAt = snap.character:GetAttribute("PearlTeleportAt"),
  }
  if not native.equip(snap, tool) then
    finish(snap, 0.4)
    return false
  end
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "pending", "step", "observeProjectile" },
  requires = { Native = "mcpnative", Options = "mcpoptions", Ballistics = "mcpballistics", Units = "mcpunits", Target = "mcptarget" },
  requiresData = { Options = { "tuning" } },
  requiresMethods = {
    Units = { "toBlocks", "toWorld", "offset", "distance" },
    Native = {
      "snapshot",
      "findSword",
      "equip",
      "findPearl",
      "usePearl",
      "pearlReady",
      "pearlCooldown",
      "blocked",
      "canHit",
      "aerialMace",
      "stats",
      "shieldRear",
      "shieldBlocks",
    },
    Ballistics = { "solve" },
    Target = { "follow", "isCurrent" },
  },
}
return Pearl
