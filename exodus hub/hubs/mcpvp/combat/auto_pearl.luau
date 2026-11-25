-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics
local shot, retryAt = nil, 0
local speed, gravity, drag = 96, 38.4, 0.99
function Pearl.setup(deps)
  native, target, ballistics = deps.Native, deps.Target, deps.Ballistics
  return true
end
local function restore(snap)
  if shot and snap and snap.character == shot.character and (snap.tool == shot.tool or not snap.tool) then
    local tool = shot.previous
    if not tool or not tool.Parent then
      tool = native.findSword(snap)
    end
    if tool then
      native.equip(snap, tool)
    end
  end
end
function Pearl.reset()
  if shot then
    target.release(shot.target)
    restore(native.snapshot())
  end
  shot = nil
end
function Pearl.busy() return shot ~= nil and shot.phase ~= "flight" end
function Pearl.observeProjectile(action, _id, kind, _position, velocity, acceleration, resistance)
  if action ~= "Projectile" or kind ~= "Pearl" or typeof(velocity) ~= "Vector3" then
    return
  end
  if velocity.Magnitude > 0 and velocity.Magnitude < 1000 then
    speed = velocity.Magnitude
  end
  if type(acceleration) == "number" and acceleration > 0 and acceleration < 1000 then
    gravity = acceleration
  end
  if type(resistance) == "number" and resistance > 0 and resistance <= 1 then
    drag = resistance
  end
end
local function plan(snap, chosen)
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
  local motion = chosen.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
  if motion.Magnitude > 45 then
    motion = motion.Unit * 45
  end
  local flight = math.clamp((chosen.root.Position - snap.eye).Magnitude / speed, 0.1, 5)
  for _ = 1, 5 do
    local prediction = chosen.root.Position + motion * flight
    local floor = workspace:Raycast(prediction + Vector3.new(0, 2, 0), Vector3.new(0, -64, 0), params)
    if not floor then
      break
    end
    local direction, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 6, drag)
    if not direction then
      break
    end
    if math.abs(duration - flight) * motion.Magnitude < 0.75 then
      return direction, duration
    end
    flight = (flight + duration) * 0.5
  end
  -- A bounded intermediate landing must make progress toward the opponent.
  local delta = (chosen.root.Position - snap.root.Position) * Vector3.new(1, 0, 1)
  if delta.Magnitude < 8 then
    return nil
  end
  for _, fraction in ipairs({ 0.8, 0.6, 0.4 }) do
    local point = snap.root.Position + delta * fraction
    local floor = workspace:Raycast(point + Vector3.new(0, 16, 0), Vector3.new(0, -64, 0), params)
    if floor and (floor.Position - chosen.root.Position).Magnitude + 8 < (snap.root.Position - chosen.root.Position).Magnitude then
      local direction, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 6, drag)
      if direction then
        return direction, duration
      end
    end
  end
  return nil
end
function Pearl.step(snap, chosen)
  if shot and shot.character ~= snap.character then
    Pearl.reset()
  end
  if shot then
    if shot.phase == "equip" then
      if snap.now > shot.deadline or not chosen or chosen.character ~= shot.target then
        Pearl.reset()
        return false
      end
      if snap.tool ~= shot.tool then
        return false
      end
      if native.blocked(snap) then
        return false
      end
      -- Re-plan from the actual post-equip eye position, immediately before dispatch.
      local direction, duration = plan(snap, chosen)
      if not direction then
        Pearl.reset()
        return false
      end
      shot.count = tonumber(shot.tool:GetAttribute("Count")) or 1
      shot.phase, shot.deadline, shot.arrival = "confirm", snap.now + 1, snap.now + duration + 0.5
      target.hold(chosen.character, shot.arrival)
      if not native.usePearl(snap, shot.tool, direction) then
        Pearl.reset()
        return false
      end
      return true
    end
    if shot.phase == "confirm" then
      local consumed = not shot.tool.Parent or (tonumber(shot.tool:GetAttribute("Count")) or shot.count) < shot.count
      if not consumed and native.pearlReady() then
        if snap.now > shot.deadline then
          Pearl.reset()
          retryAt = snap.now + native.pearlCooldown()
        end
        return false
      end
      restore(snap)
      shot.phase = "flight"
    end
    if snap.character:GetAttribute("PearlTeleportAt") == shot.teleportAt and snap.now < shot.arrival then
      return false
    end
    Pearl.reset()
    retryAt = snap.now + 0.2
    return false
  end
  if not chosen or snap.now < retryAt or native.blocked(snap) or not native.pearlReady() or native.canHit(snap, chosen) or native.aerialMace(snap, chosen) then
    return false
  end
  retryAt = snap.now + 0.3
  local tool = native.findPearl(snap)
  if not tool then
    return false
  end
  local direction = plan(snap, chosen)
  if not direction then
    return false
  end
  shot = {
    character = snap.character,
    target = chosen.character,
    previous = snap.tool,
    tool = tool,
    phase = "equip",
    deadline = snap.now + 0.75,
    teleportAt = snap.character:GetAttribute("PearlTeleportAt"),
  }
  if not native.equip(snap, tool) then
    Pearl.reset()
    return false
  end
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step", "observeProjectile" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics" },
  requiresMethods = {
    Native = { "snapshot", "findSword", "equip", "findPearl", "usePearl", "pearlReady", "pearlCooldown", "blocked", "canHit", "aerialMace" },
    Target = { "hold", "release" },
    Ballistics = { "solve" },
  },
}
return Pearl
