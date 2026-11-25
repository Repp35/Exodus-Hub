-- [[ mcpexplosives ]]
--!optimize 2
local Explosives = {}
local native, geometry
local opportunities, templates = {}, {}
local comboMode, comboAt = nil, -math.huge
local original, held, lastPulse = nil, nil, -math.huge
local blockSnapshot, blockCache
local placed = {}
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
    native.restore(original, held)
  end
  original, held = nil, nil
end
function Explosives.reset()
  Explosives.release()
  opportunities, templates, placed = {}, {}, {}
  blockSnapshot, blockCache = nil, nil
  comboMode, comboAt, lastPulse = nil, -math.huge, -math.huge
end
function Explosives.mark(object, time)
  placed[object] = time
  if time == nil then
    opportunities[object] = nil
  end
end
function Explosives.mode() return os.clock() - comboAt < 2.5 and comboMode or nil end
function Explosives.clearCombo() Explosives.reset() end
function Explosives.observe(snap, targets, cfg)
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
      if
        target
        and (placed[block] or -math.huge) > 0
        and block:GetAttribute("Builder") == snap.player.UserId
        and snap.now - placed[block] < cfg("MCComboLifetime")
        and (target.root.Position - top).Magnitude <= 12.8
      then
        state(block).manualUntil = placed[block] + cfg("MCComboLifetime")
        target.manualCombo = true
      end
      if target then
        chosen = chosen or target
      end
    end
  end
  return chosen
end
function Explosives.needsStrike(snap, target, cfg)
  if not cfg("MCDTap") or not target or not native.find("EndCrystal", true) then
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
  if not cfg("MCDTap") then
    return
  end
  for _, block in ipairs(blocks(snap)) do
    if blockKey(block) == "obsidian" and snap.now < (state(block).manualUntil or -math.huge) then
      local top = block.Position + Vector3.new(0, 1.6, 0)
      if (top - snap.eye).Magnitude <= 14.4 and (target.root.Position - top).Magnitude <= 12.8 then
        local entry = state(block)
        entry.strikeAt, entry.target = snap.now, target.character
        entry.spent = false
        comboMode, comboAt = "dtap", snap.now
      end
    end
  end
end
function Explosives.pulse(snap, targets, cfg)
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
    -- Any exposed player above this base keeps the opportunity open.
    for _, other in ipairs(targets) do
      if other.humanoid.Health > 0 and above(other, top) and geometry.damage(snap, other.character, top, 6) > 0 then
        target, elevated = other, true
        break
      end
    end
    local launch = cfg("MCDTap") and snap.now - entry.strikeAt < cfg("MCDTapLaunchWindow")
    local continuous = (elevated or launch) and geometry.damage(snap, snap.character, top, 6) <= 0
    if not target and not launch then
      entry.spent = false
      continue
    end
    local crystal, point = crystalAt(snap, top)
    local finishing = snap.now < entry.untilAt
    if entry.spent and not continuous and not finishing then
      continue
    end
    if not held then
      original = native.equipped()
    end
    if not native.equip(crystalItem.tool) then
      continue
    end
    held = crystalItem.tool
    comboMode, comboAt = launch and "dtap" or "crystal", snap.now
    -- No confirmation stage: keep sending native use/attack attempts at their native rate.
    if (continuous or not entry.spent) and native.canAct("use") then
      if native.action("use", top - Vector3.new(0, 0.03, 0)) then
        entry.spent, entry.untilAt = true, snap.now + 0.65
        acted = true
      end
    end
    if (crystal or entry.untilAt > snap.now) and native.canAct("attack") then
      local hitPoint = (point or top) + Vector3.new(0, 3.2, 0)
      local delta = hitPoint - snap.eye
      local melee = native.data().geometry
      local reach = native.stats(held).reach
      local inReach = melee
        and melee.Box
        and delta.Magnitude > 0.01
        and melee.Box(snap.eye, delta.Unit, top - Vector3.new(3.2, 0, 3.2), top + Vector3.new(3.2, 6.4, 3.2), reach) ~= nil
      if inReach and native.strike(hitPoint) then
        entry.spent = true
        acted = true
      end
    end
    if continuous or finishing or acted then
      lastPulse = snap.now
      return true, target
    end
  end
  if snap.now - lastPulse > 0.1 then
    Explosives.release()
  end
  return acted
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
      timeout = 0.5,
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
  provides = { "setup", "reset", "mark", "mode", "clearCombo", "defense", "propose", "observe", "needsStrike", "struck", "pulse", "release" },
}
return Explosives
