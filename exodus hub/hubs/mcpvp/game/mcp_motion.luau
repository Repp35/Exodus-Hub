-- [[ mcp motion ]]
--!optimize 2
local Motion = {}
local units, collision, surface
local STEP, AIR_DRAG, VERTICAL_DRAG = 0.05, 0.91, 0.98
local FLAT = Vector3.new(1, 0, 1)
local function finite(vector)
  return typeof(vector) == "Vector3" and vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z and vector.Magnitude < 512
end
local function mode(character)
  if character:GetAttribute("Gliding") == true or character:GetAttribute("InCobweb") == true then
    return "controlled"
  end
  if character:GetAttribute("LocalInWater") == true or character:GetAttribute("InWater") == true or character:GetAttribute("InLava") == true then
    return "controlled"
  end
  return "normal"
end
function Motion.setup(deps)
  units = deps.Units
  local function library(name)
    local source = game:GetService("ReplicatedStorage"):FindFirstChild(name)
    local ok, value = pcall(function() return source and require(source) end)
    return ok and type(value) == "table" and value or nil
  end
  collision, surface = library("VoxelBlockCollision"), library("VoxelSurface")
  if collision and (type(collision.Collect) ~= "function" or type(collision.Resolve) ~= "function" or type(collision.Support) ~= "function") then
    collision = nil
  end
  return true
end
function Motion.sample(root, character, now, previous)
  local position = units.toBlocks(root.Position)
  local reported = units.toBlocks(root.AssemblyLinearVelocity)
  if not finite(reported) then
    reported = Vector3.zero
  end
  local teleport, epoch = character:GetAttribute("PearlTeleportAt"), character:GetAttribute("MovementCorrectionEpoch")
  if not previous or previous.character ~= character then
    return {
      character = character,
      position = position,
      velocity = reported,
      reported = reported,
      control = reported.Magnitude <= 8 and reported * FLAT or Vector3.zero,
      acceleration = Vector3.zero,
      at = now,
      revision = 0,
      teleport = teleport,
      epoch = epoch,
      mode = mode(character),
    }
  end
  local elapsed = now - previous.at
  local changed = (reported - previous.reported).Magnitude > 3
  if elapsed < 0.04 and not changed then
    return previous
  end
  if elapsed <= 0 then
    return previous
  end
  local offset = position - previous.position
  local discontinuity = teleport ~= previous.teleport
    or epoch ~= previous.epoch
    or offset.Magnitude > math.max(4, (reported.Magnitude + previous.velocity.Magnitude) * elapsed * 2 + 0.75)
  if discontinuity or elapsed > 0.35 then
    return Motion.sample(root, character, now, nil)
  end
  if offset.Magnitude < 0.001 and not changed and reported.Magnitude > 0.1 then
    return previous
  end
  local observed = offset / elapsed
  local velocity = reported.Magnitude > 0.1 and reported or (finite(observed) and observed or reported)
  if
    finite(observed)
    and observed.Magnitude > 1
    and reported.Magnitude > 0.1
    and observed.Unit:Dot(reported.Unit) < 0.6
    and (observed - reported).Magnitude > 4
  then
    velocity = observed
  end
  if changed then
    velocity = reported
  end
  local flat, old = velocity * FLAT, previous.velocity * FLAT
  local damping = (previous.grounded and (previous.groundDrag or 0.546) or AIR_DRAG) ^ (elapsed / STEP)
  local expectedY = -78.4 + (previous.velocity.Y + 78.4) * VERTICAL_DRAG ^ (elapsed / STEP)
  local impulse = (flat - (previous.control + (old - previous.control) * damping)).Magnitude > 3 or math.abs(velocity.Y - expectedY) > 3
  local control = previous.control
  if not impulse and damping < 0.999 then
    local inferred = (flat - old * damping) / (1 - damping)
    local limit = math.max(8, flat.Magnitude, old.Magnitude, control.Magnitude)
    if inferred.Magnitude > limit then
      inferred = inferred.Unit * limit
    end
    control = previous.ready and control:Lerp(inferred, 0.5) or inferred
  end
  if flat.Magnitude < 0.15 and (observed * FLAT).Magnitude < 0.5 then
    control = Vector3.zero
  elseif flat:Dot(old) < 0 and flat.Magnitude <= math.max(1, old.Magnitude) * 2 then
    control = flat
  end
  local acceleration = (velocity - previous.velocity) / elapsed
  if acceleration.Magnitude > 64 then
    acceleration = acceleration.Unit * 64
  end
  return {
    character = character,
    position = position,
    velocity = velocity,
    reported = reported,
    control = control,
    acceleration = acceleration,
    at = now,
    revision = previous.revision + 1,
    ready = true,
    teleport = teleport,
    epoch = epoch,
    grounded = previous.grounded,
    groundDrag = previous.groundDrag,
    mode = mode(character),
  }
end
function Motion.actor(root, character, sample, latency, params, detailed)
  local position = units.toBlocks(root.Position)
  local velocity = sample and sample.velocity or units.toBlocks(root.AssemblyLinearVelocity)
  if not finite(velocity) then
    velocity = Vector3.zero
  end
  local control = sample and sample.control or (velocity.Magnitude <= 8 and velocity * FLAT or Vector3.zero)
  local acceleration = sample and sample.acceleration or Vector3.zero
  local movementMode = sample and sample.mode or mode(character)
  local grounded = character:GetAttribute("VoxelGrounded") == true and math.abs(velocity.Y) < 0.5
  local overlap
  if detailed then
    overlap = OverlapParams.new()
    overlap.FilterType, overlap.RespectCanCollide, overlap.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, params.FilterDescendantsInstances
    if collision then
      local boxes = collision.Collect(workspace, units.toWorld(position), Vector3.zero, overlap)
      grounded = velocity.Y <= 0.5 and collision.Support(units.toWorld(position), boxes, units.toWorld(0.04)) ~= nil
    else
      local feet = units.toWorld(position - Vector3.new(0, 1.2, 0))
      grounded = velocity.Y <= 0.5 and workspace:Raycast(feet, units.offset(0, -0.12, 0), params) ~= nil
    end
    if sample then
      sample.grounded = grounded
      if grounded and surface and type(surface.Ground) == "function" and type(surface.Under) == "function" then
        sample.groundDrag = surface.Ground(surface.Under(workspace, root.Position, units.toWorld(1.25), params))
      end
    end
  end
  local points, ticks = { position }, 0
  local function step()
    local movement, groundDrag = velocity * STEP, 0.546
    if detailed and collision then
      local worldPosition, worldMovement = units.toWorld(position), units.toWorld(movement)
      local boxes = collision.Collect(workspace, worldPosition, worldMovement, overlap)
      if grounded and surface and type(surface.Ground) == "function" and type(surface.Under) == "function" then
        groundDrag = surface.Ground(surface.Under(workspace, worldPosition, units.toWorld(1.25), params))
      end
      local resolved, flags = collision.Resolve(
        worldPosition,
        worldMovement,
        boxes,
        grounded or velocity.Y < 0,
        grounded and movement.Y <= 0 and character:GetAttribute("Sneaking") == true
      )
      position += units.toBlocks(resolved)
      velocity = Vector3.new(flags.x and 0 or velocity.X, flags.y and 0 or velocity.Y, flags.z and 0 or velocity.Z)
      grounded = flags.grounded == true
    elseif detailed then
      local hit =
        workspace:Blockcast(CFrame.new(units.toWorld(position + Vector3.new(0, -0.35, 0))), units.offset(0.58, 1.78, 0.58), units.toWorld(movement), params)
      if hit and movement.Magnitude > 1e-6 then
        position += movement * math.max(0, (units.toBlocks(hit.Distance) - 1 / 320) / movement.Magnitude)
        local normal = hit.Normal
        velocity -= normal * velocity:Dot(normal)
        grounded = movement.Y <= 0 and normal.Y > 0.65
      else
        position += movement
        grounded = false
      end
    else
      position += movement
    end
    if movementMode == "controlled" then
      velocity += acceleration * (STEP * 0.85 ^ ticks)
    else
      local horizontal = control + (velocity * FLAT - control) * (grounded and groundDrag or AIR_DRAG)
      velocity = horizontal + Vector3.new(0, grounded and 0 or (velocity.Y - 1.6) * VERTICAL_DRAG, 0)
    end
    ticks += 1
    points[ticks + 1] = position
  end
  return {
    crouch = character:GetAttribute("Sneaking"),
    predict = function(time)
      local elapsed = math.max(0, time + latency)
      local tick = math.floor(elapsed / STEP)
      while ticks <= tick do
        step()
      end
      return points[tick + 1]:Lerp(points[tick + 2], (elapsed - tick * STEP) / STEP)
    end,
  }
end
Motion.__contract = {
  provides = { "setup", "sample", "actor" },
  requires = { Units = "mcpunits" },
  requiresMethods = { Units = { "toBlocks", "toWorld", "offset" } },
}
return Motion
