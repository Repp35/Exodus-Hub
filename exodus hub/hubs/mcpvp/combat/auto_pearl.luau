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
    return false
  end
  shot.restored = native.restore(snap, shot.previous ~= shot.tool and shot.previous or nil)
  return shot.restored
end
function Pearl.reset()
  local snap = native.snapshot()
  if shot and (shot.phase == "confirm" or shot.phase == "restore") and snap and shot.character == snap.character then
    motion = nil
    return
  end
  restore(snap)
  shot, motion, retryAt = nil, nil, 0
end
function Pearl.busy() return shot ~= nil and shot.phase ~= "flight" end
function Pearl.pending() return shot ~= nil end
function Pearl.escaping() return shot ~= nil and shot.phase == "flight" and shot.escape == true end
function Pearl.cancelPrepared(snap)
  if shot and shot.phase == "equip" then
    restore(snap)
    shot = nil
  end
end
function Pearl.observe(snap)
  if not shot or shot.character ~= snap.character then
    return
  end
  if shot.phase == "confirm" then
    local state = native.useState(snap, shot)
    if state == nil then
      return
    end
    if state == false then
      restore(snap)
      shot, retryAt = nil, snap.now + 1
      return true
    end
    shot.restoreAt = snap.now
    shot.phase, shot.untilAt = "restore", math.max(snap.now + 0.2, shot.requestAt + shot.plan.duration + 0.7)
    if shot.chosen then
      target.attacked(snap, shot.chosen)
    end
  end
  if shot.phase == "restore" and not native.blocked(snap) then
    local restored = restore(snap)
    if restored or snap.now - shot.restoreAt >= 1 then
      shot.phase = "flight"
      return true
    end
  elseif shot.phase == "flight" then
    local arrived = units.distance(snap.root.Position, units.toWorld(shot.plan.landing + Vector3.new(0, 1.25, 0))) < 1
    if arrived or snap.now >= shot.untilAt then
      shot, retryAt = nil, snap.now + 0.2
    end
  end
end
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
local function params(snap)
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
  local ray = RaycastParams.new()
  ray.FilterType, ray.RespectCanCollide, ray.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  return ray
end
-- Destination is a root position in blocks; land on the floor at its feet.
function Pearl.route(snap, position, elevated)
  local ray, origin = params(snap), units.toBlocks(snap.eye)
  local start = position + Vector3.new(0, elevated and 12 or -0.75, 0)
  local floor = workspace:Raycast(units.toWorld(start), units.offset(0, elevated and -48 or -24, 0), ray)
  if not floor then
    return nil
  end
  local landing = units.toBlocks(floor.Position)
  local direction, duration = ballistics.solve(origin, landing, speed, gravity, ray, tuning.pearlMaxFlight, drag)
  return direction and { direction = direction, duration = duration, landing = landing } or nil
end
local function track(snap, value)
  local position = units.toBlocks(value.root.Position)
  if not motion or motion.id ~= value.id then
    motion = { id = value.id, at = snap.now, position = position, velocity = Vector3.zero }
  end
  local elapsed = snap.now - motion.at
  if elapsed >= 0.05 then
    local velocity = (position - motion.position) * HORIZONTAL / elapsed
    motion.velocity = elapsed <= 0.35 and velocity.Magnitude <= 14 and velocity or Vector3.zero
    motion.position, motion.at = position, snap.now
  end
end
local function plan(snap, value)
  local position = units.toBlocks(value.root.Position)
  local velocity = motion and motion.velocity or Vector3.zero
  local flight, result = (position - units.toBlocks(snap.eye)).Magnitude / speed, nil
  for _ = 1, 4 do
    -- Intercept the legs at impact time; never add an arbitrary lead beyond the opponent.
    local destination = position + velocity * flight
    result = Pearl.route(snap, destination)
    if not result then
      break
    end
    if math.abs(result.duration - flight) < 0.02 then
      return result
    end
    flight = result.duration
  end
  if result then
    return result
  end
  -- A tiny floor offset handles a player standing at the edge of a block.
  for _, offset in ipairs({ Vector3.zero, Vector3.new(0.4, 0, 0), Vector3.new(-0.4, 0, 0), Vector3.new(0, 0, 0.4), Vector3.new(0, 0, -0.4) }) do
    local route = Pearl.route(snap, position + offset)
    if route then
      return route
    end
  end
  return nil
end
local function advance(snap)
  if not shot or shot.phase ~= "equip" then
    return
  end
  if snap.now > shot.deadline then
    restore(snap)
    shot, retryAt = nil, snap.now + 0.2
    return
  end
  if not native.equip(snap, shot.tool) then
    return
  end
  shot.count, shot.requestAt, shot.phase = tonumber(shot.tool:GetAttribute("Count")) or 0, snap.now, "confirm"
  if not native.use(snap, shot.tool, shot.plan.direction) then
    shot.phase = "equip"
  end
end
function Pearl.launch(snap, route, escaping)
  Pearl.observe(snap)
  if shot or not route or snap.now < retryAt or native.blocked(snap) then
    return false
  end
  if (tonumber(snap.player:GetAttribute("ItemCooldown_Pearl")) or 0) > workspace:GetServerTimeNow() then
    return false
  end
  local tool = native.find(snap, "Pearl", true)
  if not tool then
    return false
  end
  shot = { phase = "equip", character = snap.character, tool = tool, previous = snap.tool, escape = escaping == true, plan = route, deadline = snap.now + 0.8 }
  advance(snap)
  return shot ~= nil
end
function Pearl.advance(snap) advance(snap) end
function Pearl.prepare(snap)
  if shot and shot.character ~= snap.character then
    shot, motion = nil, nil
  end
  Pearl.observe(snap)
  if shot and shot.phase ~= "equip" then
    return
  end
  local value = target.current(snap)
  if not utils.getConfigValue("MCAutoPearl") or not value then
    if shot and shot.phase == "equip" then
      Pearl.reset()
    end
    return
  end
  track(snap, value)
  if shot then
    if not shot.chosen or value.id ~= shot.chosen.id then
      Pearl.reset()
      return
    end
    local route = plan(snap, value)
    if not route then
      target.abandon(snap, value)
      Pearl.reset()
      return
    end
    shot.plan = route
    advance(snap)
    return
  end
  if snap.now < retryAt or native.blocked(snap) or geometry.aerialMace(snap, value) then
    return
  end
  local weapon = native.weapon(snap, value) or snap.tool
  if value.distance <= (geometry.stats(weapon).reach or 3) + 0.25 and geometry.direction(snap, value, weapon) then
    return
  end
  if not native.find(snap, "Pearl", true) or (tonumber(snap.player:GetAttribute("ItemCooldown_Pearl")) or 0) > workspace:GetServerTimeNow() then
    return
  end
  local route = plan(snap, value)
  if not route then
    target.abandon(snap, value)
    return
  end
  if Pearl.launch(snap, route) and shot then
    shot.chosen = value
  else
    retryAt = snap.now + 0.15
  end
end
Pearl.__contract = {
  provides = { "setup", "reset", "prepare", "observe", "busy", "pending", "projectile", "route", "launch", "advance", "escaping", "cancelPrepared" },
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
    Native = { "snapshot", "find", "weapon", "restore", "equip", "use", "useState", "blocked" },
    Geometry = { "direction", "aerialMace", "stats" },
    Target = { "current", "attacked", "abandon" },
    Units = { "toBlocks", "toWorld", "offset", "distance" },
    Ballistics = { "solve" },
    Utils = { "getConfigValue" },
  },
  requiresData = { Options = { "tuning" } },
}
return Pearl
