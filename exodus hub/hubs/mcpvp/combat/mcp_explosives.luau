-- [[ mcpexplosives ]]
--!optimize 2
local Explosives = {}
local native, geometry
local seen, scripted = {}, {}
local templates = {}
local dtapHit, dtapBase, comboMode, comboTarget = -math.huge, nil, nil, nil
local comboAt = -math.huge
local function cellKey(point) return string.format("%.1f:%.1f:%.1f", point.X, point.Y, point.Z) end
function Explosives.setup(deps)
  native, geometry = deps.Native, deps.Geometry
  return true
end
function Explosives.reset()
  seen, scripted, templates = {}, {}, {}
  dtapHit, dtapBase, comboMode, comboTarget = -math.huge, nil, nil, nil
end
function Explosives.mark(object, time) seen[object] = time end
function Explosives.mode() return os.clock() - comboAt < 2.5 and comboMode or nil end
function Explosives.clearCombo()
  comboMode, dtapBase, templates = nil, nil, {}
end
local function item(class) return native.find(class, true) end
local function blocks(snap)
  local folder = snap.world:FindFirstChild("PlayerBlocks")
  local list = {}
  if folder then
    for _, block in ipairs(folder:GetChildren()) do
      if block:IsA("BasePart") and (block.Position - snap.root.Position).Magnitude < 22 then
        list[#list + 1] = block
      end
    end
  end
  table.sort(list, function(a, b) return (a.Position - snap.root.Position).Magnitude < (b.Position - snap.root.Position).Magnitude end)
  return list
end
local function existing(snap, cell, key)
  for _, block in ipairs(blocks(snap)) do
    if block:GetAttribute("BlockKey") == key and (block.Position - cell).Magnitude < 0.2 then
      return block
    end
  end
  return nil
end
local function buildJob(snap, placement, tool, id, feature, priority, cfg)
  local cell, key = placement.cell, tool.block
  return {
    id = id,
    feature = feature,
    priority = priority,
    tool = tool.tool,
    native = "place",
    timeout = 0.9,
    delay = 0.08,
    point = function() return placement.point end,
    valid = function(s, t)
      if not geometry.cellFree(s, cell) or (cell - s.eye).Magnitude > 14.4 then
        return false
      end
      if id == "dtap_base" then
        return t and geometry.evaluate(s, t, cell + Vector3.new(0, 1.6, 0), 6, cfg, cfg("MCCrystalDamage"))
      end
      if id == "anchor_repeat" or id == "anchor_auto" then
        return t and geometry.evaluate(s, t, cell, 5, cfg, cfg("MCAnchorDamage"))
      end
      return true
    end,
    before = function(s) scripted[cellKey(cell)] = s.now end,
    confirm = function(s) return existing(s, cell, key) ~= nil end,
  }
end
local function protectiveItem(cfg)
  for _, choice in ipairs({ { cfg("MCProtectionObsidian"), "obsidian" }, { cfg("MCProtectionGlowstone"), "Glowstone" } }) do
    local tool = choice[1] and item(choice[2])
    if tool and tool.block and tool.tool:GetAttribute("Placeable") == true then
      return tool
    end
  end
  return nil
end
local function protect(snap, point, cfg, id, feature)
  local tool = protectiveItem(cfg)
  local placement = tool and geometry.protection(snap, point)
  if placement then
    return buildJob(snap, placement, tool, id, feature, 90, cfg)
  end
  return nil
end
function Explosives.defense(snap, cfg)
  if not cfg("MCDefense") then
    return nil
  end
  for _, block in ipairs(blocks(snap)) do
    if
      block:GetAttribute("BlockKey") == "respawn_anchor"
      and (tonumber(block:GetAttribute("AnchorCharges")) or 0) > 0
      and geometry.damage(snap, snap.character, block.Position, 5) >= cfg("MCDefenseDamage")
    then
      local job = protect(snap, block.Position, cfg, "defense_anchor", "MCDefense")
      if job then
        return job
      end
    end
  end
  local crystals = snap.world:FindFirstChild("EndCrystals")
  if crystals then
    for _, crystal in ipairs(crystals:GetChildren()) do
      local point = geometry.blastPosition(crystal)
      if point and (point - snap.root.Position).Magnitude < 20 and geometry.damage(snap, snap.character, point, 6) >= cfg("MCDefenseDamage") then
        local job = protect(snap, point, cfg, "defense_crystal", "MCDefense")
        if job then
          return job
        end
      end
    end
  end
  return nil
end
function Explosives.propose(snap, target, cfg)
  if comboTarget and comboTarget ~= target.character then
    Explosives.clearCombo()
  end
  comboTarget = target.character
  local nearby = blocks(snap)
  local crystals = snap.world:FindFirstChild("EndCrystals")
  local activeCrystal
  if crystals then
    local closest = math.huge
    for _, crystal in ipairs(crystals:GetChildren()) do
      local point = geometry.blastPosition(crystal)
      if point and (point - target.root.Position).Magnitude < cfg("MCCrystalRadius") * 3.2 and (point - snap.eye).Magnitude < 9.6 then
        local distance = (point - target.root.Position).Magnitude
        if distance < closest then
          activeCrystal, closest = crystal, distance
        end
      end
    end
  end
  local bases, anchors = {}, {}
  for _, block in ipairs(nearby) do
    local key = block:GetAttribute("BlockKey")
    local time = seen[block] or -math.huge
    local own = block:GetAttribute("Builder") == snap.player.UserId
    local scriptTime = scripted[cellKey(block.Position)] or -math.huge
    local manual = own and time > -math.huge and math.abs(time - scriptTime) > 2 and snap.now - time < cfg("MCComboLifetime")
    if key == "obsidian" and (cfg("MCCrystal") or cfg("MCDTap")) then
      local isDTap = dtapBase and (dtapBase - block.Position).Magnitude < 0.2 and snap.now - dtapHit < cfg("MCComboLifetime")
      if (cfg("MCCrystal") and (manual or not cfg("MCCrystalManual"))) or isDTap then
        bases[#bases + 1] = { block = block, dtap = isDTap }
      end
    elseif key == "respawn_anchor" and cfg("MCAnchor") then
      if manual then
        templates[cellKey(block.Position)] = { cell = block.Position, time = time }
      end
      if manual or (cfg("MCAnchorAuto") and target.engaged) or templates[cellKey(block.Position)] then
        anchors[#anchors + 1] = block
      end
    end
  end
  if cfg("MCDTap") and target.engaged and target.lastHit > dtapHit and snap.now - target.lastHit < cfg("MCDTapWindow") then
    local obsidian = item("obsidian")
    -- Place toward the opponent only after observed sword damage, never on a mere attack attempt.
    local flat = target.root.Position - snap.root.Position
    flat = Vector3.new(flat.X, 0, flat.Z)
    if obsidian and flat.Magnitude > 1 and target.distance < 12 then
      local desired = snap.root.Position + flat.Unit * 3.5 - Vector3.new(0, 2.4, 0)
      local placement = geometry.placement(snap, desired)
      if placement then
        local point = placement.cell + Vector3.new(0, 1.6, 0)
        local useful = geometry.evaluate(snap, target, point, 6, cfg, cfg("MCCrystalDamage"))
        if useful then
          local job = buildJob(snap, placement, obsidian, "dtap_base", "MCDTap", 72, cfg)
          job.success = function(s)
            dtapBase, dtapHit, comboMode = placement.cell, target.lastHit, "dtap"
          end
          return job
        end
      end
    end
  end
  for _, base in ipairs(bases) do
    local top = base.block.Position + Vector3.new(0, 1.6, 0)
    if target.root.Position.Y < top.Y + 0.5 or top.Y < snap.root.Position.Y - 4.2 then
      continue
    end
    if (target.root.Position - top).Magnitude > cfg("MCCrystalRadius") * 3.2 then
      continue
    end
    local useful = geometry.evaluate(snap, target, top, 6, cfg, cfg("MCCrystalDamage"))
    if not useful then
      continue
    end
    comboMode = base.dtap and "dtap" or "crystal"
    comboAt = snap.now
    local feature = base.dtap and "MCDTap" or "MCCrystal"
    if activeCrystal then
      local crystalPoint = geometry.blastPosition(activeCrystal)
      if (crystalPoint - top).Magnitude < 4 then
        local crystal = activeCrystal
        return {
          id = "crystal_break",
          feature = feature,
          priority = 78,
          tool = snap.equipped,
          native = "attack",
          needsEquip = false,
          delay = 0.04,
          timeout = 0.8,
          point = function() return crystalPoint + Vector3.new(0, 1.5, 0) end,
          valid = function(s, t)
            return crystal.Parent ~= nil
              and (t.root.Position - crystalPoint).Magnitude <= cfg("MCCrystalRadius") * 3.2
              and geometry.evaluate(s, t, crystalPoint, 6, cfg, cfg("MCCrystalDamage"))
          end,
          confirm = function() return crystal.Parent == nil end,
          success = function(s)
            seen[base.block] = s.now
            if base.dtap then
              dtapHit = s.now
            end
          end,
        }
      end
    else
      local crystalItem = item("EndCrystal")
      local clear = geometry.cellFree(snap, top + Vector3.new(0, 1.6, 0))
      if crystalItem and clear and (top - snap.eye).Magnitude <= 14.4 then
        return {
          id = "crystal_place",
          feature = feature,
          priority = 75,
          tool = crystalItem.tool,
          native = "use",
          delay = 0.04,
          timeout = 0.9,
          point = function() return top - Vector3.new(0, 0.03, 0) end,
          valid = function(s, t)
            return base.block.Parent ~= nil
              and (t.root.Position - top).Magnitude <= cfg("MCCrystalRadius") * 3.2
              and geometry.evaluate(s, t, top, 6, cfg, cfg("MCCrystalDamage"))
          end,
          confirm = function(s)
            local folder = s.world:FindFirstChild("EndCrystals")
            if folder then
              for _, obj in ipairs(folder:GetChildren()) do
                local pos = geometry.blastPosition(obj)
                if pos and (pos - top).Magnitude < 2 then
                  return true
                end
              end
            end
            return false
          end,
        }
      end
    end
  end
  if cfg("MCAnchor") then
    for _, anchor in ipairs(anchors) do
      local pos = anchor.Position
      if (target.root.Position - pos).Magnitude > cfg("MCAnchorRadius") * 3.2 or (snap.eye - pos).Magnitude > 14.4 then
        continue
      end
      local useful, selfDamage, targetDamage = geometry.evaluate(snap, target, pos, 5, cfg, cfg("MCAnchorDamage"))
      local charges = tonumber(anchor:GetAttribute("AnchorCharges")) or 0
      if not useful and targetDamage < cfg("MCAnchorDamage") then
        continue
      end
      comboMode = "anchor"
      comboAt = snap.now
      local required = cfg("MCAnchorAlwaysProtect") or not useful
      if required then
        if cfg("MCAnchorProtection") then
          local job = protect(snap, pos, cfg, "anchor_protection", "MCAnchor")
          if job then
            return job
          end
        end
        -- Refuse detonation when protection is unavailable or has not made the position safe.
        if not useful then
          continue
        end
        if cfg("MCAnchorAlwaysProtect") and selfDamage > cfg("MCMaxSelfDamage") / 2 then
          continue
        end
      end
      if charges < 1 then
        local glow = item("Glowstone")
        if glow then
          return {
            id = "anchor_charge",
            feature = "MCAnchor",
            priority = 74,
            tool = glow.tool,
            native = "use",
            delay = 0.04,
            timeout = 0.9,
            point = function() return pos + Vector3.new(0, 1.4, 0) end,
            valid = function(s, t)
              return anchor.Parent ~= nil
                and (tonumber(anchor:GetAttribute("AnchorCharges")) or 0) == 0
                and (t.root.Position - pos).Magnitude <= cfg("MCAnchorRadius") * 3.2
            end,
            confirm = function() return anchor.Parent == nil or (tonumber(anchor:GetAttribute("AnchorCharges")) or 0) > 0 end,
          }
        end
      elseif useful then
        local sword = item("sword")
        if sword then
          return {
            id = "anchor_detonate",
            cooldown = "anchor",
            feature = "MCAnchor",
            priority = 77,
            tool = sword.tool,
            delay = 0.04,
            timeout = 0.9,
            point = function() return pos + Vector3.new(0, 1.4, 0) end,
            perform = function() return native.anchor(pos + Vector3.new(0, 1.4, 0)) end,
            valid = function(s, t)
              return anchor.Parent ~= nil
                and (tonumber(anchor:GetAttribute("AnchorCharges")) or 0) > 0
                and (t.root.Position - pos).Magnitude <= cfg("MCAnchorRadius") * 3.2
                and geometry.evaluate(s, t, pos, 5, cfg, cfg("MCAnchorDamage"))
            end,
            confirm = function() return anchor.Parent == nil end,
            success = function(s)
              local template = templates[cellKey(pos)]
              if template then
                template.time = s.now
              end
            end,
          }
        end
      end
    end
    local anchorItem = item("respawn_anchor") or item("RespawnAnchor")
    if anchorItem then
      for key, template in pairs(templates) do
        if snap.now - template.time > cfg("MCComboLifetime") or (target.root.Position - template.cell).Magnitude > cfg("MCAnchorRadius") * 3.2 then
          templates[key] = nil
          continue
        end
        if cfg("MCAnchorRepeat") and not existing(snap, template.cell, "respawn_anchor") then
          local placement = geometry.placement(snap, template.cell)
          if placement and geometry.evaluate(snap, target, template.cell, 5, cfg, cfg("MCAnchorDamage")) then
            return buildJob(snap, placement, anchorItem, "anchor_repeat", "MCAnchor", 70, cfg)
          end
        end
      end
      if cfg("MCAnchorAuto") and target.engaged then
        local delta = target.root.Position - snap.root.Position
        local flat = Vector3.new(delta.X, 0, delta.Z)
        if flat.Magnitude > 1 and target.distance < 12 then
          local placement = geometry.placement(snap, snap.root.Position + flat.Unit * 4.5 - Vector3.new(0, 2.4, 0))
          if placement and geometry.evaluate(snap, target, placement.cell, 5, cfg, cfg("MCAnchorDamage")) then
            return buildJob(snap, placement, anchorItem, "anchor_auto", "MCAnchor", 70, cfg)
          end
        end
      end
    end
  end
  return nil
end
Explosives.__contract =
  { requires = { Native = "mcpnative", Geometry = "mcpgeometry" }, provides = { "setup", "reset", "mark", "mode", "clearCombo", "defense", "propose" } }
return Explosives
