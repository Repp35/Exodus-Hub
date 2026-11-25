-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics, utils
local shot, retryAt, sample = nil, 0, nil
local speed, gravity, drag = 96, 38.4, 0.99
local function restore(snap)
  if not shot or shot.restored or shot.character ~= snap.character then
    return
  end
  if snap.tool == shot.tool or snap.tool == nil then
    local previous = shot.previousTool
    if previous and previous.Parent then
      native.equip(snap, previous)
    elseif utils.getConfigValue("MCAutoSword") then
      local tool = native.findWeapon(snap)
      if tool then
        native.equip(snap, tool)
      end
    end
  end
  shot.restored = true
end
function Pearl.setup(deps)
  native, target, ballistics, utils = deps.Native, deps.Target, deps.Ballistics, deps.Utils
  return true
end
function Pearl.reset()
  if shot and shot.sentAt and not shot.launched then
    local snap = native.snapshot()
    local human = shot.character:FindFirstChildOfClass("Humanoid")
    if human and human.Health > 0 and (not snap or snap.character == shot.character) then
      shot.cancelAfterConfirm = true
      return
    end
  end
  if shot then
    local snap = native.snapshot()
    if snap then
      restore(snap)
    end
    if shot.sentAt then
      retryAt = math.max(retryAt, shot.sentAt + shot.flight + 1)
    end
  end
  shot = nil
end
function Pearl.busy() return shot ~= nil and shot.phase ~= "flight" end
function Pearl.observeProjectile(action, id, kind, position, velocity, acceleration, resistance)
  if action == "ProjectileEnd" then
    if shot and shot.id ~= nil and shot.id == id then
      shot.endedAt = os.clock()
    end
    return
  end
  if action ~= "Projectile" or kind ~= "Pearl" or typeof(velocity) ~= "Vector3" then
    return
  end
  if velocity.Magnitude >= 20 and velocity.Magnitude <= 200 then
    speed = velocity.Magnitude
  end
  if type(acceleration) == "number" and acceleration > 0 and acceleration < 1000 then
    gravity = acceleration
  end
  if type(resistance) == "number" and resistance > 0 and resistance <= 1 then
    drag = resistance
  end
  if
    shot
    and shot.sentAt
    and os.clock() - shot.sentAt < 1.5
    and typeof(position) == "Vector3"
    and (position - shot.origin).Magnitude <= 10
    and velocity.Magnitude > 0
    and velocity.Unit:Dot(shot.direction) > 0.98
  then
    shot.id = id
  end
end
local function visible(snap, chosen)
  if not chosen or not chosen.root.Parent or chosen.humanoid.Health <= 0
    or chosen.character:GetAttribute("Invisible") == true then return false end
  local point = chosen.root.Position - Vector3.new(0, 0.35, 0)
  local projected, onScreen = snap.camera:WorldToViewportPoint(point)
  if not onScreen or projected.Z <= 0 or not native.visible(snap, point, chosen.character) then return false end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
  params.FilterDescendantsInstances = { snap.character, snap.camera }
  local delta = point - snap.camera.CFrame.Position
  local hit = workspace:Raycast(snap.camera.CFrame.Position, delta, params)
  return not hit or hit.Instance:IsDescendantOf(chosen.character)
end
function Pearl.observe(snap)
  local chosen = target.locked()
  if not chosen or not chosen.root.Parent then sample = nil return end
  local position, velocity = chosen.root.Position, chosen.root.AssemblyLinearVelocity
  local epoch = chosen.character:GetAttribute("PearlTeleportAt")
  if not sample or sample.character ~= chosen.character or sample.epoch ~= epoch or snap.now - sample.at > 0.25 then
    sample = { character = chosen.character, epoch = epoch, position = position, velocity = velocity,
      at = snap.now, stableAt = snap.now, measuredAt = snap.now, measuredPosition = position, disagreement = 0, acceleration = 0 }
    return
  end
  local elapsed = snap.now - sample.at
  if elapsed < 1 / 120 then return end
  local acceleration = (velocity - sample.velocity).Magnitude / elapsed
  local displacement = (position - sample.position).Magnitude
  if acceleration > 12 or displacement > math.max(8, velocity.Magnitude * elapsed * 2) then sample.stableAt = snap.now end
  sample.acceleration = acceleration
  if snap.now - sample.measuredAt >= 0.1 then
    local measured = (position - sample.measuredPosition) / (snap.now - sample.measuredAt)
    sample.disagreement = (measured - velocity).Magnitude
    sample.measuredAt, sample.measuredPosition = snap.now, position
    if sample.disagreement > 4 then sample.stableAt = snap.now end
  end
  sample.position, sample.velocity, sample.at = position, velocity, snap.now
end
local function plan(snap, chosen)
  if not visible(snap, chosen) or not sample or sample.character ~= chosen.character
    or snap.now - sample.at > 0.08 or snap.now - sample.stableAt < 0.15 then return nil end
  local grounded = chosen.character:GetAttribute("VoxelGrounded")
  if grounded == false or grounded == nil and chosen.humanoid.FloorMaterial == Enum.Material.Air
    or math.abs(sample.velocity.Y) > 1 then return nil end
  local motion = sample.velocity * Vector3.new(1, 0, 1)
  if motion.Magnitude > 60 then return nil end
  local latency = 0
  local ok, ping = pcall(snap.player.GetNetworkPing, snap.player)
  if not ok or type(ping) ~= "number" or ping ~= ping or ping < 0 or ping > 0.2 then return nil end
  latency = ping
  local params, ignored = RaycastParams.new(), { snap.camera }
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player.Character then ignored[#ignored + 1] = player.Character end
  end
  for _, name in ipairs({ "LocalItemVisuals", "LocalBowVisuals", "PredictedBlocks", "ArenaPvPBots" }) do
    local folder = workspace:FindFirstChild(name)
    if folder then ignored[#ignored + 1] = folder end
  end
  params.FilterType, params.RespectCanCollide, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  local sneak = chosen.character:GetAttribute("Sneaking") == true and 0.96 or 0
  local flight = (chosen.root.Position - snap.eye).Magnitude / speed
  local direction, duration, destination, converged
  for _ = 1, 10 do
    destination = chosen.root.Position + motion * (latency + flight) - Vector3.new(0, 0.35 + sneak, 0)
    direction, duration = ballistics.solve(snap.eye, destination, speed, gravity, params, 1.25, drag, true)
    if not direction then return nil end
    if math.abs(duration - flight) * math.max(1, motion.Magnitude) <= 0.025 then converged = true break end
    flight = duration
  end
  if not converged then return nil end
  local horizon = latency + duration
  local uncertainty = 0.08 + sample.disagreement * horizon + 0.5 * sample.acceleration * horizon * horizon
  if uncertainty >= 0.5 then return nil end
  local futureRoot = chosen.root.Position + motion * horizon
  if workspace:Raycast(chosen.root.Position, futureRoot - chosen.root.Position, params) then return nil end
  local floor = workspace:Raycast(futureRoot, Vector3.new(0, -8, 0), params)
  if not floor or floor.Material == Enum.Material.Water then return nil end
  local block = floor.Instance:GetAttribute("BlockKey")
  if block == "lava" or block == "water" then return nil end
  local collision = ballistics.intersects(snap.eye, direction, speed, gravity, drag, duration,
    chosen.root.Position, motion, latency, uncertainty, sneak, params)
  if not collision then return nil end
  return direction, collision, destination
end
function Pearl.aim(snap, dt)
  if not shot or shot.phase ~= "equip" or not shot.direction or not visible(snap, shot.target) then return end
  if snap.now - (shot.validAt or 0) > 0.08 then return end
  local camera, direction = snap.camera, shot.direction
  local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
  local angle = math.acos(math.clamp(look:Dot(direction), -1, 1))
  if angle > 0.00001 then
    local alpha = math.min(1, math.rad(540) * math.clamp(dt or 1 / 60, 0, 1 / 30) / angle)
    camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, eye + direction), alpha)
  end
end

function Pearl.step(snap, chosen)
  if not utils.getConfigValue("MCAutoPearl") then
    if shot and shot.sentAt then shot.cancelAfterConfirm = true
    else Pearl.reset() return false end
  end
  if shot and shot.character ~= snap.character then
    Pearl.reset()
  end
  if shot then
    if shot.phase == "equip" then
      if snap.now >= shot.deadline then Pearl.reset() retryAt = snap.now + 0.25 return false end
      local focused = target.get(snap)
      if not focused or focused.character ~= shot.target.character then Pearl.reset() return false end
      if
        focused.player:GetAttribute("ArenaProtected") == true
        or focused.player:GetAttribute("InArena") == false
        or focused.player:GetAttribute("DuelCombatActive") == false
        or focused.character:GetAttribute("ArenaProtected") == true
        or focused.character:GetAttribute("DuelCombatActive") == false
      then
        Pearl.reset()
        return false
      end
      if not focused.character.Parent or focused.humanoid.Health <= 0 then
        Pearl.reset()
        return false
      end
      if snap.tool ~= shot.tool or native.blocked(snap) then shot.heldAt = nil return false end
      shot.heldAt = shot.heldAt or snap.now
      if snap.now - shot.heldAt < 0.05 then return false end
      if snap.now < (shot.planAt or 0) then
        return false
      end
      shot.planAt = snap.now
      local direction, duration = plan(snap, focused)
      if not direction then shot.aimedAt, shot.validAt = nil, nil return false end
      shot.direction, shot.flight, shot.origin, shot.validAt = direction, duration, snap.eye, snap.now
      local alignment = snap.camera.CFrame.LookVector:Dot(direction)
      if alignment < math.cos(math.rad(0.5)) then shot.aimedAt = nil return false end
      shot.aimedAt = shot.aimedAt or snap.now
      if snap.now - shot.aimedAt < 1 / 60 or not visible(snap, focused) then return false end
      shot.count = tonumber(shot.tool:GetAttribute("Count")) or 1
      shot.cooldown = snap.player:GetAttribute("ItemCooldown_Pearl")
      shot.sentAt, shot.phase = snap.now, "confirm"
      shot.arrivalAt = snap.now + duration + 0.4
      if not native.usePearl(snap, shot.tool, direction) then
        -- A locally refused use was never sent. Do not leave it stuck in confirmation.
        shot.sentAt = nil
        Pearl.reset()
        retryAt = snap.now + 0.15
        return false
      end
      return true
    end
    if shot.phase == "confirm" then
      local consumed = not shot.tool.Parent or (tonumber(shot.tool:GetAttribute("Count")) or shot.count) < shot.count
      local cooldown = snap.player:GetAttribute("ItemCooldown_Pearl")
      local acknowledged = type(cooldown) == "number" and cooldown ~= shot.cooldown and not native.pearlReady()
      local arrived = snap.character:GetAttribute("PearlTeleportAt") ~= shot.teleportAt
      local projectile = shot.id ~= nil
      local launched = consumed and (projectile or arrived or acknowledged and snap.now - shot.sentAt >= 0.1)
      if not launched then
        if snap.now - shot.sentAt > 5 and not shot.reported then
          shot.reported = true
          utils.recordError("mcpvp.pearl", "Lançamento pendente sem confirmação de consumo/cooldown; reenvio bloqueado.")
        end
        return false
      end
      shot.phase, shot.launched = "flight", true
      restore(snap)
      if shot.cancelAfterConfirm then shot = nil return false end
    end
    local teleported = snap.character:GetAttribute("PearlTeleportAt") ~= shot.teleportAt
    local ended = shot.endedAt ~= nil
    if not teleported and not ended and snap.now < shot.arrivalAt then
      return false
    end
    restore(snap)
    shot = nil
    retryAt = snap.now
  end
  if not chosen or not chosen.character.Parent or chosen.humanoid.Health <= 0 then
    return false
  end
  if snap.now < retryAt or native.blocked(snap) or not native.pearlReady() or native.canHit(snap, chosen) then
    return false
  end
  retryAt = snap.now
  local tool = native.findPearl(snap)
  if not tool then
    return false
  end
  local direction, duration = plan(snap, chosen)
  if not direction then
    return false
  end
  shot = {
    character = snap.character,
    tool = tool,
    target = chosen,
    previousTool = snap.tool,
    phase = "equip",
    deadline = snap.now + 1.5,
    validAt = snap.now,
    direction = direction,
    flight = duration,
    teleportAt = snap.character:GetAttribute("PearlTeleportAt"),
  }
  target.hold(chosen.character, snap.now + duration + 1)
  if not native.equip(snap, tool) then
    Pearl.reset()
    return false
  end
  local fresh = native.snapshot()
  if fresh and fresh.tool == tool then return Pearl.step(fresh, chosen) end
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step", "observeProjectile", "observe", "aim" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Utils = "utils" },
  requiresMethods = {
    Native = { "snapshot", "findWeapon", "stats", "equip", "findPearl", "usePearl", "pearlReady", "blocked", "canHit", "visible" },
    Target = { "hold", "get", "locked" },
    Ballistics = { "solve", "intersects" },
    Utils = { "getConfigValue", "recordError" },
  },
}
return Pearl
