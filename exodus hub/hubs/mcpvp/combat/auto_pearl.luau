-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, geometry, target, units, ballistics, tuning, utils, aim
local shot, motion, retryAt = nil, nil, 0
local speed, gravity, drag, inheritance = 30, 12, 0.99, 0
local FLAT = Vector3.new(1, 0, 1)
function Pearl.setup(deps)
  native, geometry, target, units, ballistics, tuning, utils, aim =
    deps.Native, deps.Geometry, deps.Target, deps.Units, deps.Ballistics, deps.Options.tuning, deps.Utils, deps.Aim
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
    shot.restoreAt, shot.phase = snap.now, "restore"
    shot.untilAt = math.max(snap.now + 0.2, shot.requestAt + shot.plan.duration + 0.7)
    if shot.chosen then
      target.attacked(snap, shot.chosen)
    end
  end
  if shot.phase == "restore" and not native.blocked(snap) then
    if restore(snap) or snap.now - shot.restoreAt >= 1 then
      shot.phase = "flight"
      return true
    end
  elseif shot.phase == "flight" then
    local moved = units.distance(snap.root.Position, shot.requestRoot) >= 2
    local arrived = moved and units.distance(snap.root.Position, units.toWorld(shot.plan.landing)) < 3
    if arrived or snap.now >= shot.untilAt then
      shot, retryAt = nil, snap.now + 0.15
    end
  end
end
function Pearl.projectile(action, _id, kind, position, velocity, acceleration, resistance)
  if
    action ~= "Projectile"
    or kind ~= "Pearl"
    or not shot
    or not shot.requestAt
    or shot.calibrated
    or shot.phase == "equip"
    or os.clock() - shot.requestAt > 1
    or typeof(position) ~= "Vector3"
    or typeof(velocity) ~= "Vector3"
  then
    return
  end
  local measured = units.toBlocks(velocity)
  if (units.toBlocks(position) - shot.plan.origin).Magnitude > 2 or measured.Magnitude < 1 or measured.Unit:Dot(shot.plan.direction) < 0.95 then
    return
  end
  -- Other players' pearls must not change our launch model.
  shot.calibrated = true
  local movement, direction = shot.requestVelocity, shot.plan.direction
  local perpendicular = movement - direction * movement:Dot(direction)
  if perpendicular.Magnitude > 0.15 then
    inheritance = math.clamp(perpendicular:Dot(measured - direction * measured:Dot(direction)) / perpendicular:Dot(perpendicular), 0, 1)
  end
  local launchSpeed = (measured - movement * inheritance):Dot(direction)
  if (perpendicular.Magnitude > 0.15 or movement.Magnitude < 0.5) and launchSpeed >= 10 and launchSpeed <= 80 then
    speed = launchSpeed
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
-- Emergency escape alone uses a safe landing surface. Combat never calls this path.
function Pearl.route(snap, position, elevated)
  local ray, origin = params(snap), units.toBlocks(snap.eye)
  local floor = workspace:Raycast(units.toWorld(position + Vector3.new(0, elevated and 12 or -0.75, 0)), units.offset(0, elevated and -48 or -24, 0), ray)
  if not floor then
    return nil
  end
  local landing = units.toBlocks(floor.Position)
  if (landing - units.toBlocks(snap.root.Position)).Magnitude < 4 then
    return nil
  end
  local direction, duration = ballistics.solve(origin, landing, speed, gravity, ray, tuning.pearlMaxFlight, drag)
  return direction and { direction = direction, duration = duration, landing = landing, origin = origin } or nil
end
local function track(snap, value)
  local position = units.toBlocks(value.root.Position)
  if not motion or motion.id ~= value.id then
    motion = { id = value.id, at = snap.now, position = position, velocity = Vector3.zero }
    return
  end
  local elapsed = snap.now - motion.at
  if elapsed < 0.05 then
    return
  end
  local velocity = (position - motion.position) * FLAT / elapsed
  if elapsed > 0.35 or velocity.Magnitude > 14 then
    motion.velocity, motion.heading, motion.ready = Vector3.zero, nil, false
  else
    local gap = (position - units.toBlocks(snap.root.Position)) * FLAT
    local stable = velocity.Magnitude > 2
      and gap.Magnitude > 0
      and velocity:Dot(gap.Unit) > 1.5
      and (not motion.heading or velocity.Unit:Dot(motion.heading) > 0.92)
    motion.velocity = stable and motion.velocity.Magnitude > 0.1 and motion.velocity:Lerp(velocity, 0.6) or velocity
    motion.ready = true
    motion.heading = velocity.Magnitude > 0.1 and velocity.Unit or nil
  end
  motion.position, motion.at = position, snap.now
end
local function actor(root, character, velocity, latency, ray)
  local position = units.toBlocks(root.Position)
  local vertical = units.toBlocks(root.AssemblyLinearVelocity.Y)
  local airborne = character:GetAttribute("VoxelGrounded") ~= true and math.abs(vertical) > 0.5
  local floor = airborne and workspace:Raycast(root.Position + units.offset(0, 0.5, 0), units.offset(0, -10, 0), ray)
  local floorY = floor and units.toBlocks(floor.Position.Y) + 1.25
  return {
    crouch = character:GetAttribute("Sneaking"),
    predict = function(time)
      local elapsed = time + latency
      local future = position + velocity * elapsed
      if airborne then
        local y = position.Y + vertical * elapsed - 16 * elapsed * elapsed
        future = Vector3.new(future.X, floorY and math.max(floorY, y) or y, future.Z)
      end
      return future
    end,
  }
end
local function plan(snap, value)
  local ray = params(snap)
  local velocity = motion and motion.id == value.id and motion.velocity or Vector3.zero
  local latency = 0
  local ok, ping = pcall(snap.player.GetNetworkPing, snap.player)
  if ok and type(ping) == "number" then
    latency = math.clamp(ping, 0, 0.15)
  end
  local predicted = actor(value.root, value.character, velocity, latency, ray)
  local others = {}
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local human = character and character:FindFirstChildOfClass("Humanoid")
    if player ~= snap.player and player ~= value.player and root and human and human.Health > 0 then
      local movement = units.toBlocks(root.AssemblyLinearVelocity) * FLAT
      if movement.Magnitude > 14 then
        movement = Vector3.zero
      end
      others[#others + 1] = actor(root, character, movement, latency, ray)
    end
  end
  local route, reason = ballistics.intercept(
    units.toBlocks(snap.eye),
    predicted,
    others,
    speed,
    gravity,
    drag,
    units.toBlocks(snap.root.AssemblyLinearVelocity) * inheritance,
    ray,
    tuning.pearlMaxFlight,
    units.toBlocks(snap.root.Position),
    value.distance <= 6,
    function(direction) return aim.canTurn(snap, direction) end
  )
  return route, reason
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
  if not shot.aimedAt or snap.now - shot.aimedAt > 0.1 then
    return
  end
  local real = native.realAim(snap)
  if real:Dot(shot.plan.direction) < math.cos(math.rad(0.75)) then
    return
  end
  shot.count, shot.requestAt = tonumber(shot.tool:GetAttribute("Count")) or 0, snap.now
  shot.requestRoot, shot.requestVelocity = snap.root.Position, units.toBlocks(snap.root.AssemblyLinearVelocity)
  shot.phase = "confirm"
  if not native.use(snap, shot.tool, shot.plan.direction) then
    shot.phase = "equip"
  elseif not shot.escape then
    shot.returnLook, shot.returnAfter = shot.originalLook, snap.now + 0.03
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
  shot = {
    phase = "equip",
    character = snap.character,
    tool = tool,
    previous = snap.tool,
    originalLook = snap.camera.CFrame.LookVector,
    escape = escaping == true,
    plan = route,
    deadline = snap.now + 1.5,
  }
  native.equip(snap, tool)
  return true
end
function Pearl.advance(snap) advance(snap) end
function Pearl.aim(snap, dt)
  if not shot then
    return false
  end
  if shot.returnLook then
    if not target.isCurrent(snap, shot.chosen) then
      shot.returnLook = nil
      return false
    end
    if snap.now >= shot.returnAfter and aim.turn(snap, shot.returnLook, dt, true) then
      shot.returnLook = nil
    end
    return true
  end
  if shot.phase ~= "equip" then
    return false
  end
  if not shot.escape and (not target.isCurrent(snap, shot.chosen) or not aim.canTurn(snap, shot.plan.direction)) then
    Pearl.cancelPrepared(snap)
    return false
  end
  if aim.turn(snap, shot.plan.direction, dt, shot.escape) then
    shot.aimedAt = snap.now
  end
  return true
end
function Pearl.prepare(snap)
  if shot and shot.character ~= snap.character then
    shot, motion = nil, nil
  end
  Pearl.observe(snap)
  local value = target.current(snap)
  if value then
    track(snap, value)
  end
  if shot and shot.phase ~= "equip" then
    return
  end
  if not utils.getConfigValue("MCAutoPearl") or not value then
    Pearl.cancelPrepared(snap)
    return
  end
  local weapon = native.weapon(snap, value) or snap.tool
  local near = target.near(snap)
  if near and geometry.direction(snap, near, weapon) then
    Pearl.cancelPrepared(snap)
    return
  end
  if shot then
    if not shot.chosen or value.id ~= shot.chosen.id then
      Pearl.cancelPrepared(snap)
      return
    end
    if not shot.planAt or snap.now - shot.planAt >= 0.05 then
      local route, reason = plan(snap, value)
      if not route then
        Pearl.cancelPrepared(snap)
        if reason == "view" then
          target.abandon(snap, value)
        end
        return
      end
      shot.plan, shot.planAt = route, snap.now
    end
    advance(snap)
    return
  end
  if snap.now < retryAt or native.blocked(snap) or geometry.aerialMace(snap, value) then
    return
  end
  if not aim.looking(snap, value) or not motion.ready then
    return
  end
  if not native.find(snap, "Pearl", true) or (tonumber(snap.player:GetAttribute("ItemCooldown_Pearl")) or 0) > workspace:GetServerTimeNow() then
    return
  end
  local route, reason = plan(snap, value)
  if not route then
    retryAt = snap.now + 0.2
    if reason == "view" then
      target.abandon(snap, value)
    end
    return
  end
  if Pearl.launch(snap, route) then
    shot.chosen = value
  end
end
Pearl.__contract = {
  provides = { "setup", "reset", "prepare", "observe", "busy", "pending", "projectile", "route", "launch", "advance", "escaping", "cancelPrepared", "aim" },
  requires = {
    Native = "mcpnative",
    Geometry = "mcpgeometry",
    Target = "mcptarget",
    Units = "mcpunits",
    Ballistics = "mcpballistics",
    Options = "mcpoptions",
    Utils = "utils",
    Aim = "mcpaim",
  },
  requiresMethods = {
    Native = { "snapshot", "find", "weapon", "restore", "equip", "use", "useState", "blocked", "realAim" },
    Geometry = { "direction", "aerialMace" },
    Target = { "current", "near", "attacked", "abandon", "isCurrent" },
    Units = { "toBlocks", "toWorld", "offset", "distance" },
    Ballistics = { "solve", "intercept" },
    Utils = { "getConfigValue" },
    Aim = { "canTurn", "turn", "looking" },
  },
  requiresData = { Options = { "tuning" } },
}
return Pearl
