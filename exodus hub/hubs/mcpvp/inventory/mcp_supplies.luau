-- [[ mcpsupplies ]]
--!optimize 2
local Supplies = {}
local inventory, native, utils
local owner, layout, seen, potion, awaiting = nil, {}, {}, nil, {}
local effects = { { key = "MCAutoStrength", class = "StrengthPotion", effect = "strength" }, { key = "MCAutoSpeed", class = "SpeedPotion", effect = "speed" } }
local function enabled(key) return utils.getConfigValue(key) == true end
local function alive(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function identity(tool)
  return alive(tool) and tool.Name .. "|" .. tostring(tool:GetAttribute("ClassItem")) .. "|" .. tostring(tool:GetAttribute("BlockKey")) or nil
end
local function destination(slots, wanted)
  -- An exhausted stack still owns its slot. Backup items cannot claim it.
  for slot = 1, 9 do
    if not alive(slots[slot]) and wanted and layout[slot] == wanted then
      return slot
    end
  end
  for slot = 1, 9 do
    if not alive(slots[slot]) and not layout[slot] then
      return slot
    end
  end
  return nil
end
function Supplies.setup(deps)
  inventory, native, utils = deps.Inventory, deps.Native, deps.Utils
  return true
end
function Supplies.reset()
  local snap = native.snapshot()
  if potion and snap and potion.character == snap.character then
    return
  end
  owner, layout, seen, potion, awaiting = nil, {}, {}, nil, {}
  inventory.reset()
end
function Supplies.busy() return inventory.busy() or potion ~= nil end
local function finish(snap)
  if not inventory.close() then
    return
  end
  if not native.restore(snap, potion.previous) then
    return
  end
  awaiting[potion.effect] = snap.now + (potion.confirmed and 0.5 or 1)
  potion = nil
end
local function servicePotion(snap, slots)
  if potion.character ~= snap.character then
    potion = nil
    return
  end
  if potion.phase == "confirm" then
    local state = native.useState(snap, potion, potion.effect)
    if state == nil then
      return
    end
    potion.confirmed, potion.phase = state, "cleanup"
  end
  if potion.phase == "cleanup" then
    potion.cleanupAt = potion.cleanupAt or snap.now
    if snap.now - potion.cleanupAt > 3 then
      inventory.close(true)
      native.restore(snap, potion.previous)
      awaiting[potion.effect] = snap.now + 2
      potion = nil
      return
    end
    finish(snap)
    return
  end
  local inHotbar = false
  for slot = 1, 9 do
    if slots[slot] == potion.tool then
      inHotbar = true
      break
    end
  end
  if snap.now - potion.at > 4 or not alive(potion.tool) or not inHotbar then
    potion.phase = "cleanup"
    return
  end
  if not inventory.close() or native.blocked(snap) then
    return
  end
  if native.equip(snap, potion.tool) then
    potion.count, potion.requestAt = tonumber(potion.tool:GetAttribute("Count")) or 1, snap.now
    if native.use(snap, potion.tool, Vector3.new(0, -1, 0)) then
      potion.phase = "confirm"
    end
  end
end
local function refill(snap, slots)
  for slot = 1, 9 do
    if not alive(slots[slot]) and layout[slot] then
      for from = 10, 36 do
        local tool = slots[from]
        if identity(tool) == layout[slot] then
          if not inventory.move(snap, tool, from, slot) then
            return false
          end
          break
        end
      end
    end
  end
  return true
end
local function beginPotion(snap, slots, effect, tool)
  potion = {
    character = snap.character,
    tool = tool,
    effect = effect.effect,
    previous = snap.tool,
    at = snap.now,
    phase = "use",
  }
  servicePotion(snap, slots)
  return true
end
function Supplies.step(snap, allowBackground)
  if owner ~= snap.character then
    owner, layout, seen, potion, awaiting = snap.character, {}, {}, nil, {}
    inventory.reset()
  end
  inventory.step(snap)
  local slots = inventory.slots()
  if not slots then
    if potion and snap.now - potion.at > 4 then
      inventory.close(true)
      native.restore(snap, potion.previous)
      potion = nil
    end
    return
  end
  if potion then
    servicePotion(snap, slots)
    return
  end
  if allowBackground == false and not inventory.busy() or snap.character:GetAttribute("EatingApple") then
    return
  end
  for slot = 1, 9 do
    local tool = slots[slot]
    if alive(tool) then
      layout[slot] = identity(tool)
    elseif alive(seen[slot]) then
      -- A live stack moved by the player is not an exhausted stack.
      layout[slot] = nil
    end
    seen[slot] = alive(tool) and tool or nil
  end
  if enabled("MCAutoTotem") and snap.character:GetAttribute("OffhandItem") ~= "totem" and inventory.find("Totem") then
    if inventory.totem(snap) == false then
      return
    end
  end
  -- All depleted items are restored before considering an extra hotbar totem.
  if enabled("MCAutoRefill") and not refill(snap, slots) then
    return
  end
  if allowBackground ~= false and enabled("MCAutoPotion") then
    for _, effect in ipairs(effects) do
      if
        enabled(effect.key)
        and snap.now >= (awaiting[effect.effect] or 0)
        and (tonumber(snap.character:GetAttribute("Effect_" .. effect.effect)) or 0) <= workspace:GetServerTimeNow()
      then
        local tool = inventory.find(effect.class, 1, 9)
        if tool and beginPotion(snap, slots, effect, tool) then
          return
        end
      end
    end
  end
  if enabled("MCAutoTotem") and snap.character:GetAttribute("OffhandItem") == "totem" and not inventory.find("Totem", 1, 9) then
    local tool, from = inventory.find("Totem", 10, 36)
    local to = tool and destination(slots, identity(tool))
    if to and not inventory.move(snap, tool, from, to) then
      return
    end
  end
  inventory.close()
end
Supplies.__contract = {
  provides = { "setup", "reset", "step", "busy" },
  requires = { Inventory = "mcpinventory", Native = "mcpnative", Utils = "utils" },
  requiresMethods = {
    Inventory = { "slots", "find", "move", "close", "totem", "step", "busy", "reset" },
    Native = { "snapshot", "equip", "restore", "use", "useState", "blocked" },
    Utils = { "getConfigValue" },
  },
}
return Supplies
