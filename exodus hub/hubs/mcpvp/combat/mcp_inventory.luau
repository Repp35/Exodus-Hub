-- [[ mcpinventory ]]
--!optimize 2
local Inventory = {}
local native
local missingSince, remembered, pending = nil, {}, nil
local character
local wasCombat, lastCombat, quietUntil = false, -math.huge, -math.huge
local previousHealth, threatenedUntil = nil, -math.huge
function Inventory.setup(deps)
  native = deps.Native
  return true
end
function Inventory.reset()
  missingSince, remembered, pending, character = nil, {}, nil, nil
  wasCombat, lastCombat, quietUntil = false, -math.huge, -math.huge
  previousHealth, threatenedUntil = nil, -math.huge
end
local function emptySlot()
  local slots = native.slots()
  if not slots then
    return nil
  end
  for slot = 1, 9 do
    if not slots[slot] then
      return slot
    end
  end
  return nil
end
function Inventory.propose(snap, target, cfg)
  if character ~= snap.character then
    Inventory.reset()
    character = snap.character
  end
  if previousHealth and snap.humanoid.Health < previousHealth then
    threatenedUntil = snap.now + 3
  end
  previousHealth = snap.humanoid.Health
  local combat = (target ~= nil and target.engaged == true) or snap.now < threatenedUntil
  if combat then
    lastCombat = snap.now
  elseif wasCombat then
    quietUntil = snap.now + cfg("MCApplePostCombatDelay")
  end
  wasCombat = combat
  local function appleAllowed()
    if wasCombat then
      return cfg("MCAppleCombat")
    end
    return snap.now >= quietUntil and snap.now - lastCombat >= cfg("MCApplePostCombatDelay")
  end
  local pressure = target and target.engaged and math.clamp(1 - target.distance / 25, 0, 1) or 0
  pressure = math.max(pressure, 1 - snap.humanoid.Health / snap.humanoid.MaxHealth)
  if cfg("MCTotem") and snap.character:GetAttribute("OffhandItem") ~= "totem" then
    if not missingSince then
      local minimum, maximum = cfg("MCReactionMin"), cfg("MCReactionMax")
      missingSince = snap.now + (maximum + (minimum - maximum) * pressure) * (0.85 + math.random() * 0.3)
    end
    if snap.now >= missingSince and not pending then
      local item = native.find("Totem", true) or native.find("Totem", false)
      if item and item.slot then
        local owner = snap.character
        local inHotbar = item.slot ~= nil and item.slot <= 9
        local job = {
          id = "totem",
          feature = "MCTotem",
          priority = 100,
          mode = "offhand",
          tool = item.tool,
          timeout = 2,
          delay = 0,
          needsEquip = inHotbar,
          inventory = not inHotbar,
        }
        job.perform = function()
          pending = job
          native.offhand(item.tool, function(ok)
            if pending == job then
              pending = nil
            end
            job.result = ok and snap.player.Character == owner
          end)
          return true
        end
        job.confirm = function(s) return s.character:GetAttribute("OffhandItem") == "totem" end
        job.success = function()
          if inHotbar and job.original then
            native.equip(job.original)
          end
        end
        return job
      end
    end
  else
    missingSince = nil
  end
  if pending then
    return nil
  end
  local slots = native.slots()
  if not slots then
    return nil
  end
  if cfg("MCTotem") and cfg("MCTotemRefill") and snap.character:GetAttribute("OffhandItem") == "totem" then
    local count, inventory = 0, nil
    for _, item in ipairs(native.items()) do
      if item.class == "Totem" then
        if item.slot and item.slot <= 9 then
          count += 1
        else
          inventory = item
        end
      end
    end
    local slot = emptySlot()
    if count < cfg("MCTotemSlots") and inventory and slot then
      return {
        id = "totem_refill",
        feature = "MCTotem",
        priority = 30,
        mode = "inventory",
        inventory = true,
        needsEquip = false,
        delay = 0.15 + (1 - pressure) * 0.15,
        perform = function() return native.move(inventory.tool, slot) end,
        confirm = function() return slots[slot] == inventory.tool end,
      }
    end
  end
  if cfg("MCPotion") then
    for _, effect in ipairs({ "strength", "speed" }) do
      local enabled = effect == "strength" and cfg("MCPotionStrength") or effect == "speed" and cfg("MCPotionSpeed")
      if not enabled then
        continue
      end
      local class = effect == "strength" and "StrengthPotion" or "SpeedPotion"
      local item = native.find(class, true)
      if item then
        remembered[class] = item.slot
      end
      local expiry = tonumber(snap.character:GetAttribute("Effect_" .. effect)) or 0
      if expiry > snap.server then
        continue
      end
      if not item and remembered[class] and cfg("MCPotionRefill") and not slots[remembered[class]] then
        local spare = native.find(class, false)
        if spare then
          local destination = remembered[class]
          return {
            id = "potion_refill",
            feature = "MCPotion",
            priority = 35,
            mode = "inventory",
            inventory = true,
            needsEquip = false,
            delay = 0.18,
            perform = function() return native.move(spare.tool, destination) end,
            confirm = function() return slots[destination] == spare.tool end,
          }
        end
      end
      if
        item
        and (not target or not target.engaged or cfg("MCPotionCombat"))
        and snap.humanoid.FloorMaterial ~= Enum.Material.Air
        and math.abs(snap.root.AssemblyLinearVelocity.Y) < 5
      then
        local before = item.count
        return {
          id = "potion_" .. effect,
          feature = "MCPotion",
          priority = 60,
          tool = item.tool,
          native = "use",
          delay = 0.12 + (1 - pressure) * 0.12,
          timeout = cfg("MCPotionRetry"),
          point = function(s) return s.eye + Vector3.new(0, -8, 0) end,
          valid = function(s)
            return s.humanoid.FloorMaterial ~= Enum.Material.Air and (tonumber(s.character:GetAttribute("Effect_" .. effect)) or 0) <= s.server
          end,
          confirm = function(s)
            return (tonumber(s.character:GetAttribute("Effect_" .. effect)) or 0) > s.server
              or not item.tool.Parent
              or (tonumber(item.tool:GetAttribute("Count")) or 0) < before
          end,
        }
      end
    end
  end
  if
    cfg("MCApple")
    and snap.humanoid.Health / snap.humanoid.MaxHealth < cfg("MCAppleHealth") / 100
    and appleAllowed()
    and not snap.character:GetAttribute("EatingApple")
  then
    local item = native.find("GoldenApple", true)
    if not item then
      for _, candidate in ipairs(native.items()) do
        if candidate.tool.Name == "Gold Apple" and candidate.slot and candidate.slot <= 9 then
          item = candidate
          break
        end
      end
    end
    if item then
      local before = item.count
      return {
        id = "apple",
        feature = "MCApple",
        priority = 40,
        tool = item.tool,
        delay = 0.2,
        timeout = 3,
        valid = function(s)
          return (wasCombat and cfg("MCAppleCombat")) or (not wasCombat and s.now >= quietUntil and s.now - lastCombat >= cfg("MCApplePostCombatDelay"))
        end,
        perform = function() return native.apple(true) end,
        cancel = function() native.apple(false) end,
        confirm = function() return not item.tool.Parent or (tonumber(item.tool:GetAttribute("Count")) or 0) < before end,
      }
    end
  end
  return nil
end
Inventory.__contract = { requires = { Native = "mcpnative" }, provides = { "setup", "reset", "propose" } }
return Inventory
