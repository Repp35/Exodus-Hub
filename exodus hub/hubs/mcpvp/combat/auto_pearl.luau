-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, geometry, target, units, ballistics, tuning, utils
local shot, motion, retryAt = nil, nil, 0
local speed, gravity, drag = 30, 12, 0.99
local HORIZONTAL = Vector3.new(1, 0, 1)
function Pearl.setup(deps)
  native, geometry, target, units, ballistics, tuning, utils =
    deps.Native, deps.Geometry, deps.Target, deps.Units, deps.Ballistics, deps.Options.tuning, deps.Utils
  return true
end
local function restore(snap)
  if not shot or shot.restored or not snap or shot.character ~= snap.character then
    return
  end
  local tool = utils.getConfigValue("MCAutoSword") and native.find(snap, "sword") or shot.previous
  if tool and tool.Parent then
    shot.restored = native.equip(snap, tool)
  end
end
function Pearl.reset()
  restore(native.snapshot())
  shot, motion, retryAt = nil, nil, 0
end
function Pearl.busy() return shot ~= nil and shot.phase == "equip" end
function Pearl.pending() return shot ~= nil end
function Pearl.projectile(action, _id, kind, _position, velocity, acceleration, resistance)
  if action ~= "Projectile" or kind ~= "Pearl" or typeof(velocity) ~= "Vector3" then
    return
  end
  local value = units.toBlocks(velocity.Magnitude)
  if value > 0 and value < 312.5 then
    speed = value
  end
  if type(acceleration) == "number" and acceleration > 0 then
    gravity = units.toBlocks(acceleration)
  end
  if type(resistance) == "number" and resistance > 0 and resistance <= 1 then
    drag = resistance
  end
end
local function observe(snap, value)
  local position = units.toBlocks(value.root.Position)
  local gap = (position - units.toBlocks(snap.root.Position)) * HORIZONTAL
  if not motion or motion.id ~= value.id then
    motion = { id = value.id, at = snap.now, position = position, gap = gap.Magnitude, velocity = Vector3.zero }
  end
  local elapsed = snap.now - motion.at
  if elapsed >= 0.1 then
    local velocity = (position - motion.position) * HORIZONTAL / elapsed
    local fleeing = elapsed < 0.5
      and velocity.Magnitude <= 14
      and gap.Magnitude >= 8
      and gap.Magnitude > motion.gap - 0.1
      and gap.Magnitude > 0
      and velocity:Dot(gap.Unit) > 2
      and (not motion.heading or velocity.Magnitude > 0 and velocity.Unit:Dot(motion.heading) > 0.85)
    if fleeing then
      motion.escapeAt, motion.escapeGap = motion.escapeAt or snap.now, motion.escapeGap or gap.Magnitude
      motion.leading = snap.now - motion.escapeAt >= 1 and gap.Magnitude >= motion.escapeGap - 0.1
    else
      motion.escapeAt, motion.escapeGap, motion.leading = nil, nil, false
    end
    motion.velocity = velocity.Magnitude <= 14 and velocity or Vector3.zero
    motion.heading = motion.velocity.Magnitude > 0 and motion.velocity.Unit or nil
    motion.position, motion.at, motion.gap = position, snap.now, gap.Magnitude
  end
end
local function plan(snap, value)
  local ignored = { snap.character, snap.camera }
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player.Character then
      ignored[#ignored + 1] = player.Character
    end
  end
  for _, name in ipairs({ "LocalItemVisuals", "LocalBowVisuals", "PredictedBlocks", "ArenaPvPBots" }) do
    local folder = workspace:FindFirstChild(name)
    if folder then
      ignored[#ignored + 1] = folder
    end
  end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  local origin, position = units.toBlocks(snap.eye), units.toBlocks(value.root.Position)
  local flight = (position - origin).Magnitude / speed
  for _ = 1, motion.leading and 6 or 1 do
    local destination = position + (motion.leading and motion.velocity * (flight + 0.08) or Vector3.zero)
    if (destination - units.toBlocks(snap.root.Position)).Magnitude > tuning.pearlRangeBlocks then
      return nil
    end
    local floor = workspace:Raycast(units.toWorld(destination - Vector3.new(0, 0.75, 0)), units.offset(0, -20, 0), params)
    if not floor then
      return nil
    end
    local landing = units.toBlocks(floor.Position)
    local direction, duration = ballistics.solve(origin, landing, speed, gravity, params, tuning.pearlMaxFlight, drag)
    if not direction then
      return nil
    end
    if not motion.leading or math.abs(duration - flight) < 0.02 then
      return direction, duration, landing
    end
    flight = duration
  end
  return nil
end
function Pearl.prepare(snap)
  if not utils.getConfigValue("MCAutoPearl") then
    Pearl.reset()
    return
  end
  local value = target.current(snap)
  if value then
    observe(snap, value)
  end
  if shot and shot.character ~= snap.character then
    Pearl.reset()
  end
  if shot and shot.phase == "flight" then
    restore(snap)
    local arrived = units.distance(snap.root.Position, units.toWorld(shot.landing + Vector3.new(0, 1.25, 0))) < 1
    if arrived or snap.now >= shot.untilAt then
      shot, retryAt = nil, snap.now + 0.2
    end
    return
  end
  if shot and (not value or value.id ~= shot.id or snap.now > shot.deadline) then
    restore(snap)
    shot, retryAt = nil, snap.now + 0.2
    return
  end
  if not value or not shot and snap.now < retryAt or native.blocked(snap) or geometry.aerialMace(snap, value) then
    return
  end
  local sword = native.find(snap, "sword")
  if value.distance <= (geometry.stats(sword or snap.tool).reach or 3) + 0.5 or geometry.direction(snap, value, sword or snap.tool) then
    if shot then
      restore(snap)
      shot = nil
    end
    return
  end
  if (tonumber(snap.player:GetAttribute("ItemCooldown_Pearl")) or 0) > workspace:GetServerTimeNow() then
    return
  end
  if not shot then
    retryAt = snap.now + 0.2
    local tool = native.find(snap, "Pearl")
    if not tool then
      return
    end
    local direction = plan(snap, value)
    if not direction then
      return
    end
    shot = { phase = "equip", character = snap.character, id = value.id, tool = tool, previous = snap.tool, deadline = snap.now + 0.8 }
    native.equip(snap, tool)
    return
  end
  if snap.tool ~= shot.tool then
    native.equip(snap, shot.tool)
    return
  end
  local direction, duration, landing = plan(snap, value)
  if not direction then
    restore(snap)
    shot = nil
    return
  end
  if native.use(snap, shot.tool, direction) then
    shot.phase, shot.landing, shot.untilAt = "flight", landing, snap.now + duration + 0.7
    target.attacked(snap, value)
    restore(snap)
  end
end
Pearl.__contract = {
  provides = { "setup", "reset", "prepare", "busy", "pending", "projectile" },
  requires = {
    Native = "mcpnative",
    Geometry = "mcpgeometry",
    Target = "mcptarget",
    Units = "mcpunits",
    Ballistics = "mcpballistics",
    Options = "mcpoptions",
    Utils = "utils",
  },
  requiresMethods = {
    Native = { "snapshot", "find", "equip", "use", "blocked" },
    Geometry = { "direction", "aerialMace", "stats" },
    Target = { "current", "attacked" },
    Units = { "toBlocks", "toWorld", "offset", "distance" },
    Ballistics = { "solve" },
    Utils = { "getConfigValue" },
  },
  requiresData = { Options = { "tuning" } },
}
return Pearl
