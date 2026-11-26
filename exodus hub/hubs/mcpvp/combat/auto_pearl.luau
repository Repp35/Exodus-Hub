-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, ballistics, tuning, units
local shot, retryAt = nil, 0
local speed, gravity, drag = 30, 12, 0.99
function Pearl.setup(deps)
  native, ballistics, tuning, units = deps.Native, deps.Ballistics, deps.Options.tuning, deps.Units
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
    restore(native.snapshot())
  end
  shot = nil
end
function Pearl.busy() return shot ~= nil and shot.phase ~= "flight" end
function Pearl.observeProjectile(action, _id, kind, _position, velocity, acceleration, resistance)
  if action ~= "Projectile" or kind ~= "Pearl" or typeof(velocity) ~= "Vector3" then
    return
  end
  if units.toBlocks(velocity.Magnitude) > 0 and units.toBlocks(velocity.Magnitude) < 312.5 then
    speed = units.toBlocks(velocity.Magnitude)
  end
  if type(acceleration) == "number" and acceleration > 0 and units.toBlocks(acceleration) < 312.5 then
    gravity = units.toBlocks(acceleration)
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
  local playerPosition, targetPosition, eye = units.toBlocks(snap.root.Position), units.toBlocks(chosen.root.Position), units.toBlocks(snap.eye)
  local motion = units.toBlocks(chosen.root.AssemblyLinearVelocity) * Vector3.new(1, 0, 1)
  if motion.Magnitude > 14.0625 then
    motion = motion.Unit * 14.0625
  end
  local flight = math.clamp((targetPosition - eye).Magnitude / speed, 0.1, 5)
  for _ = 1, 5 do
    local prediction = targetPosition + motion * flight
    if (prediction - playerPosition).Magnitude > tuning.focusRangeBlocks then
      return nil
    end
    local floor = workspace:Raycast(units.toWorld(prediction + Vector3.new(0, 0.625, 0)), units.offset(0, -20, 0), params)
    if not floor or units.distance(floor.Position, snap.root.Position) > tuning.focusRangeBlocks then
      break
    end
    local direction, duration = ballistics.solve(eye, units.toBlocks(floor.Position), speed, gravity, params, 0.75, drag)
    if not direction then
      break
    end
    if math.abs(duration - flight) * motion.Magnitude < 15 / 64 then
      return direction, duration
    end
    flight = (flight + duration) * 0.5
  end

  return nil
end
function Pearl.step(snap, chosen)
  if
    shot
    and (
      shot.character ~= snap.character
      or not chosen
      or chosen.character ~= shot.target
      or units.distance(chosen.root.Position, snap.root.Position) > tuning.focusRangeBlocks
    )
  then
    Pearl.reset()
    retryAt = snap.now + 0.3
    return false
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
  if
    not chosen
    or units.distance(chosen.root.Position, snap.root.Position) > tuning.focusRangeBlocks
    or snap.now < retryAt
    or native.blocked(snap)
    or not native.pearlReady()
    or native.canHit(snap, chosen)
    or native.aerialMace(snap, chosen)
  then
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
  requires = { Native = "mcpnative", Options = "mcpoptions", Ballistics = "mcpballistics", Units = "mcpunits" },
  requiresData = { Options = { "tuning" } },
  requiresMethods = {
    Units = { "toBlocks", "toWorld", "offset", "distance" },
    Native = { "snapshot", "findSword", "equip", "findPearl", "usePearl", "pearlReady", "pearlCooldown", "blocked", "canHit", "aerialMace" },
    Ballistics = { "solve" },
  },
}
return Pearl
