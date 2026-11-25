-- [[ autorefill ]]
--!optimize 2
local Refill = {}
local inventory, native, utils
local character, class, remembered, job, nextRun = nil, nil, {}, nil, 0
local function available(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function key(tool) return tostring(tool:GetAttribute("ClassItem")) .. "|" .. tostring(tool:GetAttribute("BlockKey")) .. "|" .. tool.Name end
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
  inventory.cancel("refill")
  job = nil
end
function Refill.busy() return job ~= nil end
function Refill.isReserved(slot) return enabled() and remembered[slot] ~= nil end
function Refill.observe(snap)
  local equippedClass = snap.character:GetAttribute("EquippedClass")
  if character ~= snap.character or class ~= equippedClass then
    Refill.reset()
    character, class, remembered, nextRun = snap.character, equippedClass, {}, 0
  end
  if job then
    return
  end
  local values = inventory.slots()
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
    Refill.reset()
    return
  end
  if job and job.character ~= snap.character then
    Refill.reset()
    return
  end
  if not job and snap.now < nextRun then
    return
  end
  local values = inventory.slots()
  if not values then
    return
  end
  if not job then
    nextRun = snap.now + 0.3
    if native.blocked(snap) or not missing(values) or not inventory.begin("refill", snap) then
      return
    end
    job = { character = snap.character }
  end
  if job.stage == "close" then
    if inventory.finish("refill", snap) then
      job = nil
      nextRun = snap.now + 0.4
    end
    return
  end
  if not inventory.ready("refill", snap) then
    return
  end
  if job.pending then
    if not inventory.confirm(job.pending, snap) then
      return
    end
    job.pending = nil
  end
  local tool, from, destination = missing(values)
  if tool then
    job.pending = inventory.move("refill", snap, tool, from, destination)
    return
  end
  job.stage = "close"
  if inventory.finish("refill", snap) then
    job = nil
    nextRun = snap.now + 0.4
  end
end
Refill.__contract = {
  provides = { "setup", "reset", "busy", "observe", "step", "isReserved" },
  requires = { Inventory = "mcpinventory", Native = "mcpnative", Utils = "utils" },
  requiresMethods = {
    Inventory = { "slots", "begin", "ready", "move", "confirm", "finish", "cancel" },
    Native = { "blocked" },
    Utils = { "isActive", "getConfigValue" },
  },
}
return Refill
