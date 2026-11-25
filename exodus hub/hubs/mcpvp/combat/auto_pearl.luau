-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics, utils
local shot, sending, retryAt, motionSample = nil, false, 0, nil
local speed, gravity, drag = 96, 38.4, 0.99

local function restore()
  local snap = native.snapshot()
  if not snap or not shot or shot.restored or snap.character ~= shot.character then
    return
  end
  if snap.tool == shot.tool or snap.tool == nil then
    local previous = shot.previousTool
    if previous and previous.Parent then
      native.equip(snap, previous)
    elseif utils.getConfigValue("MCAutoSword") then
      local sword = native.findSword(snap)
      if sword then
        native.equip(snap, sword)
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
  restore()
  if shot then
    retryAt = math.max(retryAt, shot.arrivalAt or 0, os.clock() + 0.75)
  end
  shot, sending, motionSample = nil, false, nil
end
function Pearl.busy() return sending or (shot ~= nil and shot.phase ~= "flight") end
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
  local params, ignored = RaycastParams.new(), { snap.camera }
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
  params.FilterType, params.RespectCanCollide, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  local motion = chosen.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
  if motion.Magnitude > 45 then
    return nil
  end
  if motionSample and motionSample.character == chosen.character then
    local elapsed = snap.now - motionSample.at
    if elapsed > 0.05 and elapsed < 0.75 then
      local measured = (chosen.root.Position - motionSample.position) * Vector3.new(1, 0, 1) / elapsed
      if measured.Magnitude > 60 or (measured - motionSample.velocity).Magnitude > 30 then
        motionSample = nil
        return nil
      end
      motion = motion * 0.5 + measured * 0.5
    end
  end
  motionSample = { character = chosen.character, at = snap.now, position = chosen.root.Position, velocity = motion }
  local gap = chosen.root.Position - snap.root.Position
  local horizontal = gap * Vector3.new(1, 0, 1)
  if horizontal.Magnitude < 16 then
    return nil
  end
  local reach = native.stats(native.findSword(snap)).reach or 9.6
  local flight = math.clamp(horizontal.Magnitude / speed, 0.2, 2)
  local destination
  for _ = 1, 4 do
    local future = chosen.root.Position + motion * (flight + 0.12)
    -- Approach from our side, leaving room for a normal melee engagement.
    local approach = (future - snap.root.Position) * Vector3.new(1, 0, 1)
    if approach.Magnitude < 0.01 then
      return nil
    end
    local point = future - approach.Unit * math.min(3.2, reach * 0.4)
    local floor = workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -48, 0), params)
    if not floor or floor.Normal.Y < 0.65 or floor.Material == Enum.Material.Water then
      return nil
    end
    local block = floor.Instance:GetAttribute("BlockKey")
    if block == "lava" or block == "water" then
      return nil
    end
    local aim, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 2.4, drag)
    if not aim then
      return nil
    end
    if math.abs(duration - flight) * math.max(1, motion.Magnitude) <= 1.6 then
      local arrival = chosen.root.Position + motion * (duration + 0.12)
      local error = (arrival - floor.Position) * Vector3.new(1, 0, 1)
      local walkingGap = (arrival - snap.root.Position) * Vector3.new(1, 0, 1)
      if error.Magnitude <= reach and error.Magnitude + 8 < walkingGap.Magnitude then
        destination = floor.Position
        return aim, duration, destination
      end
      return nil
    end
    flight = duration
  end
  return nil
end

function Pearl.step(snap, chosen)
  if shot and shot.character ~= snap.character then
    Pearl.reset()
  end
  if shot then
    if shot.phase == "equip" then
      if snap.now >= shot.timeout then
        Pearl.reset()
        return false
      end
      if snap.tool ~= shot.tool then
        return false
      end
      if not native.usePearl(snap, shot.tool, shot.direction) then
        Pearl.reset()
        return false
      end
      shot.phase, shot.timeout = "confirm", snap.now + 1.2
      shot.arrivalAt = snap.now + shot.flight + 0.6
      return true
    end
    if shot.phase == "confirm" then
      local confirmed = not shot.tool.Parent or (tonumber(shot.tool:GetAttribute("Count")) or shot.count) < shot.count or not native.pearlReady()
      if not confirmed then
        if snap.now >= shot.timeout then
          Pearl.reset()
          retryAt = math.max(retryAt, snap.now + 1.5)
        end
        return false
      end
      restore()
      shot.phase = "flight"
    end
    restore()
    local teleported = snap.character:GetAttribute("PearlTeleportAt") ~= shot.teleportAt
    if not teleported and snap.now < shot.arrivalAt then
      return false
    end
    retryAt = math.max(retryAt, snap.now + (teleported and 0.65 or 1.5))
    shot = nil
  end
  if not chosen then
    return false
  end
  if not chosen.character.Parent or chosen.humanoid.Health <= 0 then
    return false
  end
  if
    snap.now < retryAt
    or native.blocked(snap)
    or not native.pearlReady()
    or native.canHit(snap, chosen)
    or native.aerialMace(snap, chosen)
    or not native.visible(snap, chosen.root.Position, chosen.character)
  then
    return false
  end
  retryAt = snap.now + 0.5
  local tool = native.findPearl(snap)
  if not tool then
    return false
  end
  local direction, flight = plan(snap, chosen)
  if not direction then
    return false
  end
  shot = {
    character = snap.character,
    tool = tool,
    previousTool = snap.tool,
    count = tonumber(tool:GetAttribute("Count")) or 1,
    teleportAt = snap.character:GetAttribute("PearlTeleportAt"),
    phase = "equip",
    direction = direction,
    flight = flight,
    timeout = snap.now + 0.8,
    arrivalAt = snap.now + flight + 1.4,
  }
  target.hold(chosen.character, shot.arrivalAt + 0.75)
  sending = true
  local ok, equipped = pcall(native.equip, snap, tool)
  sending = false
  if not ok or not equipped then
    Pearl.reset()
    if not ok then
      error(equipped)
    end
    return false
  end
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step", "observeProjectile" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics", Utils = "utils" },
  requiresMethods = {
    Native = { "snapshot", "findSword", "equip", "findPearl", "usePearl", "pearlReady", "blocked", "canHit", "aerialMace", "visible", "stats" },
    Utils = { "getConfigValue" },
    Target = { "hold" },
    Ballistics = { "solve" },
  },
}
return Pearl
