-- [[ mcpsupplies ]]
--!optimize 2
local Supplies = {}
local inventory, native, utils, target
local owner, class, job, immediate, rejected
local remembered, nextRun = {}, 0
local strengthEpoch, strengthUsed, quietUntil = nil, false, 0
local function alive(tool) return typeof(tool) == "Instance" and tool:IsA("Tool") and tool.Parent ~= nil and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function enabled(key) return utils.getConfigValue(key) == true end
local function identity(tool) return tostring(tool:GetAttribute("ClassItem")) .. "|" .. tostring(tool:GetAttribute("BlockKey")) .. "|" .. tool.Name end
local function find(values, kind, first, last)
  for slot = first, last do
    local tool = values[slot]
    if alive(tool) and tool:GetAttribute("ClassItem") == kind then
      return tool, slot
    end
  end
  return nil
end
local function destination(values, snap, urgent)
  for slot = 1, 9 do
    if not alive(values[slot]) and not remembered[slot] then
      return slot
    end
  end
  for slot = 1, 9 do
    if not alive(values[slot]) then
      return slot
    end
  end
  for slot = 9, 1, -1 do
    local tool = values[slot]
    if
      urgent and tool ~= snap.tool and native.stats(tool).type == nil and tool:GetAttribute("ClassItem") ~= "Pearl"
      or not urgent and tool:GetAttribute("ClassItem") == "SpeedPotion"
    then
      return slot
    end
  end
  if urgent then
    return values[9] ~= snap.tool and 9 or 8
  end
  return nil
end
local function restore(snap)
  if job and job.kind == "strength" and snap.character == job.character and (snap.tool == job.tool or not snap.tool) and alive(job.previous) then
    native.equip(snap, job.previous)
  end
end
function Supplies.setup(deps)
  inventory, native, utils, target = deps.Inventory, deps.Native, deps.Utils, deps.Target
  return true
end
function Supplies.reset()
  local snap = native.snapshot()
  if snap then
    restore(snap)
  end
  inventory.cancel()
  job = nil
end
function Supplies.busy() return job ~= nil or immediate ~= nil and os.clock() - immediate.at < 1 end
function Supplies.observe(snap)
  local equipped = snap.character:GetAttribute("EquippedClass")
  local epoch = snap.character:GetAttribute("TotemPoppedAt") or 0
  if owner ~= snap.character or class ~= equipped then
    Supplies.reset()
    owner, class, remembered, immediate, rejected = snap.character, equipped, {}, nil, nil
    strengthEpoch, strengthUsed, quietUntil =
      epoch, snap.character:GetAttribute("ExodusStrengthAttemptPop") == epoch and snap.character:GetAttribute("ExodusStrengthAttemptAt") ~= nil, snap.now + 4
  elseif epoch ~= strengthEpoch then
    strengthEpoch, strengthUsed, quietUntil = epoch, false, snap.now + 4
  end
  local values = inventory.slots()
  if values and not job and not inventory.busy() then
    for slot = 1, 9 do
      if alive(values[slot]) then
        remembered[slot] = identity(values[slot])
      end
    end
  end
end
local function protect(snap, values)
  if immediate then
    if immediate.character ~= snap.character then
      immediate, rejected = nil, nil
    elseif inventory.confirm(immediate, snap) then
      immediate = nil
    elseif immediate.done and not immediate.accepted then
      rejected, immediate = immediate.tool, nil
    else
      return
    end
  end
  if not enabled("MCAutoTotem") or snap.character:GetAttribute("OffhandItem") == "totem" then
    return
  end
  local tool = find(values, "Totem", 1, 9)
  if tool and rejected ~= tool then
    immediate = inventory.offhand("totem", snap, tool, true)
  end
end
local function request(snap, kind, tool, from, to)
  if not inventory.begin(kind, snap) then
    return false
  end
  job =
    { kind = kind, character = snap.character, tool = tool, from = from, to = to, stage = from and "move" or "offhand", at = snap.now, previous = snap.tool }
  return true
end
local configKeys = { totem = "MCAutoTotem", refill = "MCAutoRefill", strength = "MCAutoStrength" }
function Supplies.step(snap, allowStart)
  local values = inventory.slots()
  if not values then
    return
  end
  protect(snap, values)
  if job then
    if not enabled(configKeys[job.kind]) or snap.now - job.at > 6 or job.character ~= snap.character then
      Supplies.reset()
      nextRun = snap.now + 0.5
      return
    end
    if job.stage == "move" or job.stage == "offhand" then
      if not inventory.ready(job.kind, snap, job.kind == "totem") then
        return
      end
      if not job.pending then
        if job.stage == "move" then
          job.pending = inventory.move(job.kind, snap, job.tool, job.from, job.to, job.kind == "totem" and "totem" or job.kind == "strength")
        elseif snap.character:GetAttribute("OffhandItem") == "totem" then
          job.stage = "close"
        else
          job.pending = inventory.offhand(job.kind, snap, job.tool)
        end
        return
      end
      if not inventory.confirm(job.pending, snap) then
        return
      end
      job.pending = nil
      job.stage = job.kind == "totem" and snap.character:GetAttribute("OffhandItem") ~= "totem" and "offhand" or "close"
    end
    if job.stage == "close" then
      if not inventory.finish(job.kind, snap) then
        return
      end
      if job.kind ~= "strength" then
        job = nil
        nextRun = snap.now + 0.15
        return
      end
      job.stage = "equip"
    end
    if job.stage == "equip" then
      if not target.quiet(snap, 4) or snap.now < quietUntil then
        Supplies.reset()
        return
      end
      if not alive(job.tool) then
        Supplies.reset()
        return
      end
      if snap.tool ~= job.tool then
        native.equip(snap, job.tool)
        return
      end
      if native.blocked(snap) or math.abs(snap.root.AssemblyLinearVelocity.Y) > 5 then
        return
      end
      job.count, job.stage = tonumber(job.tool:GetAttribute("Count")) or 1, "confirm"
      strengthUsed = true
      snap.character:SetAttribute("ExodusStrengthAttemptAt", workspace:GetServerTimeNow())
      snap.character:SetAttribute("ExodusStrengthAttemptPop", strengthEpoch)
      if not native.useItem(snap, job.tool, Vector3.new(0, -1, 0)) then
        Supplies.reset()
      end
      return
    end
    if job.stage == "confirm" then
      local consumed = not alive(job.tool) or (tonumber(job.tool:GetAttribute("Count")) or job.count) < job.count
      if consumed or (tonumber(snap.character:GetAttribute("Effect_strength")) or 0) > workspace:GetServerTimeNow() then
        Supplies.reset()
      end
    end
    return
  end
  if not allowStart or immediate and snap.now - immediate.at < 1 or snap.now < nextRun or inventory.busy() then
    return
  end
  nextRun = snap.now + 0.2
  local missing = snap.character:GetAttribute("OffhandItem") ~= "totem"
  if not immediate and enabled("MCAutoTotem") and (missing or target.quiet(snap, 0.8) and not find(values, "Totem", 1, 9)) then
    local tool, from = find(values, "Totem", missing and 1 or 10, 36)
    if tool then
      local reserve = from > 9
      local to = reserve and destination(values, snap, true)
      if request(snap, "totem", tool, reserve and from or nil, to) then
        return
      end
    end
  end
  if native.blocked(snap) then
    return
  end
  if enabled("MCAutoRefill") then
    for to = 1, 9 do
      if not remembered[to] or alive(values[to]) then
        continue
      end
      for from = 10, 36 do
        local tool = values[from]
        if alive(tool) and identity(tool) == remembered[to] and request(snap, "refill", tool, from, to) then
          return
        end
      end
    end
  end
  if
    not enabled("MCAutoStrength")
    or strengthUsed
    or snap.now < quietUntil
    or not target.quiet(snap, 4)
    or (tonumber(snap.character:GetAttribute("Effect_strength")) or 0) > workspace:GetServerTimeNow()
  then
    return
  end
  local tool, from = find(values, "StrengthPotion", 1, 36)
  if not tool then
    return
  end
  if from <= 9 then
    job = { kind = "strength", character = snap.character, tool = tool, stage = "equip", at = snap.now, previous = snap.tool }
  else
    local to = destination(values, snap, false)
    if to then
      request(snap, "strength", tool, from, to)
    end
  end
end
Supplies.__contract = {
  provides = { "setup", "reset", "busy", "observe", "step" },
  requires = { Inventory = "mcpinventory", Native = "mcpnative", Utils = "utils", Target = "mcptarget" },
  requiresMethods = {
    Inventory = { "slots", "begin", "ready", "move", "offhand", "confirm", "finish", "cancel", "busy" },
    Native = { "snapshot", "equip", "blocked", "stats", "useItem" },
    Utils = { "getConfigValue" },
    Target = { "quiet" },
  },
}
return Supplies
