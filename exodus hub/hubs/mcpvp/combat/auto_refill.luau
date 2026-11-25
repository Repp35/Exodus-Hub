-- [[ autorefill ]]
--!optimize 2
local Refill = {}
local inventory, native, utils
local character, remembered, job, nextRun = nil, {}, nil, 0
local function available(tool)
  return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0
end
local function key(tool)
  return tostring(tool:GetAttribute("ClassItem")) .. "|" .. tostring(tool:GetAttribute("BlockKey")) .. "|" .. tool.Name
end
local function enabled() return utils.isActive() and utils.getConfigValue("MCAutoRefill") == true end
function Refill.setup(deps)
  inventory, native, utils = deps.Inventory, deps.Native, deps.Utils
  return true
end
function Refill.reset()
  if job and job.opened then inventory.closeInventory() end
  job = nil
end
function Refill.busy() return job ~= nil end
function Refill.isReserved(slot) return enabled() and remembered[slot] ~= nil end
function Refill.observe(snap)
  if character ~= snap.character then
    Refill.reset()
    character, remembered = snap.character, {}
  end
  local values = inventory.inventorySlots()
  if not values then return end
  for slot = 1, 9 do
    if available(values[slot]) then remembered[slot] = key(values[slot]) end
  end
end
function Refill.step(snap)
  if not enabled() then Refill.reset() return end
  local values = inventory.inventorySlots()
  if not values then Refill.reset() return end
  if job then
    if job.character ~= snap.character or snap.now > job.deadline or not inventory.inventoryVisible() then
      Refill.reset() nextRun = snap.now + 0.5 return
    end
    if snap.now < job.ready then return end
    if not available(values[job.to]) and values[job.from] == job.tool and key(job.tool) == remembered[job.to] then
      inventory.moveReserve(job.tool, job.from, job.to)
    end
    Refill.reset()
    nextRun = snap.now + 0.15
    return
  end
  if snap.now < nextRun or native.blocked(snap) then return end
  for destination = 1, 9 do
    local identity = remembered[destination]
    if not identity or available(values[destination]) then continue end
    for source = 10, 36 do
      local tool = values[source]
      if available(tool) and key(tool) == identity then
        local opened = not inventory.inventoryVisible()
        if not inventory.openInventory() then nextRun = snap.now + 0.5 return end
        job = { character = snap.character, tool = tool, from = source, to = destination,
          opened = opened, ready = snap.now + 0.18, deadline = snap.now + 1.5 }
        return
      end
    end
  end
  nextRun = snap.now + 0.2
end
Refill.__contract = {
  provides = { "setup", "reset", "busy", "observe", "step", "isReserved" },
  requires = { Inventory = "autototem", Native = "mcpnative", Utils = "utils" },
  requiresMethods = { Inventory = { "inventorySlots", "inventoryVisible", "openInventory", "closeInventory", "moveReserve" },
    Native = { "blocked" }, Utils = { "isActive", "getConfigValue" } },
}
return Refill
