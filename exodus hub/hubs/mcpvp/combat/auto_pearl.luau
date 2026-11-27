-- [[ auto pearl ]]
--!optimize 2
local Pearl = {}
local native, geometry, target, units, ballistics, tuning, utils, prediction
local shot, motion, retryAt = nil, nil, 0
local speed, gravity, drag, inheritance = 30, 12, 0.99, 0
local renderLead, measuredLatency = 1 / 60, nil
function Pearl.setup(deps)
  native, geometry, target, units, ballistics, tuning, utils, prediction =
    deps.Native, deps.Geometry, deps.Target, deps.Units, deps.Ballistics, deps.Options.tuning, deps.Utils, deps.Prediction
  return true
end
local function restore(snap)
  if not shot or shot.restored or not snap or shot.character ~= snap.character then
    return false
  end
  if not shot.requestAt then
    return true
  end
  local previous = shot.previous
  if not shot.manual and previous == shot.tool then
    previous = nil
  end
  shot.restored = native.restore(snap, previous, shot.manual)
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
function Pearl.busy() return shot ~= nil and shot.phase ~= "flight" and not shot.restored end
function Pearl.pending() return shot ~= nil end
function Pearl.escaping() return shot ~= nil and shot.phase == "flight" and shot.escape == true end
function Pearl.cancelPrepared(snap)
  if shot and shot.phase == "equip" then
    restore(snap)
    if shot.chosen then
      target.abandon(snap, shot.chosen)
    end
    shot = nil
  end
end
function Pearl.observe(snap)
  local followed = target.tracked(snap)
  if followed then
    motion = prediction.sample(followed.root, followed.character, snap.now, motion)
  else
    motion = nil
  end
  if not shot or shot.character ~= snap.character then
    return
  end
  if shot.phase == "confirm" then
    if not shot.restored and not native.blocked(snap) then
      restore(snap)
    end
    local state = native.useState(snap, shot)
    if state == nil and not shot.failed and not shot.calibrated then
      return
    end
    state = state == true or shot.calibrated == true
    if state == false then
      if shot.chosen then
        target.abandon(snap, shot.chosen)
      end
      shot.failed, shot.restoreAt, shot.phase = true, snap.now, "restore"
    else
      shot.failed, shot.restoreAt, shot.phase = false, snap.now, "restore"
      shot.untilAt = math.max(snap.now + 0.2, shot.requestAt + shot.plan.duration + 0.7)
      if shot.chosen then
        target.pursuing(snap, shot.untilAt, shot.chosen)
      end
    end
  end
  if shot.phase == "restore" and not native.blocked(snap) then
    if restore(snap) or snap.now - shot.restoreAt >= 1 then
      if shot.failed or shot.manual then
        local delay = shot.failed and 1 or 0.15
        shot, retryAt = nil, snap.now + delay
      else
        shot.phase = "flight"
      end
      return true
    end
  elseif shot.phase == "flight" then
    local moved = units.distance(snap.root.Position, shot.requestRoot) >= 2
    local arrived = moved and units.distance(snap.root.Position, units.toWorld(shot.plan.landing)) < 3
    if arrived or snap.now >= shot.untilAt then
      if shot.chosen then
        target.arrived(snap, shot.chosen)
      end
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
  local elapsed = os.clock() - shot.requestAt
  if elapsed > 0 and elapsed < 1 then
    measuredLatency = elapsed
  end
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
local function launchFloor(snap, ray)
  local feet = units.toBlocks(snap.root.Position) - Vector3.new(0, 1.25, 0)
  local heights = {}
  for _, offset in ipairs({ Vector3.new(2.5, 0, 0), Vector3.new(-2.5, 0, 0), Vector3.new(0, 0, 2.5), Vector3.new(0, 0, -2.5) }) do
    local point = feet + offset + Vector3.new(0, tuning.pearlExitHeightBlocks, 0)
    local hit = workspace:Raycast(units.toWorld(point), units.offset(0, -tuning.pearlExitHeightBlocks - 2, 0), ray)
    if hit and hit.Normal.Y >= 0.65 and hit.Material ~= Enum.Material.Water then
      heights[#heights + 1] = units.toBlocks(hit.Position.Y)
    end
  end
  if #heights < 3 then
    return feet.Y
  end
  table.sort(heights)
  return math.max(feet.Y, heights[math.ceil(#heights / 2)])
end
local function nearGround(snap, value, ray)
  local height = units.toBlocks(value.root.Position.Y) - 1.25
  local localFloor = units.toBlocks(snap.root.Position.Y) - 1.25
  if height - localFloor > tuning.pearlTargetHeightBlocks and height - launchFloor(snap, ray) > tuning.pearlTargetHeightBlocks then
    return false
  end
  local feet = value.root.Position - units.offset(0, 1.25, 0)
  local hit = workspace:Raycast(feet + units.offset(0, 1 / 32, 0), units.offset(0, -tuning.pearlTargetHeightBlocks - 1 / 32, 0), ray)
  return hit ~= nil
    and hit.Normal.Y >= 0.65
    and hit.Material ~= Enum.Material.Water
    and hit.Instance:GetAttribute("BlockKey") ~= "lava"
    and hit.Instance:GetAttribute("BlockKey") ~= "water"
end
local function plan(snap, value)
  local ray = params(snap)
  if not nearGround(snap, value, ray) then
    return nil, "height"
  end
  local roundTrip = measuredLatency
  local ok, ping = pcall(snap.player.GetNetworkPing, snap.player)
  if ok and type(ping) == "number" and ping > 0 then
    roundTrip = math.clamp(ping * 2, 0, 1)
  elseif not roundTrip then
    local readable, value = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if readable and type(value) == "number" then
      roundTrip = math.clamp(value / 1000, 0, 1)
    end
  end
  local latency = renderLead + (roundTrip or 0)
  local predicted = prediction.actor(value.root, value.character, motion, latency, ray, true)
  local actual, origin = units.toBlocks(value.root.Position), units.toBlocks(snap.eye)
  local predict = predicted.predict
  local leadLimit = math.max(2, math.min(8, value.distance * 0.5))
  predicted.predict = function(time)
    local point = predict(time)
    local offset = (point - actual) * Vector3.new(1, 0, 1)
    if offset.Magnitude > leadLimit then
      point = actual + offset.Unit * leadLimit + Vector3.new(0, point.Y - actual.Y, 0)
    end
    local toward, forecast = (actual - origin) * Vector3.new(1, 0, 1), (point - origin) * Vector3.new(1, 0, 1)
    if toward:Dot(forecast) <= 0 then
      return actual
    end
    return point
  end
  local others = {}
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local human = character and character:FindFirstChildOfClass("Humanoid")
    if player ~= snap.player and player ~= value.player and root and human and human.Health > 0 then
      others[#others + 1] = prediction.actor(root, character, nil, latency, ray, false)
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
    tuning.pearlLandingRadiusBlocks
  )
  if route then
    local toward = (actual - origin) * Vector3.new(1, 0, 1)
    local launch = route.direction * Vector3.new(1, 0, 1)
    if toward.Magnitude > 0.1 and toward:Dot(launch) <= 0 then
      return nil, "direction"
    end
  end
  return route, reason
end
local function rangeAllows(snap)
  if not shot or not shot.chosen then
    return true
  end
  local current = target.current(snap)
  if not current or not target.isCurrent(snap, shot.chosen) then
    return false
  end
  shot.chosen = current
  local weapon = native.weapon(snap, current) or shot.previous
  return current.distance > (geometry.stats(weapon).reach or 3) + tuning.pearlAttackMarginBlocks
end
local function advance(snap)
  if not shot or shot.phase ~= "equip" then
    return
  end
  if shot.chosen and not utils.getConfigValue("MCAutoPearl") or not rangeAllows(snap) then
    Pearl.cancelPrepared(snap)
    return
  end
  if snap.now > shot.deadline then
    Pearl.cancelPrepared(snap)
    retryAt = snap.now + 0.2
    return
  end
  shot.count, shot.requestAt = tonumber(shot.tool:GetAttribute("Count")) or 0, snap.now
  shot.requestRoot, shot.requestVelocity = snap.root.Position, units.toBlocks(snap.root.AssemblyLinearVelocity)
  shot.phase = "confirm"
  shot.failed = not native.use(snap, shot.tool, shot.plan.direction)
  if shot.failed then
    if shot.chosen then
      target.abandon(snap, shot.chosen)
    end
    shot.phase, shot.restoreAt = "restore", snap.now
  elseif shot.chosen then
    target.pursuing(snap, snap.now + shot.plan.duration + 0.7, shot.chosen)
  end
  if not native.blocked(snap) then
    restore(snap)
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
    escape = escaping == true,
    plan = route,
    deadline = snap.now + 1.5,
  }
  return true
end
function Pearl.throw(snap)
  Pearl.cancelPrepared(snap)
  if shot and shot.phase == "flight" then
    shot = nil
  end
  local route = { direction = snap.camera.CFrame.LookVector, origin = units.toBlocks(snap.eye), duration = 0 }
  if not Pearl.launch(snap, route) then
    return false, "Pearl indisponível ou em uso."
  end
  shot.manual = true
  advance(snap)
  if not shot or shot.failed then
    return false, "O uso nativo da Pearl foi recusado."
  end
  return true
end
function Pearl.advance(snap) advance(snap) end
function Pearl.render(dt) renderLead = math.clamp(dt or 1 / 60, 0, 0.05) end
function Pearl.prepare(snap, available)
  if shot and shot.character ~= snap.character then
    shot, motion = nil, nil
  end
  Pearl.observe(snap)
  local value = target.escape(snap)
  if not value then
    if shot and shot.manual then
      advance(snap)
    end
    return
  end
  if not utils.getConfigValue("MCAutoPearl") or shot or available == false or native.blocked(snap) or snap.now < retryAt then
    target.abandon(snap, value)
    return
  end
  if not native.find(snap, "Pearl", true) or (tonumber(snap.player:GetAttribute("ItemCooldown_Pearl")) or 0) > workspace:GetServerTimeNow() then
    target.abandon(snap, value)
    return
  end
  local route = plan(snap, value)
  if not route or not Pearl.launch(snap, route) then
    target.abandon(snap, value)
    return
  end
  shot.chosen = value
  advance(snap)
end
Pearl.__contract = {
  provides = {
    "setup",
    "reset",
    "prepare",
    "observe",
    "busy",
    "pending",
    "projectile",
    "route",
    "launch",
    "advance",
    "escaping",
    "cancelPrepared",
    "render",
    "throw",
  },
  requires = {
    Native = "mcpnative",
    Geometry = "mcpgeometry",
    Target = "mcptarget",
    Units = "mcpunits",
    Ballistics = "mcpballistics",
    Options = "mcpoptions",
    Utils = "utils",
    Prediction = "mcpmotion",
  },
  requiresMethods = {
    Native = { "snapshot", "find", "weapon", "restore", "use", "useState", "blocked" },
    Geometry = { "stats", "inView" },
    Target = { "current", "tracked", "isCurrent", "pursuing", "escape", "abandon", "arrived" },
    Units = { "toBlocks", "toWorld", "offset", "distance" },
    Ballistics = { "solve", "intercept" },
    Utils = { "getConfigValue" },
    Prediction = { "sample", "actor" },
  },
  requiresData = { Options = { "tuning" } },
}
return Pearl
