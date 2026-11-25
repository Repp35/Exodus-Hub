-- [[ mcpexplosives ]]
--!optimize 2
local Explosives = {}
local native, geometry
local opportunities, templates = {}, {}
local comboMode, comboAt = nil, -math.huge
local original, held, lastPulse = nil, nil, -math.huge
local heldAuto = false
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
  local function add(block)
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
  if held then
    local obsidian = native.find("obsidian", true)
    if heldAuto and obsidian and native.equipped() == held then
      native.restore(obsidian.tool, held)
    else
      native.restore(original, held)
    end
  end
  original, held, heldAuto = nil, nil, false
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
  if manualOverride or not encounter or encounter.character ~= char or snap.now >= encounter.untilAt then
    return false
  end
  encounter.untilAt = snap.now + math.max(cfg("MCComboLifetime"), 12)
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
        entry.spent = false
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
    if blockKey(block) ~= "obsidian" then
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
    local launch = (cfg("MCDTap") or cfg("MCCrystal") and cfg("MCCrystalAutoCombo")) and snap.now - entry.strikeAt < cfg("MCDTapLaunchWindow")
    if target and not elevated and (target.root.Position - top).Magnitude > 12.8 then
      target = nil
    end
    if not target and launch then
      for _, other in ipairs(targets) do
        if other.humanoid.Health > 0 and (other.root.Position - top).Magnitude <= 12.8 then
          target = other
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
    if not held then
      original = native.equipped()
      heldAuto = original ~= crystalItem.tool
    end
    if not native.equip(crystalItem.tool) then
      original, heldAuto = nil, false
      continue
    end
    held = crystalItem.tool
    comboMode, comboAt = launch and "dtap" or "crystal", snap.now
    -- Self exposure must block detonation itself, not only replacement placement.
    local selfSafe = geometry.damage(snap, snap.character, point or top, 6) <= 0
    local broke = false
    if crystal and elevated and selfSafe and native.canAct("attack") then
      if native.strike(hitPoint) then
        entry.spent, broke = true, true
        acted = true
      end
    end
    if (not entry.spent or selfSafe) and (not crystal or broke) and native.canAct("use") then
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
    if crystal and snap.now - lastPulse <= 0.1 then
      return true, target
    end
  end
  if snap.now - lastPulse > 0.1 then
    Explosives.release()
  end
  return acted
end
function Explosives.resumeBase(snap, target, cfg)
  if
    not manualOverride
    and cfg("MCCrystal")
    and cfg("MCCrystalAutoCombo")
    and target
    and target.engaged
    and target.character.Parent
    and target.humanoid.Health > 0
  then
    remember(target.character, "crystal", snap.now + cfg("MCComboLifetime"))
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
  if not native.find("EndCrystal", true) then
    return nil
  end
  local function useful(s, position)
    local top = position + Vector3.new(0, 1.6, 0)
    local delta = target.root.Position - top
    local flat = Vector3.new(delta.X, 0, delta.Z)
    return (top - s.eye).Magnitude <= 14.4 and flat.Magnitude <= 6.4 and delta.Y >= -0.32 and delta.Y <= 10.4
  end
  for _, block in ipairs(blocks(snap)) do
    if blockKey(block) == "obsidian" and useful(snap, block.Position) then
      state(block).manualUntil = encounter.untilAt
      return nil
    end
  end
  if snap.now - lastBase < 0.35 then
    return nil
  end
  local item = native.find("obsidian", true)
  if not item then
    return nil
  end
  local ground = native.raycast(target.root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -16, 0), { target.character })
  if not ground or ground.Normal.Y < 0.99 then
    return nil
  end
  local delta = snap.root.Position - target.root.Position
  local flat = Vector3.new(delta.X, 0, delta.Z)
  if flat.Magnitude < 0.01 then
    return nil
  end
  local toward = flat.Unit * 3.2
  local side = Vector3.new(-toward.Z, 0, toward.X)
  local center = ground.Position + Vector3.new(0, 1.6, 0)
  local planned, score
  for _, offset in ipairs({ toward, toward * 2, side, -side, -toward }) do
    local placement = geometry.placement(snap, center + offset)
    if placement and useful(snap, placement.cell) then
      local predicted = target.root.Position + target.root.AssemblyLinearVelocity * math.min(0.2, snap.ping or 0)
      local value = (predicted - placement.cell).Magnitude + (snap.eye - placement.cell).Magnitude * 0.25
      if not score or value < score then
        planned, score = placement, value
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
    timeout = 0.5,
    point = function() return planned.point end,
    valid = function(s)
      return encounter == session
        and not manualOverride
        and s.now < session.untilAt
        and target.humanoid.Health > 0
        and useful(s, planned.cell)
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
