-- [[ autototem ]]
--!optimize 2
local Totem = {}
local inventory, utils
local reserved, job, nextRun
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
function Totem.setup(deps)
  inventory, utils = deps.Inventory, deps.Utils
  return true
end
function Totem.reset()
  inventory.cancel("totem")
  job = nil
end
function Totem.busy() return job ~= nil end
function Totem.setReservations(callback) reserved = callback end
function Totem.step(snap)
  if not utils.isActive() or not utils.getConfigValue("MCAutoTotem") then
    Totem.reset()
    return
  end
  if job and job.character ~= snap.character then
    Totem.reset()
    return
  end
  local values = inventory.slots()
  if not values then
    return
  end
  if not job then
    if snap.now < (nextRun or 0) then
      return
    end
    nextRun = snap.now + 0.2
    local missing = snap.character:GetAttribute("OffhandItem") ~= "totem"
    if not (missing and find(values, 1, 36)) and not (find(values, 10, 36) and empty(values)) then
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
  if not inventory.ready("totem", snap) then
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
      local tool = find(values, 1, 36)
      if tool then
        job.pending = inventory.offhand("totem", snap, tool)
      end
      return
    end
  end
  local tool, destination = find(values, 10, 36), empty(values)
  if tool and destination then
    local from
    for slot = 10, 36 do
      if values[slot] == tool then
        from = slot
        break
      end
    end
    job.pending = inventory.move("totem", snap, tool, from, destination)
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
  provides = { "setup", "reset", "busy", "step", "setReservations" },
  requires = { Inventory = "mcpinventory", Utils = "utils" },
  requiresMethods = {
    Inventory = { "slots", "begin", "ready", "move", "offhand", "confirm", "finish", "cancel" },
    Utils = { "isActive", "getConfigValue" },
  },
}
return Totem
