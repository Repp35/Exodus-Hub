-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics, utils
local shot, retryAt = nil, 0
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
local function plan(snap, chosen)
  local params, ignored = RaycastParams.new(), { snap.camera }
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
  params.FilterType, params.RespectCanCollide, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  local motion = chosen.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
  if motion.Magnitude > 90 then
    motion = motion.Unit * 90
  end
  local gap = (chosen.root.Position - snap.root.Position) * Vector3.new(1, 0, 1)
  if gap.Magnitude < 0.01 then
    return nil
  end
  local reach = native.stats(native.findWeapon(snap)).reach or 9.6
  if gap.Magnitude <= math.max(48, reach * 4) then
    -- Nearby opponents are intercepted at body height; do not redirect the pearl to a floor.
    local flight = gap.Magnitude / speed
    local best, duration, destination
    for _ = 1, 3 do
      destination = chosen.root.Position + motion * (flight + 0.02)
      local aim, time = ballistics.solve(snap.eye, destination, speed, gravity, params, 1.25, drag, true)
      if not aim then break end
      best, duration, flight = aim, time, time
    end
    return best, duration, destination
  end
  -- Original interception flow: refine flight time, then use a nearer landing if needed.
  local flight, best, bestFlight = 0.3, nil, nil
  for _ = 1, 8 do
    local point = chosen.root.Position + motion * flight
    local floor = workspace:Raycast(point + Vector3.new(0, 0.5, 0), Vector3.new(0, -128, 0), params)
    if not floor then break end
    local aim, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 6, drag)
    if not aim then break end
    best, bestFlight = aim, duration
    if math.abs(duration - flight) * math.max(1, motion.Magnitude) < 0.5 then return aim, duration end
    flight = duration
  end
  if best then return best, bestFlight end
  local delta = chosen.root.Position - snap.root.Position
  for _, distance in ipairs({ 160, 128, 96, 64, 32 }) do
    if delta.Magnitude <= distance then continue end
    local point = snap.root.Position + delta.Unit * distance
    local floor = workspace:Raycast(point + Vector3.new(0, 32, 0), Vector3.new(0, -256, 0), params)
    if floor and (floor.Position - chosen.root.Position).Magnitude + 8 < delta.Magnitude then
      local aim, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 6, drag)
      if aim then return aim, duration end
    end
  end
  return nil
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
      if not direction then
        return false
      end
      shot.direction, shot.flight, shot.origin = direction, duration, snap.eye
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
  provides = { "setup", "reset", "busy", "step", "observeProjectile" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Utils = "utils" },
  requiresMethods = {
    Native = { "snapshot", "findWeapon", "stats", "equip", "findPearl", "usePearl", "pearlReady", "blocked", "canHit" },
    Target = { "hold", "get" },
    Ballistics = { "solve" },
    Utils = { "getConfigValue", "recordError" },
  },
}
return Pearl
