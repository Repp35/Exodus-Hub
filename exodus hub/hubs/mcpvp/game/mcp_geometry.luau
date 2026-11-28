-- [[ mcpgeometry ]]
--!optimize 2
local Geometry = {}
local units, world, players, weapons, boxes, shields, rules
local storage, nextScan = nil, 0
local function library(name, methods)
  local source = storage:FindFirstChild(name)
  if not source then
    return nil
  end
  local value = require(source)
  if type(value) ~= "table" then
    error("MCPvP: API inválida: " .. name)
  end
  for _, method in ipairs(methods) do
    if value[method] == nil then
      return nil
    end
    if type(value[method]) ~= "function" then
      error("MCPvP: API inválida: " .. name .. "." .. method)
    end
  end
  return value
end
function Geometry.ready()
  local now = os.clock()
  if now >= nextScan then
    nextScan = now + 0.5
    weapons = weapons or library("VoxelWeapons", { "Stats" })
    boxes = boxes or library("VoxelMeleeGeometry", { "Hit", "Box", "Eye" })
    shields = shields or library("ShieldRules", { "IsBlocking" })
    rules = rules or library("SpawnBowRules", { "CanShoot" })
  end
  return weapons ~= nil and boxes ~= nil
end
function Geometry.setup(deps)
  units, world, players = deps.Units, deps.Utils.getWorkspace(), game:GetService("Players")
  storage, nextScan = game:GetService("ReplicatedStorage"), 0
  weapons, boxes, shields, rules = nil, nil, nil, nil
  Geometry.ready()
  return true
end
function Geometry.stats(tool)
  if not tool or not Geometry.ready() then
    return {}
  end
  local value = weapons.Stats(tool)
  if value == nil then
    return {}
  end
  return { type = value.type, speed = value.speed, reach = value.reachBlocks or units.toBlocks(value.reach), damage = value.damage }
end
function Geometry.melee(tool)
  if not tool then
    return false
  end
  local kind = Geometry.stats(tool).type
  return kind == "sword"
    or kind == "axe"
    or kind == "spear"
    or kind == "pickaxe"
    or kind == "mace" and (tonumber(tool:GetAttribute("Breach")) or 0) > 0 and (tonumber(tool:GetAttribute("Density")) or 0) <= 0
end
function Geometry.blocking(character) return shields ~= nil and shields.IsBlocking(character) == true end
function Geometry.allowed(character)
  if rules then
    return rules.CanShoot(character)
  end
  if not character or character:GetAttribute("ArenaProtected") == true or character:GetAttribute("DuelCombatActive") == false then
    return false
  end
  local player = players:GetPlayerFromCharacter(character)
  return player
    and player:GetAttribute("InArena") == true
    and player:GetAttribute("ArenaProtected") ~= true
    and player:GetAttribute("DuelCombatActive") ~= false
end
function Geometry.eye(root, character) return boxes.Eye(root.Position, character:GetAttribute("Sneaking")) end
function Geometry.grounded(snap)
  local value = snap.character:GetAttribute("VoxelGrounded")
  return value == true or value == nil and snap.humanoid.FloorMaterial ~= Enum.Material.Air
end
function Geometry.falling(snap)
  return not Geometry.grounded(snap)
    and (tonumber(snap.character:GetAttribute("LocalFallDistance")) or 0) > 0
    and units.toBlocks(snap.root.AssemblyLinearVelocity.Y) < -1 / 32
    and not snap.humanoid.Sit
    and not snap.humanoid.PlatformStand
    and snap.character:GetAttribute("LocalInWater") ~= true
    and snap.character:GetAttribute("InLava") ~= true
    and snap.player:GetAttribute("LocalGliding") ~= true
    and snap.character:GetAttribute("Gliding") ~= true
end
local function params(snap, actors)
  local ignored = { snap.character, snap.camera }
  if actors then
    for _, player in ipairs(players:GetPlayers()) do
      if player.Character then
        ignored[#ignored + 1] = player.Character
      end
    end
    local bots = world:FindFirstChild("ArenaPvPBots")
    if bots then
      ignored[#ignored + 1] = bots
    end
  end
  local value = RaycastParams.new()
  value.FilterType, value.RespectCanCollide, value.IgnoreWater = Enum.RaycastFilterType.Exclude, true, actors == true
  value.FilterDescendantsInstances = ignored
  return value
end
function Geometry.visible(snap, point, character, origin)
  origin = origin or snap.eye
  local hit = world:Raycast(origin, point - origin, params(snap, false))
  return not hit or character and hit.Instance:IsDescendantOf(character)
end
function Geometry.point(character, root)
  local rear = Vector3.zero
  if shields and shields.IsBlocking(character) then
    rear = -root.CFrame.LookVector * Vector3.new(1, 0, 1) * units.toWorld(0.25)
  end
  return root.Position + units.offset(0, character:GetAttribute("Sneaking") and 3 / 64 or 5 / 32, 0) + rear
end
function Geometry.hit(snap, target, tool, direction)
  if not Geometry.allowed(target.character) or target.humanoid.Health <= 0 then
    return nil
  end
  local reach = units.toWorld(Geometry.stats(tool).reach or 3)
  local distance = boxes.Hit(snap.eye, direction, target.root.Position, target.character:GetAttribute("Sneaking"), reach)
  if not distance then
    return nil
  end
  local obstruction = world:Raycast(snap.eye, direction * distance, params(snap, true))
  if obstruction and obstruction.Distance < distance - units.toWorld(1 / 320) then
    return nil
  end
  local function closer(character)
    if character == snap.character or character == target.character then
      return false
    end
    local human, root = character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
    if not human or human.Health <= 0 or not root then
      return false
    end
    local other = boxes.Hit(snap.eye, direction, root.Position, character:GetAttribute("Sneaking"), distance)
    return other ~= nil and other < distance
  end
  for _, player in ipairs(players:GetPlayers()) do
    if player.Character and closer(player.Character) then
      return nil
    end
  end
  local bots = world:FindFirstChild("ArenaPvPBots")
  if bots then
    for _, character in ipairs(bots:GetChildren()) do
      if closer(character) then
        return nil
      end
    end
  end
  local crystals = world:FindFirstChild("EndCrystals")
  if crystals then
    for _, crystal in ipairs(crystals:GetChildren()) do
      local feet = crystal:GetAttribute("CrystalFeet")
      if typeof(feet) == "Vector3" then
        local other = boxes.Box(snap.eye, direction, feet - units.offset(1, 0, 1), feet + units.offset(1, 2, 1), distance)
        if other and other < distance then
          return nil
        end
      end
    end
  end
  return units.toBlocks(distance)
end
function Geometry.direction(snap, target, tool)
  if not target or not target.character.Parent or not target.root.Parent then
    return nil
  end
  local relative = units.toBlocks(snap.eye - target.root.Position)
  local crouch = target.character:GetAttribute("Sneaking") and 0.3 or 0
  local points = {
    Geometry.point(target.character, target.root),
    target.root.Position
      + units.toWorld(Vector3.new(math.clamp(relative.X, -3 / 8, 3 / 8), math.clamp(relative.Y, -1.25, 0.18 - crouch), math.clamp(relative.Z, -3 / 8, 3 / 8))),
    target.root.Position + units.offset(0, 0.5 - crouch, 0),
  }
  for _, point in ipairs(points) do
    local delta = point - snap.eye
    if delta.Magnitude > 0.001 and Geometry.hit(snap, target, tool, delta.Unit) then
      return delta.Unit
    end
  end
  return nil
end
function Geometry.incoming(snap, target)
  local eye = Geometry.eye(target.root, target.character)
  local aim = target.player:GetAttribute("FrontCameraAimDirection")
  if typeof(aim) ~= "Vector3" or aim.Magnitude < 0.001 then
    aim = target.root.CFrame.LookVector
  end
  if aim.Magnitude < 0.001 then
    return false
  end
  local reach = Geometry.stats(target.character:FindFirstChildOfClass("Tool")).reach or 3
  local distance = boxes.Hit(eye, aim.Unit, snap.root.Position, snap.character:GetAttribute("Sneaking"), units.toWorld(reach))
  if not distance then
    return false
  end
  local obstruction = world:Raycast(eye, aim.Unit * distance, params(snap, true))
  return not obstruction or obstruction.Distance >= distance - units.toWorld(1 / 320)
end
function Geometry.aerialMace(snap, target)
  if Geometry.stats(target.character:FindFirstChildOfClass("Tool")).type ~= "mace" then
    return false
  end
  local floor = world:Raycast(target.root.Position, units.offset(0, -3.75, 0), params(snap, true))
  return target.character:GetAttribute("VoxelGrounded") ~= true and (not floor or units.toBlocks(target.root.Position.Y - snap.root.Position.Y) > 2.5)
end
local function clearance(snap)
  local ray, room = params(snap, true), 1.3
  local feet = snap.root.Position - units.offset(0, 1.25, 0)
  for _, offset in ipairs({ Vector3.zero, Vector3.new(0.28, 0, 0), Vector3.new(-0.28, 0, 0), Vector3.new(0, 0, 0.28), Vector3.new(0, 0, -0.28) }) do
    local top = feet + units.toWorld(offset + Vector3.new(0, 1.9, 0))
    local hit = world:Raycast(top, units.offset(0, 1.36, 0), ray)
    if hit then
      room = math.min(room, math.max(0, units.toBlocks(hit.Distance) - 0.06))
    end
  end
  return room
end
function Geometry.headroom(snap) return clearance(snap) >= 1.3 - 1 / 320 end
function Geometry.criticalWindow(snap)
  local room = clearance(snap)
  if room < 3 / 64 then
    return nil
  end
  -- Under a low ceiling, charge first: the head collision creates a much shorter fall window.
  return room >= 1.3 - 1 / 320 and 0.28 or 0
end
function Geometry.jumpRisk(snap)
  local crystals, seen = game:GetService("CollectionService"):GetTagged("EndCrystal"), {}
  local folder = world:FindFirstChild("EndCrystals")
  if folder then
    for _, value in ipairs(folder:GetChildren()) do
      crystals[#crystals + 1] = value
    end
  end
  local ray = params(snap, true)
  local ignored = ray.FilterDescendantsInstances
  for _, value in ipairs(crystals) do
    ignored[#ignored + 1] = value
  end
  ray.FilterDescendantsInstances = ignored
  local origins = {}
  for _, crystal in ipairs(crystals) do
    local feet = crystal:GetAttribute("CrystalFeet")
    if crystal.Parent and typeof(feet) == "Vector3" and not seen[crystal] then
      seen[crystal] = true
      origins[#origins + 1] = units.toBlocks(feet)
    end
  end
  local overlap = OverlapParams.new()
  overlap.FilterType, overlap.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignored
  for _, block in ipairs(world:GetPartBoundsInBox(CFrame.new(snap.root.Position), units.offset(5, 6, 5), overlap)) do
    local key = string.lower(tostring(block:GetAttribute("BlockKey") or block.Name))
    if key == "obsidian" then
      local top = block.Position + Vector3.new(0, block.Size.Y / 2, 0)
      if not world:Raycast(top + units.offset(0, 1 / 64, 0), units.offset(0, 2, 0), ray) then
        origins[#origins + 1] = units.toBlocks(top)
      end
    end
  end
  local start = units.toBlocks(snap.root.Position) - Vector3.new(0, 1.25, 0)
  local motion = units.toBlocks(snap.root.AssemblyLinearVelocity) * Vector3.new(1, 0, 1)
  for _, origin in ipairs(origins) do
    local height, vy = 0, 8.4
    for tick = 0, 12 do
      local predicted = start + motion * (tick * 0.05) + Vector3.new(0, height, 0)
      local delta = predicted - origin
      -- Local estimate only: the server's maximum-damage formula is absent from the dump.
      if delta.Y >= -1 / 64 and delta.Y <= 2 and math.abs(delta.X) <= 1.3 and math.abs(delta.Z) <= 1.3 then
        local exposed = true
        for _, y in ipairs({ 3 / 64, 1, 1.95 }) do
          local from = origin + Vector3.new(0, 1 / 64, 0)
          if world:Raycast(units.toWorld(from), units.toWorld(predicted + Vector3.new(0, y, 0) - from), ray) then
            exposed = false
            break
          end
        end
        if exposed then
          return true
        end
      end
      height += vy * 0.05
      vy = (vy - 1.6) * 0.98
      if height < 0 then
        break
      end
    end
  end
  return false
end
Geometry.__contract = {
  provides = {
    "setup",
    "ready",
    "stats",
    "allowed",
    "eye",
    "grounded",
    "falling",
    "visible",
    "point",
    "hit",
    "direction",
    "incoming",
    "aerialMace",
    "jumpRisk",
    "headroom",
    "criticalWindow",
    "melee",
    "blocking",
  },
  requires = { Units = "mcpunits", Utils = "utils" },
  requiresMethods = { Units = { "toWorld", "toBlocks", "offset" }, Utils = { "getWorkspace" } },
}
return Geometry
