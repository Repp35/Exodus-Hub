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
  if not shot or shot.restored or not snap or snap.character ~= shot.character or snap.tool and snap.tool ~= shot.tool then
    return
  end
  local tool = shot.previous
  if not tool or not tool.Parent then
    tool = native.findSword(snap)
  end
  if tool then
    shot.restored = native.equip(snap, tool)
  end
end
function Pearl.reset()
  restore(native.snapshot())
  shot, track, retryAt = nil, nil, 0
end
local function finish(snap, delay)
  restore(snap)
  shot, track, retryAt = nil, nil, snap.now + delay
end
function Pearl.busy() return shot ~= nil and not shot.detached and (shot.phase == "equip" or shot.phase == "confirm" and not shot.dispatched) end
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
  local gap = (position - units.toBlocks(snap.root.Position)) * HORIZONTAL
  if not track or track.owner ~= snap.character or track.character ~= chosen.character or track.sessionId ~= chosen.sessionId then
    track = {
      owner = snap.character,
      character = chosen.character,
      sessionId = chosen.sessionId,
      position = position,
      velocity = velocity,
      gap = gap.Magnitude,
      at = snap.now,
    }
    return velocity
  end
  local elapsed = snap.now - track.at
  if elapsed >= 0.1 then
    local measured
    if elapsed <= 0.5 then
      measured = (position - track.position) * HORIZONTAL / elapsed
      if measured.Magnitude <= 14 then
        velocity = (velocity + measured) * 0.5
      end
    end
    local outward = gap.Magnitude > 0.001 and gap.Unit or Vector3.zero
    local escaping = measured
      and measured.Magnitude <= 14
      and gap.Magnitude >= 8
      and measured:Dot(outward) >= 2
      and velocity:Dot(outward) >= 2
      and gap.Magnitude >= track.gap - 0.1
    local heading = velocity.Magnitude > 0.001 and velocity.Unit or Vector3.zero
    if not escaping or track.heading and heading:Dot(track.heading) < 0.85 then
      track.escapeAt, track.escapeGap, track.leading = nil, nil, false
    else
      track.escapeAt, track.escapeGap = track.escapeAt or snap.now, track.escapeGap or gap.Magnitude
      track.leading = snap.now - track.escapeAt >= 1 and gap.Magnitude - track.escapeGap >= 1
    end
    track.heading, track.gap = heading, gap.Magnitude
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
  local leading = track and track.leading == true
  local delay = transportDelay + 0.05
  local sword = native.findSword(snap)
  local reach = native.stats(sword or snap.tool).reachBlocks or 3
  local flight = math.clamp((position - origin).Magnitude / speed, 0.1, tuning.pearlMaxFlight)
  for _ = 1, leading and 8 or 1 do
    -- Direct throws are the default. Only sustained, distant escape enables interception.
    local destination = position + (leading and motion * (flight + delay) or Vector3.zero)
    if (destination - playerPosition).Magnitude > tuning.pearlRangeBlocks + reach then
      break
    end
    local floor = workspace:Raycast(units.toWorld(destination - Vector3.new(0, 0.75, 0)), units.offset(0, -20, 0), params)
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
    local inReach = (landing + Vector3.new(0, 1.25, 0) - actualFuture).Magnitude <= reach
    local closer = gap.Magnitude + 0.5 < ((position - playerPosition) * HORIZONTAL).Magnitude
    if (not leading or math.abs(duration - flight) * math.max(1, motion.Magnitude) <= 0.15) and inReach and closer then
      return direction, duration, landing
    end
    flight = duration
  end
  return nil
end
function Pearl.step(snap, chosen)
  if shot and shot.character ~= snap.character then
    finish(snap, 0.25)
  end
  local motion = chosen and observe(snap, chosen)
  if shot then
    if shot.phase ~= "equip" and (not chosen or chosen.sessionId ~= shot.sessionId or chosen.character ~= shot.target) then
      -- The projectile cannot be recalled, but it no longer owns combat or camera focus.
      restore(snap)
      shot.detached = true
    end
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
      if native.canHit(snap, chosen, native.findSword(snap) or snap.tool) then
        finish(snap, 0.2)
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
      shot.dispatched = true
      -- The use was dispatched; confirmation can continue while the sword is held again.
      restore(snap)
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
  if native.canHit(snap, chosen, native.findSword(snap) or snap.tool) then
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
    },
    Ballistics = { "solve" },
    Target = { "follow", "isCurrent" },
  },
}
return Pearl
