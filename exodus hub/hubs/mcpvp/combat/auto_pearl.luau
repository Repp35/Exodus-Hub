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
  local flight = math.clamp(gap.Magnitude / speed, 0.15, 4)
  local best, bestFlight, bestScore, bestPoint
  local function try(point)
    local floor = workspace:Raycast(point + Vector3.new(0, 12.8, 0), Vector3.new(0, -160, 0), params)
    if not floor or floor.Normal.Y < 0.6 or floor.Material == Enum.Material.Water then
      return
    end
    local block = floor.Instance:GetAttribute("BlockKey")
    if block == "lava" or block == "water" then
      return
    end
    local aim, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 4.5, drag)
    if not aim then
      return
    end
    local future = chosen.root.Position + motion * math.min(duration + 0.08, 2.5)
    local error = ((future - floor.Position) * Vector3.new(1, 0, 1)).Magnitude
    local withoutPearl = ((future - snap.root.Position) * Vector3.new(1, 0, 1)).Magnitude
    local gain = withoutPearl - error
    -- A useful partial interception is valid too; exact convergence is never required.
    if gain < math.min(3.2, gap.Magnitude * 0.2) then
      return
    end
    local score = error + duration * 3
    if not bestScore or score < bestScore then
      best, bestFlight, bestScore, bestPoint = aim, duration, score, floor.Position
    end
    return duration
  end
  for _ = 1, 3 do
    local future = chosen.root.Position + motion * math.min(flight + 0.08, 2.5)
    local approach = (future - snap.root.Position) * Vector3.new(1, 0, 1)
    if approach.Magnitude > 0.01 then
      local duration = try(future - approach.Unit * math.min(2, reach * 0.2))
      if duration then
        flight = duration
      else
        break
      end
    end
  end
  if not best then
    -- Far teleports and obstacles use successive safe landings towards the same opponent.
    local side = Vector3.new(-gap.Unit.Z, 0, gap.Unit.X)
    for _, distance in ipairs({ 128, 96, 64, 32 }) do
      if gap.Magnitude < distance then
        continue
      end
      for _, offset in ipairs({ 0, 3.2, -3.2 }) do
        try(snap.root.Position + gap.Unit * distance + side * offset)
      end
      if best then
        break
      end
    end
  end
  return best, bestFlight, bestPoint
end
function Pearl.step(snap, chosen)
  if not utils.getConfigValue("MCAutoPearl") then
    Pearl.reset()
    return false
  end
  if shot and shot.character ~= snap.character then
    Pearl.reset()
  end
  if shot then
    if shot.phase == "equip" then
      local focused = shot.target
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
      if snap.tool ~= shot.tool or native.blocked(snap) then
        return false
      end
      if snap.now < (shot.planAt or 0) then
        return false
      end
      shot.planAt = snap.now + 0.15
      local direction, duration = plan(snap, focused)
      if not direction then
        return false
      end
      shot.direction, shot.flight, shot.origin = direction, duration, snap.eye
      shot.count = tonumber(shot.tool:GetAttribute("Count")) or 1
      shot.cooldown = snap.player:GetAttribute("ItemCooldown_Pearl")
      shot.sentAt, shot.phase = snap.now, "confirm"
      if not native.usePearl(snap, shot.tool, direction) then
        Pearl.reset()
        retryAt = snap.now + 0.4
        return false
      end
      return true
    end
    if shot.phase == "confirm" then
      local consumed = not shot.tool.Parent or (tonumber(shot.tool:GetAttribute("Count")) or shot.count) < shot.count
      local cooldown = snap.player:GetAttribute("ItemCooldown_Pearl")
      local acknowledged = type(cooldown) == "number" and cooldown ~= shot.cooldown and not native.pearlReady()
      if not consumed and not acknowledged then
        if snap.now - shot.sentAt > 5 and not shot.reported then
          shot.reported = true
          utils.recordError("mcpvp.pearl", "Lançamento pendente sem confirmação de consumo/cooldown; reenvio bloqueado.")
        end
        return false
      end
      shot.phase = "flight"
      restore(snap)
    end
    local teleported = snap.character:GetAttribute("PearlTeleportAt") ~= shot.teleportAt
    local ended = shot.endedAt and snap.now >= shot.sentAt + shot.flight + 0.25
    if not teleported and not ended then
      return false
    end
    restore(snap)
    shot = nil
    retryAt = snap.now + 0.08
  end
  if not chosen or not chosen.character.Parent or chosen.humanoid.Health <= 0 then
    return false
  end
  if snap.now < retryAt or native.blocked(snap) or not native.pearlReady() or native.canHit(snap, chosen) then
    return false
  end
  local distance = (chosen.root.Position - snap.root.Position).Magnitude
  local reach = native.stats(native.findWeapon(snap)).reach or 9.6
  if distance < reach + 1.2 then
    return false
  end
  retryAt = snap.now + 0.15
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
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step", "observeProjectile" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Utils = "utils" },
  requiresMethods = {
    Native = { "snapshot", "findWeapon", "stats", "equip", "findPearl", "usePearl", "pearlReady", "blocked", "canHit" },
    Target = { "hold" },
    Ballistics = { "solve" },
    Utils = { "getConfigValue", "recordError" },
  },
}
return Pearl
