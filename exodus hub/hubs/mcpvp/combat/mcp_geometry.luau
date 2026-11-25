-- [[ mcpgeometry ]]
--!optimize 2
local Geometry = {}
local native
function Geometry.setup(deps)
  native = deps.Native
  return true
end
function Geometry.snap(point)
  return Vector3.new((math.floor(point.X / 3.2) + 0.5) * 3.2, (math.floor(point.Y / 3.2) + 0.5) * 3.2, (math.floor(point.Z / 3.2) + 0.5) * 3.2)
end
function Geometry.position(object)
  if object:IsA("BasePart") then
    return object.Position
  end
  if object:IsA("Model") then
    return object:GetPivot().Position
  end
  return nil
end
function Geometry.blastPosition(crystal)
  local feet = crystal:GetAttribute("CrystalFeet")
  return typeof(feet) == "Vector3" and feet or Geometry.position(crystal)
end
function Geometry.damage(snap, char, point, power, plannedBlock, predictedPosition)
  local root = char:FindFirstChild("HumanoidRootPart")
  if not root then
    return math.huge
  end
  local position = predictedPosition or root.Position
  local distance = (position - point).Magnitude / 3.2
  local diameter = power * 2
  if distance > diameter then
    return 0
  end
  local excluded = { char }
  local blocks = snap.world:FindFirstChild("PlayerBlocks")
  if blocks then
    for _, block in ipairs(blocks:GetChildren()) do
      if block:IsA("BasePart") and (block.Position - point).Magnitude < 0.2 then
        excluded[#excluded + 1] = block
      end
    end
  end
  local exposed, total = 0, 0
  for _, height in ipairs({ -3.6, -1, 1.8 }) do
    for _, offset in ipairs({ Vector3.new(-0.8, height, -0.8), Vector3.new(0, height, 0), Vector3.new(0.8, height, 0.8) }) do
      total += 1
      local delta = position + offset - point
      local hit = native.raycast(point + Vector3.new(0, 0.05, 0), delta, excluded)
      local blocked = hit and hit.Distance < delta.Magnitude - 0.15
      local melee = native.data().geometry
      if plannedBlock and melee and type(melee.Box) == "function" and delta.Magnitude > 0.01 then
        local size = Vector3.new(1.6, 1.6, 1.6)
        local distance = melee.Box(point + Vector3.new(0, 0.05, 0), delta.Unit, plannedBlock - size, plannedBlock + size, delta.Magnitude)
        if distance and distance < delta.Magnitude - 0.15 then
          blocked = true
        end
      end
      if not blocked then
        exposed += 1
      end
    end
  end
  local impact = (1 - distance / diameter) * (exposed / total)
  local damage = math.floor((impact * impact + impact) / 2 * 7 * diameter + 1)
  if exposed == 0 then
    return 0
  end
  local config = native.data().config
  local ladder = config and config.Ladder
  local armor, tough = 0, 0
  if ladder then
    for _, slot in ipairs(ladder.ArmorSlots or {}) do
      local attr = ladder.SlotAttributes[slot]
      local tier = tonumber(char:GetAttribute(attr)) or 0
      local material = ladder.ArmorTiers[tier]
      if material then
        armor += (ladder.ArmorPoints[material] or {})[slot] or 0
        tough += (ladder.ArmorToughness or {})[material] or 0
      end
    end
  end
  local effective = math.min(20, math.max(armor / 5, armor - damage / (2 + tough / 4)))
  damage *= 1 - effective / 25
  -- Vanilla baseline; only apply reductions when the replicated attribute actually exists.
  local protection = tonumber(char:GetAttribute("Protection"))
  if protection then
    damage *= 1 - math.clamp(protection, 0, 20) / 25
  end
  local resistUntil = tonumber(char:GetAttribute("Effect_resistance")) or 0
  if resistUntil > snap.server then
    damage *= math.max(0, 1 - 0.2 * ((tonumber(char:GetAttribute("Effect_resistanceLevel")) or 0) + 1))
  end
  return damage
end
function Geometry.evaluate(snap, target, point, power, cfg, minDamage, plannedBlock)
  local factor = cfg("MCDamageUncertainty") / 100
  local selfDamage = Geometry.damage(snap, snap.character, point, power, plannedBlock) * (1 + factor)
  local velocity = target.root.AssemblyLinearVelocity
  local lead = math.clamp(0.12 + (snap.ping or 0), 0.12, 0.3)
  local displacement = velocity * lead
  if displacement.Magnitude > 4 then
    displacement = displacement.Unit * 4
  end
  local predicted = target.root.Position + displacement
  local currentDamage = Geometry.damage(snap, target.character, point, power, plannedBlock)
  local futureDamage = Geometry.damage(snap, target.character, point, power, plannedBlock, predicted)
  local targetDamage = math.max(currentDamage, futureDamage) * math.max(0, 1 - factor)
  local reserve = snap.humanoid.MaxHealth * cfg("MCHealthReserve") / 100
  local safe = selfDamage <= cfg("MCMaxSelfDamage") and snap.humanoid.Health - selfDamage >= reserve
  local useful = targetDamage >= minDamage and targetDamage - selfDamage >= cfg("MCDamageMargin")
  return safe and useful, selfDamage, targetDamage
end
function Geometry.cellFree(snap, position)
  local params = OverlapParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  local ignore = {}
  for _, name in ipairs({ "PredictedBlocks", "LocalItemVisuals", "LocalBowVisuals" }) do
    local folder = snap.world:FindFirstChild(name)
    if folder then
      ignore[#ignore + 1] = folder
    end
  end
  params.FilterDescendantsInstances = ignore
  for _, part in ipairs(snap.world:GetPartBoundsInBox(CFrame.new(position), Vector3.new(3.05, 3.05, 3.05), params)) do
    if part.CanCollide or part:FindFirstAncestorOfClass("Model") and part:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then
      return false
    end
  end
  return true
end
function Geometry.placement(snap, desired)
  local center = Geometry.snap(desired)
  if (center - snap.eye).Magnitude > 14.4 or not Geometry.cellFree(snap, center) then
    return nil
  end
  -- Aim at the support face, allowing the native placement routine to resolve and validate the exact cell.
  local support = native.raycast(center + Vector3.new(0, 1.5, 0), Vector3.new(0, -5, 0))
  if not support or support.Normal.Y < 0.99 then
    return nil
  end
  local placement = native.data().placement
  local actual = placement and placement.FromHit(support)
  if not actual or (actual - center).Magnitude > 0.1 then
    return nil
  end
  local point = support.Position
  if not native.visible(snap.eye, point, support.Instance) then
    return nil
  end
  return { cell = center, point = point, support = support.Instance }
end
function Geometry.protection(snap, source)
  local delta = source - snap.root.Position
  local flat = Vector3.new(delta.X, 0, delta.Z)
  if flat.Magnitude < 1 then
    return nil
  end
  local center = Geometry.snap(snap.root.Position + flat.Unit * 3.2 - Vector3.new(0, 2.4, 0))
  if (center - source).Magnitude < 1.7 then
    return nil
  end
  for height = 0, 2 do
    local placement = Geometry.placement(snap, center + Vector3.new(0, height * 3.2, 0))
    if placement then
      return placement
    end
  end
  return nil
end
function Geometry.pearl(snap, target, cfg, projectile)
  local selfDamage = (native.data().config and native.data().config.Items.Pearl.selfDamage) or 2
  if snap.humanoid.Health - selfDamage <= snap.humanoid.MaxHealth * cfg("MCPearlMinHealth") / 100 then
    return nil
  end
  -- Vanilla launch speed in the game's 3.2-stud block scale; observed packets replace this baseline.
  projectile = projectile or { speed = 96, gravity = 38.4, drag = 0.99 }
  if not projectile.speed or projectile.speed <= 0 then
    return nil
  end
  local origin = snap.eye
  local speed, gravity = projectile.speed, projectile.gravity
  local lead = math.min(cfg("MCPearlLead"), target.distance / speed)
  local toward = target.root.Position - snap.root.Position
  local horizontal = Vector3.new(toward.X, 0, toward.Z)
  if horizontal.Magnitude < 0.1 then
    return nil
  end
  local landing = target.root.Position + target.root.AssemblyLinearVelocity * lead - horizontal.Unit * 4 - Vector3.new(0, 3.5, 0)
  local ground = native.raycast(landing + Vector3.new(0, 5, 0), Vector3.new(0, -13, 0), { target.character })
  if not ground or ground.Normal.Y < 0.7 then
    return nil
  end
  landing = ground.Position + Vector3.new(0, 0.5, 0)
  if (landing - snap.root.Position).Magnitude >= target.distance - 3.2 then
    return nil
  end
  local flat = Vector3.new(landing.X - origin.X, 0, landing.Z - origin.Z)
  local x = flat.Magnitude
  if x < 0.1 then
    return nil
  end
  -- Match the native fixed 50 ms projectile tick, including drag after each position step.
  local bestDirection, bestError, bestTime = nil, math.huge, nil
  for degrees = -40, 65, 1 do
    local theta = math.rad(degrees)
    local direction = flat.Unit * math.cos(theta) + Vector3.new(0, math.sin(theta), 0)
    local velocity, position = direction * speed, origin
    for step = 1, 60 do
      local nextPosition = position + velocity * 0.05
      local along = (nextPosition - origin):Dot(flat.Unit)
      if along >= x then
        local prior = (position - origin):Dot(flat.Unit)
        local alpha = math.clamp((x - prior) / math.max(0.001, along - prior), 0, 1)
        local atTarget = position:Lerp(nextPosition, alpha)
        local error = math.abs(atTarget.Y - landing.Y)
        if error < bestError then
          bestDirection, bestError, bestTime = direction, error, (step - 1 + alpha) * 0.05
        end
        break
      end
      position = nextPosition
      velocity = velocity * (projectile.drag or 0.99) - Vector3.new(0, gravity * 0.05, 0)
    end
  end
  if not bestDirection or bestError > 1.5 or not bestTime then
    return nil
  end
  local velocity, previous = bestDirection * speed, origin
  local steps = math.ceil(bestTime / 0.05)
  for step = 1, steps do
    local point = previous + velocity * 0.05
    local hit = native.raycast(previous, point - previous, { target.character })
    if hit and step < steps - 1 then
      return nil
    end
    previous = point
    velocity = velocity * (projectile.drag or 0.99) - Vector3.new(0, gravity * 0.05, 0)
  end
  -- Avoid landing next to an existing explosive rather than assuming every pursuit is advantageous.
  for _, name in ipairs({ "EndCrystals", "PlayerBlocks" }) do
    local folder = snap.world:FindFirstChild(name)
    if folder then
      for _, obj in ipairs(folder:GetChildren()) do
        local dangerous = name == "EndCrystals" or (obj:GetAttribute("BlockKey") == "respawn_anchor" and (tonumber(obj:GetAttribute("AnchorCharges")) or 0) > 0)
        local pos = dangerous and Geometry.position(obj)
        if pos and (pos - landing).Magnitude < 8 then
          return nil
        end
      end
    end
  end
  return origin + bestDirection * 30
end
Geometry.__contract = {
  requires = { Native = "mcpnative" },
  provides = { "setup", "snap", "position", "blastPosition", "damage", "evaluate", "cellFree", "placement", "protection", "pearl" },
}
return Geometry
