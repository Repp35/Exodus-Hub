-- [[ autototem ]]
--!optimize 2
local Totem = {}
local inventory, utils, target
local reserved, job, nextRun, immediate, rejected
local function available(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function find(values, first, last)
  for slot = first, last do
    local tool = values[slot]
    if available(tool) and tool:GetAttribute("ClassItem") == "Totem" then
      return tool
    end
  end
  return nil
end
local function empty(values)
  for slot = 1, 9 do
    if not available(values[slot]) and (not reserved or not reserved(slot)) then
      return slot
    end
  end
  return nil
end
local function destination(values, snap)
  local free = empty(values)
  if free then return free end
  for slot = 1, 9 do if not available(values[slot]) then return slot end end
  for slot = 9, 1, -1 do
    local tool = values[slot]
    if tool ~= snap.tool and tool:GetAttribute("ClassItem") ~= "Pearl"
      and tool:GetAttribute("WeaponType") == nil and tool:GetAttribute("VoxelWeapon") ~= true then return slot end
  end
  return values[9] ~= snap.tool and 9 or 8
end
function Totem.setup(deps)
  inventory, utils, target = deps.Inventory, deps.Utils, deps.Target
  return true
end
function Totem.reset()
  inventory.cancel("totem")
  job = nil
end
function Totem.busy() return job ~= nil end
function Totem.setReservations(callback) reserved = callback end
function Totem.protect(snap)
  if not utils.isActive() or not utils.getConfigValue("MCAutoTotem") then return end
  if immediate then
    if immediate.character ~= snap.character then immediate, rejected = nil, nil
    elseif inventory.confirm(immediate, snap) then immediate = nil
    elseif immediate.done and not immediate.accepted then rejected, immediate = immediate.tool, nil
    else return end
  end
  if snap.character:GetAttribute("OffhandItem") == "totem" then rejected = nil return end
  local values = inventory.slots()
  local tool = values and find(values, 1, 9)
  if tool and tool ~= rejected then immediate = inventory.offhand("totem", snap, tool, true) end
end
function Totem.step(snap)
  if not utils.isActive() or not utils.getConfigValue("MCAutoTotem") then
    Totem.reset()
    return
  end
  if job and job.character ~= snap.character then
    Totem.reset()
    return
  end
  Totem.protect(snap)
  if immediate then return end
  local values = inventory.slots()
  if not values then
    return
  end
  if not job then
    if snap.character:GetAttribute("OffhandItem") == "totem" and snap.now < (nextRun or 0) then
      return
    end
    nextRun = snap.now
    local missing = snap.character:GetAttribute("OffhandItem") ~= "totem"
    if not missing and not target.quiet(snap, 0.8) then return end
    if not (missing and find(values, 1, 36)) and not (find(values, 10, 36) and not find(values, 1, 9)) then
      return
    end
    if not inventory.begin("totem", snap) then
      return
    end
    job = { character = snap.character, stage = missing and "offhand" or "refill" }
  end
  if job.stage == "close" then
    if inventory.finish("totem", snap) then
      job = nil
      nextRun = snap.now + 0.4
    end
    return
  end
  if not inventory.ready("totem", snap, true) then
    return
  end
  if job.pending then
    if not inventory.confirm(job.pending, snap) then
      return
    end
    job.pending = nil
  end
  if job.stage == "offhand" then
    if snap.character:GetAttribute("OffhandItem") == "totem" then
      job.stage = "refill"
    else
      local tool = find(values, 1, 9)
      if tool then
        job.pending = inventory.offhand("totem", snap, tool)
      else
        local reserve = find(values, 10, 36)
        if reserve then
          for from = 10, 36 do
            if values[from] == reserve then
              job.pending = inventory.move("totem", snap, reserve, from, destination(values, snap), "totem")
              -- The native slot table is updated synchronously, just as in VoxelPackHUD.
              -- Equip the newly moved totem immediately rather than waiting another frame.
              Totem.protect(snap)
              break
            end
          end
        end
      end
      return
    end
  end
  local tool = not find(values, 1, 9) and find(values, 10, 36)
  local destination = tool and destination(values, snap)
  if tool and destination then
    local from
    for slot = 10, 36 do
      if values[slot] == tool then
        from = slot
        break
      end
    end
    job.pending = inventory.move("totem", snap, tool, from, destination, "totem")
    return
  end
  if snap.character:GetAttribute("OffhandItem") ~= "totem" and find(values, 1, 36) then
    job.stage = "offhand"
    return
  end
  job.stage = "close"
  if inventory.finish("totem", snap) then
    job = nil
    nextRun = snap.now + 0.4
  end
end
Totem.__contract = {
  provides = { "setup", "reset", "busy", "step", "setReservations", "protect" },
  requires = { Inventory = "mcpinventory", Utils = "utils", Target = "mcptarget" },
  requiresMethods = {
    Inventory = { "slots", "begin", "ready", "move", "offhand", "confirm", "finish", "cancel" },
    Utils = { "isActive", "getConfigValue" }, Target = { "quiet" },
  },
}
return Totem
