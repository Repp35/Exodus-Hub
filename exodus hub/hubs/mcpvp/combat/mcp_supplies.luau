-- [[ mcpsupplies ]]
--!optimize 2
local Supplies = {}
local inventory, native, target, utils, units
local owner, epoch, layout, potion, used, readyAt = nil, nil, {}, nil, false, 0
local function enabled(key) return utils.getConfigValue(key) == true end
local function identity(tool)
  if not tool or not tool.Parent then
    return nil
  end
  return tool.Name .. "|" .. tostring(tool:GetAttribute("ClassItem")) .. "|" .. tostring(tool:GetAttribute("BlockKey"))
end
local function destination(slots)
  for slot = 1, 9 do
    if not slots[slot] or not slots[slot].Parent then
      return slot
    end
  end
  return nil
end
function Supplies.setup(deps)
  inventory, native, target, utils, units = deps.Inventory, deps.Native, deps.Target, deps.Utils, deps.Units
  return true
end
function Supplies.reset()
  local snap = native.snapshot()
  if potion and snap and potion.character == snap.character and potion.previous and potion.previous.Parent then
    native.equip(snap, potion.previous)
  end
  owner, epoch, layout, potion, used, readyAt = nil, nil, {}, nil, false, 0
  inventory.reset()
end
function Supplies.busy() return inventory.busy() or potion ~= nil end
function Supplies.step(snap, allowBackground)
  local pop = snap.character:GetAttribute("TotemPoppedAt") or 0
  if owner ~= snap.character then
    Supplies.reset()
    owner, epoch, readyAt = snap.character, pop, snap.now + 4
    used = snap.character:GetAttribute("ExodusStrengthAttemptPop") == pop and snap.character:GetAttribute("ExodusStrengthAttemptAt") ~= nil
  end
  if epoch ~= pop then
    epoch, used, readyAt = pop, false, snap.now + 4
  end
  inventory.step(snap)
  local slots = inventory.slots()
  if not slots then
    return
  end
  for slot = 1, 9 do
    if slots[slot] and slots[slot].Parent then
      layout[slot] = identity(slots[slot])
    end
  end
  if enabled("MCAutoTotem") and (snap.character:GetAttribute("OffhandItem") == "totem" or inventory.find("Totem")) then
    if not inventory.totem(snap) then
      return
    end
    if not inventory.find("Totem", 1, 9) then
      local tool, from = inventory.find("Totem", 10, 36)
      local to = tool and destination(slots)
      if tool and to and not inventory.move(snap, tool, from, to) then
        return
      end
    end
  end
  inventory.close()
  if allowBackground == false then
    return
  end
  if potion then
    if potion.character ~= snap.character or target.current(snap) or not enabled("MCAutoStrength") then
      if potion.previous and potion.previous.Parent then
        native.equip(snap, potion.previous)
      end
      potion = nil
      return
    end
    if potion.sent then
      if snap.character:GetAttribute("DrinkingPotion") then
        return
      end
      if snap.now - potion.at < 0.25 then
        return
      end
      if potion.previous and potion.previous.Parent then
        native.equip(snap, potion.previous)
      end
      potion = nil
      return
    end
    if snap.now - potion.at > 1 then
      potion = nil
      return
    end
    if native.equip(snap, potion.tool) then
      snap.tool = potion.tool
      if native.use(snap, potion.tool, Vector3.new(0, -1, 0)) then
        potion.sent, potion.at, used = true, snap.now, true
        snap.character:SetAttribute("ExodusStrengthAttemptPop", epoch)
        snap.character:SetAttribute("ExodusStrengthAttemptAt", workspace:GetServerTimeNow())
      end
    end
    return
  end
  -- Background maintenance never opens an inventory in the middle of an active fight.
  if target.current(snap) or native.blocked(snap) then
    return
  end
  if enabled("MCAutoRefill") then
    for slot = 1, 9 do
      if slots[slot] and slots[slot].Parent then
        layout[slot] = identity(slots[slot])
      elseif layout[slot] then
        for from = 10, 36 do
          local tool = slots[from]
          if identity(tool) == layout[slot] then
            if not inventory.move(snap, tool, from, slot) then
              return
            end
            break
          end
        end
      end
    end
    inventory.close()
  end
  if
    not enabled("MCAutoStrength")
    or used
    or snap.now < readyAt
    or not target.quiet(snap, 4)
    or (tonumber(snap.character:GetAttribute("Effect_strength")) or 0) > workspace:GetServerTimeNow()
    or math.abs(units.toBlocks(snap.root.AssemblyLinearVelocity.Y)) > 0.1
  then
    return
  end
  local tool, from = inventory.find("StrengthPotion")
  if not tool then
    return
  end
  if from > 9 then
    local to = destination(slots)
    if not to or not inventory.move(snap, tool, from, to) then
      return
    end
    inventory.close()
  end
  potion = { character = snap.character, tool = tool, previous = snap.tool, at = snap.now }
end
Supplies.__contract = {
  provides = { "setup", "reset", "step", "busy" },
  requires = { Inventory = "mcpinventory", Native = "mcpnative", Target = "mcptarget", Utils = "utils", Units = "mcpunits" },
  requiresMethods = {
    Inventory = { "slots", "find", "move", "close", "totem", "step", "busy", "reset" },
    Native = { "snapshot", "equip", "use", "blocked" },
    Target = { "current", "quiet" },
    Utils = { "getConfigValue" },
    Units = { "toBlocks" },
  },
}
return Supplies
