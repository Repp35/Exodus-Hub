-- [[ mcpsupplies ]]
--!optimize 2
local Supplies = {}
local inventory, native, utils
local owner, layout, potion, awaiting = nil, {}, nil, {}
local effects = { { key = "MCAutoStrength", class = "StrengthPotion", effect = "strength" }, { key = "MCAutoSpeed", class = "SpeedPotion", effect = "speed" } }
local function enabled(key) return utils.getConfigValue(key) == true end
local function alive(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function identity(tool)
  return alive(tool) and tool.Name .. "|" .. tostring(tool:GetAttribute("ClassItem")) .. "|" .. tostring(tool:GetAttribute("BlockKey")) or nil
end
local function destination(slots)
  for slot = 1, 9 do
    if not alive(slots[slot]) then
      return slot
    end
  end
  return nil
end
local function restore(snap) return native.restore(snap, potion and potion.previous) end
function Supplies.setup(deps)
  inventory, native, utils = deps.Inventory, deps.Native, deps.Utils
  return true
end
function Supplies.reset()
  local snap = native.snapshot()
  if potion and potion.sent and snap and potion.character == snap.character then
    -- An accepted request stays owned until the game confirms consumption.
    return
  end
  if snap and potion then
    restore(snap)
  end
  owner, layout, potion, awaiting = nil, {}, nil, {}
  inventory.reset()
end
function Supplies.busy() return inventory.busy() or potion ~= nil end
local function throw(snap)
  if potion.character ~= snap.character then
    potion = nil
    return
  end
  if potion.sent then
    local consumed = not alive(potion.tool) or (tonumber(potion.tool:GetAttribute("Count")) or potion.count) < potion.count
    local active = (tonumber(snap.character:GetAttribute("Effect_" .. potion.effect)) or 0) > workspace:GetServerTimeNow()
    if (consumed or active) and not snap.character:GetAttribute("DrinkingPotion") and not native.busy() and restore(snap) then
      awaiting[potion.effect] = not active and snap.now + 1 or nil
      potion = nil
    end
    return
  end
  if not alive(potion.tool) or snap.now > potion.deadline then
    if restore(snap) then
      potion = nil
    end
    return
  end
  if native.equip(snap, potion.tool) then
    potion.count = tonumber(potion.tool:GetAttribute("Count")) or 1
    potion.sent = native.use(snap, potion.tool, Vector3.new(0, -1, 0))
  end
end
function Supplies.step(snap, allowBackground)
  if owner ~= snap.character then
    owner, layout, potion, awaiting = snap.character, {}, nil, {}
    inventory.reset()
  end
  inventory.step(snap)
  if potion then
    throw(snap)
    return
  end
  if allowBackground == false and not inventory.busy() or snap.character:GetAttribute("EatingApple") then
    return
  end
  local slots = inventory.slots()
  if not slots then
    return
  end
  for slot = 1, 9 do
    layout[slot] = identity(slots[slot]) or layout[slot]
  end
  if enabled("MCAutoTotem") and (snap.character:GetAttribute("OffhandItem") == "totem" or inventory.find("Totem")) then
    if not inventory.totem(snap) then
      return
    end
    if not inventory.find("Totem", 1, 9) then
      local tool, from = inventory.find("Totem", 10, 36)
      local to = tool and destination(slots)
      if to and not inventory.move(snap, tool, from, to) then
        return
      end
    end
  end
  if enabled("MCAutoRefill") then
    for slot = 1, 9 do
      if not alive(slots[slot]) and layout[slot] then
        for from = 10, 36 do
          local tool = slots[from]
          if identity(tool) == layout[slot] then
            -- Keep this inventory lease across frames until the actual move succeeds.
            if not inventory.move(snap, tool, from, slot) then
              return
            end
            break
          end
        end
      end
    end
  end
  if allowBackground ~= false and enabled("MCAutoPotion") then
    for _, effect in ipairs(effects) do
      if
        enabled(effect.key)
        and snap.now >= (awaiting[effect.effect] or 0)
        and (tonumber(snap.character:GetAttribute("Effect_" .. effect.effect)) or 0) <= workspace:GetServerTimeNow()
      then
        local tool, from = inventory.find(effect.class)
        if tool then
          if from > 9 then
            local to = destination(slots)
            if to and not inventory.move(snap, tool, from, to) then
              return
            end
            if not to then
              continue
            end
          end
          inventory.close()
          if not native.blocked(snap) then
            potion = { character = snap.character, tool = tool, previous = snap.tool, effect = effect.effect, deadline = snap.now + 1 }
            throw(snap)
          end
          return
        end
      end
    end
  end
  inventory.close()
end
Supplies.__contract = {
  provides = { "setup", "reset", "step", "busy" },
  requires = { Inventory = "mcpinventory", Native = "mcpnative", Utils = "utils" },
  requiresMethods = {
    Inventory = { "slots", "find", "move", "close", "totem", "step", "busy", "reset" },
    Native = { "snapshot", "equip", "restore", "use", "blocked", "busy" },
    Utils = { "getConfigValue" },
  },
}
return Supplies
