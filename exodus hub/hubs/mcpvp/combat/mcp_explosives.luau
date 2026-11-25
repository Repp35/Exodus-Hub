-- [[ mcpexplosives ]]
--!optimize 2
local Explosives = {}
local native, geometry
local opportunities, templates = {}, {}
local comboMode, comboAt = nil, -math.huge
local original, held, lastPulse = nil, nil, -math.huge
local blockSnapshot, blockCache
local placed = {}
local manualOverride = false
local encounter
local lastBase = -math.huge
local function remember(char, mode, untilAt)
  if not encounter or encounter.character ~= char then
    encounter = { character = char, mode = mode, untilAt = untilAt }
  else
    encounter.mode = mode
    encounter.untilAt = math.max(encounter.untilAt, untilAt)
  end
end
local function blockKey(block) return block:GetAttribute("BlockKey") or string.lower(block.Name) end
local function blocks(snap)
  if blockSnapshot == snap then
    return blockCache
  end
  local list, seen = {}, {}
  local predicted = snap.world:FindFirstChild("PredictedBlocks")
  local visuals = snap.world:FindFirstChild("LocalItemVisuals")
  local function add(block)
    if (predicted and block:IsDescendantOf(predicted)) or (visuals and block:IsDescendantOf(visuals)) then
      return
    end
    if block:IsA("BasePart") and not seen[block] and (block.Position - snap.root.Position).Magnitude <= 22 then
      local key = blockKey(block)
      if key == "obsidian" or key == "respawn_anchor" then
        seen[block] = true
        list[#list + 1] = block
      end
    end
  end
  local folder = snap.world:FindFirstChild("PlayerBlocks")
  if folder then
    for _, block in ipairs(folder:GetChildren()) do
      add(block)
    end
  end
  -- Includes map obsidian and blocks placed before the assistant was enabled.
  for _, block in ipairs(snap.world:GetPartBoundsInRadius(snap.root.Position, 22)) do
    add(block)
  end
  table.sort(list, function(a, b) return (a.Position - snap.root.Position).Magnitude < (b.Position - snap.root.Position).Magnitude end)
  blockSnapshot, blockCache = snap, list
  return list
end
local function state(block)
  if not opportunities[block] then
    opportunities[block] = { spent = false, untilAt = -math.huge, strikeAt = -math.huge }
  end
  return opportunities[block]
end
local function above(target, top)
  local delta = target.root.Position - top
  -- The native player body extends four studs below HumanoidRootPart.
  return delta.Y >= 4 - 0.32 and Vector3.new(delta.X, 0, delta.Z).Magnitude <= 4.48
end
local function candidate(snap, targets, point, power)
  local chosen, best = nil, 0
  for _, target in ipairs(targets) do
    if target.humanoid.Health > 0 and (target.root.Position - point).Magnitude <= power * 2 * 3.2 then
      local damage = geometry.damage(snap, target.character, point, power)
      if damage > best then
        chosen, best = target, damage
      end
    end
  end
  return chosen, best
end
local function crystalAt(snap, top)
  local folder = snap.world:FindFirstChild("EndCrystals")
  if folder then
    for _, crystal in ipairs(folder:GetChildren()) do
      local point = geometry.blastPosition(crystal)
      if point and (point - top).Magnitude < 2 then
        return crystal, point
      end
    end
  end
  return nil
end
function Explosives.setup(deps)
  native, geometry = deps.Native, deps.Geometry
  return true
end
function Explosives.release()
  -- Finish the crystal transaction without switching back to a block.
  original, held = nil, nil
end
function Explosives.reset()
  Explosives.release()
  opportunities, templates, placed = {}, {}, {}
  manualOverride = false
  encounter, lastBase = nil, -math.huge
  blockSnapshot, blockCache = nil, nil
  comboMode, comboAt, lastPulse = nil, -math.huge, -math.huge
end
function Explosives.mark(object, time)
  placed[object] = time
  if time == nil then
    opportunities[object] = nil
  end
end
function Explosives.mode()
  if encounter and os.clock() < encounter.untilAt and encounter.character.Parent and not manualOverride then
    return encounter.mode
  end
  return os.clock() - comboAt < 2.5 and comboMode or nil
end
function Explosives.follow(snap, char, cfg)
  if manualOverride or not char or not char.Parent then
    return false
  end
  local mode = cfg("MCDTap") and "dtap" or (cfg("MCCrystal") and "crystal" or nil)
  if not mode then
    return false
  end
  remember(char, mode, snap.now + math.max(cfg("MCComboLifetime"), 12))
  return true
end
function Explosives.clearCombo()
  Explosives.reset()
  manualOverride = true
end
function Explosives.observe(snap, targets, cfg)
  if held and native.equipped() ~= held then
    Explosives.clearCombo()
  end
  local chosen
  for block in pairs(opportunities) do
    if not block.Parent then
      opportunities[block] = nil
    end
  end
  for _, block in ipairs(blocks(snap)) do
    local key = blockKey(block)
    if (key == "obsidian" and (cfg("MCCrystal") or cfg("MCDTap"))) or (key == "respawn_anchor" and cfg("MCAnchor")) then
      local top = block.Position + Vector3.new(0, key == "obsidian" and 1.6 or 0, 0)
      local target = candidate(snap, targets, top, key == "obsidian" and 6 or 5)
      if not target and key == "obsidian" and (placed[block] or -math.huge) > 0 and block:GetAttribute("Builder") == snap.player.UserId then
        for _, other in ipairs(targets) do
          if (other.root.Position - top).Magnitude <= 12.8 then
            target = other
            break
          end
        end
      end
      if
        target
        and (placed[block] or -math.huge) > 0
        and block:GetAttribute("Builder") == snap.player.UserId
        and snap.now - placed[block] < cfg("MCComboLifetime")
        and (target.root.Position - top).Magnitude <= 12.8
      then
        manualOverride = false
        local entry = state(block)
        entry.manualUntil = math.max(entry.manualUntil or -math.huge, placed[block] + cfg("MCComboLifetime"))
        target.manualCombo = true
        if key == "obsidian" then
          remember(target.character, cfg("MCDTap") and "dtap" or "crystal", entry.manualUntil)
        end
      end
      if target then
        chosen = chosen or target
      end
    end
  end
  return chosen
end
function Explosives.needsStrike(snap, target, cfg)
  if manualOverride or (not cfg("MCDTap") and not (cfg("MCCrystal") and cfg("MCCrystalAutoCombo"))) or not target or not native.find("EndCrystal", true) then
    return false, false
  end
  for _, block in ipairs(blocks(snap)) do
    if blockKey(block) == "obsidian" and snap.now < (state(block).manualUntil or -math.huge) then
      local top = block.Position + Vector3.new(0, 1.6, 0)
      if (top - snap.eye).Magnitude <= 14.4 and (target.root.Position - top).Magnitude <= 12.8 and not above(target, top) then
        return true, true
      end
    end
  end
  return false, false
end
function Explosives.struck(snap, target, cfg)
  if not cfg("MCDTap") and not (cfg("MCCrystal") and cfg("MCCrystalAutoCombo")) then
    return
  end
  for _, block in ipairs(blocks(snap)) do
    if blockKey(block) == "obsidian" and snap.now < (state(block).manualUntil or -math.huge) then
      local top = block.Position + Vector3.new(0, 1.6, 0)
      if (top - snap.eye).Magnitude <= 14.4 and (target.root.Position - top).Magnitude <= 12.8 then
        local entry = state(block)
        entry.strikeAt, entry.target = snap.now, target.character
        entry.spent, entry.finished = false, false
        entry.manualUntil = snap.now + cfg("MCComboLifetime")
        comboMode, comboAt = "dtap", snap.now
        remember(target.character, "dtap", entry.manualUntil)
      end
    end
  end
end
function Explosives.pulse(snap, targets, cfg)
  if held and native.equipped() ~= held then
    Explosives.clearCombo()
    return false
  end
  if manualOverride then
    if not snap.equipped or snap.equipped:GetAttribute("ClassItem") ~= "EndCrystal" then
      return false
    end
    manualOverride = false
  end
  if not cfg("MCCrystal") and not cfg("MCDTap") then
    Explosives.release()
    return false
  end
  local crystalItem = native.find("EndCrystal", true)
  if not crystalItem or native.inventoryOpen() then
    Explosives.release()
    return false
  end
  local acted = false
  for _, block in ipairs(blocks(snap)) do
    if not block.Parent or blockKey(block) ~= "obsidian" then
      continue
    end
    local top = block.Position + Vector3.new(0, 1.6, 0)
    if (top - snap.eye).Magnitude > 14.4 then
      continue
    end
    local entry = state(block)
    local target = candidate(snap, targets, top, 6)
    local elevated = false
    -- Any airborne opponent exposed to this blast is eligible.
    for _, other in ipairs(targets) do
      if other.humanoid.Health > 0 and other.humanoid.FloorMaterial == Enum.Material.Air and geometry.damage(snap, other.character, top, 6) > 0 then
        target, elevated = other, true
        break
      end
    end
    local launch = false
    if target and not elevated and (target.root.Position - top).Magnitude > 12.8 then
      target = nil
    end
    -- A dispatched swing is not a confirmed hit. Wait for the target record to acknowledge it.
    if (cfg("MCDTap") or cfg("MCCrystal") and cfg("MCCrystalAutoCombo")) and snap.now - entry.strikeAt < cfg("MCDTapLaunchWindow") then
      for _, other in ipairs(targets) do
        if other.character == entry.target and other.humanoid.Health > 0 and (other.lastHit or -math.huge) >= entry.strikeAt
          and (other.root.Position - top).Magnitude <= 12.8 then
          launch = true
          if not elevated then
            target = other
          end
          break
        end
      end
    end
    if not target then
      entry.spent = false
      continue
    end
    local crystal, point = crystalAt(snap, top)
    -- Place immediately after the sword hit; wait for the airborne damage opportunity only when breaking.
    if not elevated and (not launch or crystal) then
      continue
    end
    -- Match crystalPick in the game client: aim inside the native CrystalFeet box.
    local feet = point or top
    local low = feet - Vector3.new(3.2, 0, 3.2)
    local high = feet + Vector3.new(3.2, 6.4, 3.2)
    local inset = 0.05
    local hitPoint = Vector3.new(
      math.clamp(snap.eye.X, low.X + inset, high.X - inset),
      math.clamp(snap.eye.Y, low.Y + inset, high.Y - inset),
      math.clamp(snap.eye.Z, low.Z + inset, high.Z - inset)
    )
    local delta = hitPoint - snap.eye
    if delta.Magnitude < 0.01 then
      hitPoint = feet + Vector3.new(0, 3.2, 0)
      delta = hitPoint - snap.eye
    end
    local melee = native.data().geometry
    local reach = native.stats(crystalItem.tool).reach
    local inReach = melee and melee.Box and delta.Magnitude > 0.01 and melee.Box(snap.eye, delta.Unit, low, high, reach) ~= nil
    if not inReach then
      continue
    end
    local equipped = native.equipped()
    local switching = equipped ~= crystalItem.tool
    local selfSafe = geometry.damage(snap, snap.character, point or top, 6) <= 0
    -- Do not take over the hotbar merely because a player is airborne near a block.
    -- Manual crystal use still works without a preceding sword hit.
    if switching then
      local confirmed = target.lastHit or -math.huge
      if snap.now - confirmed >= cfg("MCComboLifetime") then
        continue
      end
      if equipped and equipped:GetAttribute("BlockKey") == "obsidian" then
        if snap.now >= (entry.manualUntil or -math.huge) or native.usingHeld() then
          continue
        end
      end
      local canBreak = crystal and elevated and selfSafe and native.canAct("attack")
      local canPlace = not crystal and not entry.finished and (not entry.spent or selfSafe) and (selfSafe or launch) and native.canAct("use", crystalItem.tool)
      if not canBreak and not canPlace then
        continue
      end
    end
    if not held then
      original = native.equipped()
    end
    if not native.equip(crystalItem.tool) then
      original = nil
      continue
    end
    held = crystalItem.tool
    comboMode, comboAt = launch and "dtap" or "crystal", snap.now
    -- Self exposure must block detonation itself, not only replacement placement.
    if crystal and elevated and selfSafe and native.canAct("attack") then
      if native.strike(hitPoint) then
        entry.spent = true
        if cfg("MCDTap") or (encounter and encounter.mode == "dtap") then
          entry.finished = true
        end
        acted = true
      end
    end
    if not crystal and not entry.finished and (not entry.spent or selfSafe) and native.canAct("use") then
      if native.action("use", top - Vector3.new(0, 0.03, 0)) then
        entry.spent, entry.untilAt = true, snap.now + 0.65
        remember(target.character, comboMode, snap.now + cfg("MCComboLifetime"))
        acted = true
      end
    end
    if acted then
      lastPulse = snap.now
      return true, target
    end
    if switching then
      -- A rejected action may restore the previous non-block item only.
      native.restore(original, held)
      Explosives.release()
    elseif crystal and elevated and selfSafe and snap.now - lastPulse <= 0.1 then
      return true, target
    end
  end
  if snap.now - lastPulse > 0.1 then
    Explosives.release()
  end
  return acted
end
function Explosives.resumeBase(snap, target, cfg)
  -- In CPvP an established duel can start a placement session even without a previous base.
  if not manualOverride and cfg("MCCrystal") and cfg("MCCrystalAutoCombo") and target
    and target.engaged and target.character.Parent and target.humanoid.Health > 0
    and (not encounter or encounter.character ~= target.character or snap.now >= encounter.untilAt) then
    remember(target.character, cfg("MCDTap") and "dtap" or "crystal", snap.now + cfg("MCComboLifetime"))
  end
  if manualOverride or not encounter or snap.now >= encounter.untilAt or not target or target.character ~= encounter.character then
    return nil
  end
  if not cfg("MCCrystal") and not cfg("MCDTap") then
    return nil
  end
  if not target.character.Parent or target.humanoid.Health <= 0 or target.distance > 19.2 then
    return nil
  end
  local crystalItem = native.find("EndCrystal", true)
  if not crystalItem then
    return nil
  end
  local function useful(s, position, planned)
    local top = position + Vector3.new(0, 1.6, 0)
    local current = target.root.Position
    local predicted = current + target.root.AssemblyLinearVelocity * math.clamp(s.ping or 0.05, 0.03, 0.12)
    local airborne = target.humanoid.FloorMaterial == Enum.Material.Air
    local function opportunity(point)
      local delta = point - top
      local flat = Vector3.new(delta.X, 0, delta.Z)
      if flat.Magnitude > 6.4 or delta.Y < (airborne and 3.68 or -0.32) or delta.Y > 13.6 then
        return 0
      end
      return geometry.damage(s, target.character, top, 6, planned and position or nil, point)
    end
    if (top - s.eye).Magnitude > 14.4 then
      return nil
    end
    local low, high = top - Vector3.new(3.2, 0, 3.2), top + Vector3.new(3.2, 6.4, 3.2)
    local aim = Vector3.new(math.clamp(s.eye.X, low.X + 0.05, high.X - 0.05), math.clamp(s.eye.Y, low.Y + 0.05, high.Y - 0.05), math.clamp(s.eye.Z, low.Z + 0.05, high.Z - 0.05))
    local direction = aim - s.eye
    local melee = native.data().geometry
    if direction.Magnitude < 0.01 or not melee or not melee.Box or not melee.Box(s.eye, direction.Unit, low, high, native.stats(crystalItem.tool).reach) then
      return nil
    end
    local damage = math.max(opportunity(current), opportunity(predicted))
    if damage <= 0 then
      return nil
    end
    local selfDamage = geometry.damage(s, s.character, top, 6, planned and position or nil)
    if airborne and selfDamage > 0 then
      return nil
    end
    return damage - selfDamage * 0.25 - (predicted - top).Magnitude * 0.1
  end
  -- Reuse one viable base; select only one new cell when no existing base works.
  local bestBlock, bestScore
  for _, block in ipairs(blocks(snap)) do
    if blockKey(block) == "obsidian" then
      local value = useful(snap, block.Position, false)
      if value and (not bestScore or value > bestScore) then
        bestBlock, bestScore = block, value
      end
    end
  end
  if bestBlock then
    state(bestBlock).manualUntil = encounter.untilAt
    target.manualCombo = true
    return nil
  end
  if snap.now - lastBase < 0.08 then
    return nil
  end
  local item = native.find("obsidian", true)
  if not item then
    return nil
  end
  local predicted = target.root.Position + target.root.AssemblyLinearVelocity * math.clamp(snap.ping or 0.05, 0.03, 0.12)
  local center = geometry.snap(predicted)
  local planned, score
  -- Raycast each column independently so the target's height and ledges matter.
  for x = -1, 1 do
    for z = -1, 1 do
      local column = Vector3.new(center.X + x * 3.2, predicted.Y + 1, center.Z + z * 3.2)
      local ground = native.raycast(column, Vector3.new(0, -17, 0), { target.character })
      if ground and ground.Normal.Y > 0.99 then
        local placement = geometry.placement(snap, ground.Position + Vector3.new(0, 1.6, 0))
        local value = placement and useful(snap, placement.cell, true)
        if value and (not score or value > score) then
          planned, score = placement, value
        end
      end
    end
  end
  if not planned then
    return nil
  end
  local session = encounter
  local function placedBase(s)
    for _, block in ipairs(blocks(s)) do
      if blockKey(block) == "obsidian" and (block.Position - planned.cell).Magnitude < 0.2 then
        return block
      end
    end
    return nil
  end
  return {
    id = "crystal_follow_base",
    feature = cfg("MCDTap") and "MCDTap" or "MCCrystal",
    target = target.character,
    priority = 76,
    native = "place",
    tool = item.tool,
    delay = 0,
    timeout = 0.65,
    repeatFast = false,
    point = function() return planned.point end,
    valid = function(s)
      return encounter == session
        and not manualOverride
        and s.now < session.untilAt
        and target.humanoid.Health > 0
        and useful(s, planned.cell, true) ~= nil
        and geometry.cellFree(s, planned.cell)
    end,
    before = function(s) lastBase = s.now end,
    confirm = function(s) return placedBase(s) ~= nil end,
    success = function(s)
      local block = placedBase(s)
      if block and encounter == session then
        state(block).manualUntil = session.untilAt
        target.manualCombo = true
      end
    end,
  }
end
function Explosives.defense() return nil end
function Explosives.propose(snap, _, cfg, targets)
  if not cfg("MCAnchor") then
    return nil
  end
  targets = targets or {}
  for _, block in ipairs(blocks(snap)) do
    if blockKey(block) ~= "respawn_anchor" or (block.Position - snap.eye).Magnitude > 14.4 then
      continue
    end
    local pos = block.Position
    local victim = candidate(snap, targets, pos, 5)
    if not victim then
      continue
    end
    comboMode, comboAt = "anchor", snap.now
    templates[block] = { cell = pos, time = snap.now, target = victim.character }
    local charged = (tonumber(block:GetAttribute("AnchorCharges")) or 0) > 0
    local tool = not charged and native.find("Glowstone", true)
    if not charged and not tool then
      continue
    end
    -- Glowstone uses ItemAction; detonation uses RespawnAnchor and any non-glowstone hotbar item.
    if charged then
      tool = native.find("sword", true) or native.find("EndCrystal", true) or native.find("Totem", true)
      if not tool then
        for _, item in ipairs(native.items()) do
          if item.slot and item.slot <= 9 and item.class ~= "Glowstone" then
            tool = item
            break
          end
        end
      end
      if not tool then
        continue
      end
    end
    return {
      target = victim.character,
      id = charged and "anchor_detonate" or "anchor_charge",
      feature = "MCAnchor",
      priority = charged and 82 or 80,
      tool = tool.tool,
      delay = 0,
      timeout = 0.25,
      cooldown = charged and "anchor" or "use",
      point = function() return pos + Vector3.new(0, 1.4, 0) end,
      valid = function(s) return block.Parent ~= nil and candidate(s, targets, pos, 5) ~= nil end,
      perform = function()
        if charged then
          return native.anchor(pos + Vector3.new(0, 1.4, 0))
        end
        return native.action("use", pos + Vector3.new(0, 1.4, 0))
      end,
      confirm = function() return block.Parent == nil or (not charged and (tonumber(block:GetAttribute("AnchorCharges")) or 0) > 0) end,
    }
  end
  if cfg("MCAnchorRepeat") then
    local item = native.find("respawn_anchor", true) or native.find("RespawnAnchor", true)
    for block, template in pairs(templates) do
      if snap.now - template.time > cfg("MCComboLifetime") then
        templates[block] = nil
      elseif item and not block.Parent and candidate(snap, targets, template.cell, 5) then
        local placement = geometry.placement(snap, template.cell)
        if placement then
          return {
            id = "anchor_repeat",
            feature = "MCAnchor",
            priority = 70,
            tool = item.tool,
            native = "place",
            delay = 0,
            point = function() return placement.point end,
            valid = function(s) return geometry.cellFree(s, template.cell) and candidate(s, targets, template.cell, 5) ~= nil end,
            confirm = function(s) return not geometry.cellFree(s, template.cell) end,
          }
        end
      end
    end
  end
  return nil
end
Explosives.__contract = {
  requires = { Native = "mcpnative", Geometry = "mcpgeometry" },
  provides = {
    "setup",
    "reset",
    "mark",
    "mode",
    "clearCombo",
    "defense",
    "propose",
    "observe",
    "needsStrike",
    "struck",
    "pulse",
    "release",
    "follow",
    "resumeBase",
  },
}
return Explosives
