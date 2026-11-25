-- [[ autorefill ]]
--!optimize 2
local Refill = {}
local inventory, native, utils
local character, class, remembered, job, nextRun, failed = nil, nil, {}, nil, 0, nil
local function available(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function key(tool) return tostring(tool:GetAttribute("ClassItem")) .. "|" .. tostring(tool:GetAttribute("BlockKey")) .. "|" .. tool.Name end
local function signature(values)
  local parts = {}
  for slot = 1, 36 do
    local tool = values[slot]
    parts[slot] = available(tool) and tostring(tool) .. key(tool) .. tostring(tool:GetAttribute("Count")) or "_"
  end
  return table.concat(parts, ";")
end
local function enabled() return utils.isActive() and utils.getConfigValue("MCAutoRefill") == true end
local function missing(values)
  for destination = 1, 9 do
    if remembered[destination] and not available(values[destination]) then
      for source = 10, 36 do
        local tool = values[source]
        if available(tool) and key(tool) == remembered[destination] then
          return tool, source, destination
        end
      end
    end
  end
  return nil
end
function Refill.setup(deps)
  inventory, native, utils = deps.Inventory, deps.Native, deps.Utils
  return true
end
function Refill.reset()
  if job and job.opened then
    inventory.closeInventory()
  end
  job = nil
end
function Refill.busy() return job ~= nil end
function Refill.isReserved(slot) return enabled() and remembered[slot] ~= nil end
function Refill.observe(snap)
  local equippedClass = snap.character:GetAttribute("EquippedClass")
  if character ~= snap.character or class ~= equippedClass then
    Refill.reset()
    character, class, remembered, failed, nextRun = snap.character, equippedClass, {}, nil, 0
  end
  if job then
    return
  end
  local values = inventory.inventorySlots()
  if not values then
    return
  end
  for slot = 1, 9 do
    if available(values[slot]) then
      remembered[slot] = key(values[slot])
    end
  end
end
function Refill.step(snap)
  if not enabled() then
    failed = nil
    Refill.reset()
    return
  end
  if not job and snap.now < nextRun then
    return
  end
  local values = inventory.inventorySlots()
  if not values then
    Refill.reset()
    nextRun = snap.now + 0.5
    return
  end
  if job then
    if job.character ~= snap.character or snap.now > job.deadline or not inventory.inventoryVisible() then
      failed = signature(values)
      Refill.reset()
      nextRun = snap.now + 0.5
      return
    end
    if snap.now < job.ready then
      return
    end
    if job.pending then
      if values[job.to] == job.tool and available(job.tool) then
        job.pending = false
      else
        if snap.now >= job.confirmAt then
          failed = signature(values)
          Refill.reset()
        end
        return
      end
    end
    local tool, source, destination = missing(values)
    if not tool then
      Refill.reset()
      nextRun = snap.now + 0.3
      return
    end
    job.tool, job.from, job.to = tool, source, destination
    if not inventory.moveReserve(tool, source, destination) then
      failed = signature(values)
      Refill.reset()
      return
    end
    job.pending, job.ready, job.confirmAt = true, snap.now + 0.1, snap.now + 0.8
    return
  end
  nextRun = snap.now + 0.25
  if native.blocked(snap) or failed == signature(values) then
    return
  end
  if not missing(values) then
    return
  end
  local opened = not inventory.inventoryVisible()
  if not inventory.openInventory() then
    failed = signature(values)
    return
  end
  job = { character = snap.character, opened = opened, ready = snap.now + 0.18, deadline = snap.now + 5 }
end
Refill.__contract = {
  provides = { "setup", "reset", "busy", "observe", "step", "isReserved" },
  requires = { Inventory = "autototem", Native = "mcpnative", Utils = "utils" },
  requiresMethods = {
    Inventory = { "inventorySlots", "inventoryVisible", "openInventory", "closeInventory", "moveReserve" },
    Native = { "blocked" },
    Utils = { "isActive", "getConfigValue" },
  },
}
return Refill
