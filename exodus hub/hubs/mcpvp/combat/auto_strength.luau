-- [[ autostrength ]]
--!optimize 2
local Strength = {}
local native, inventory, utils, target
local owner, popAt, job, nextAttempt, used, quietUntil = nil, nil, nil, 0, false, 0
local function alive(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function active(snap) return (tonumber(snap.character:GetAttribute("Effect_strength")) or 0) > workspace:GetServerTimeNow() end
local function find(values, first, last)
  for slot = first, last do
    local tool = values[slot]
    if alive(tool) and tool:GetAttribute("ClassItem") == "StrengthPotion" then
      return tool, slot
    end
  end
  return nil
end
local function restore(snap)
  if job and snap.character == job.character and (snap.tool == job.tool or snap.tool == nil) then
    if job.previousTool and job.previousTool.Parent then
      native.equip(snap, job.previousTool)
    end
  end
end
function Strength.setup(deps)
  native, inventory, utils, target = deps.Native, deps.Inventory, deps.Utils, deps.Target
  return true
end
function Strength.reset()
  inventory.cancel("strength")
  local snap = native.snapshot()
  if snap and job and not job.sent then
    restore(snap)
  end
  job = nil
  -- Cooldown and the life/totem latch deliberately survive Stop, toggles and runtime resets.
end
function Strength.observe(snap)
  local popped = snap.character:GetAttribute("TotemPoppedAt")
  if owner ~= snap.character then
    Strength.reset()
    local previous = tonumber(snap.character:GetAttribute("ExodusStrengthAttemptAt"))
    local sameEpoch = snap.character:GetAttribute("ExodusStrengthAttemptPop") == (popped or 0)
    owner, popAt, used, quietUntil = snap.character, popped, previous ~= nil and sameEpoch, snap.now + 4
    nextAttempt = previous and snap.now + math.max(0, native.strengthDuration() - (workspace:GetServerTimeNow() - previous)) or 0
  elseif popped ~= nil and popped ~= popAt then
    Strength.reset()
    popAt, nextAttempt, used, quietUntil = popped, snap.now + 4, false, snap.now + 4
  end
end
function Strength.busy() return job ~= nil end
function Strength.step(snap)
  if not utils.isActive() or not utils.getConfigValue("MCAutoStrength") then
    Strength.reset()
    return
  end
  Strength.observe(snap)
  if job then
    if job.stage == "inventory" then
      if not inventory.ready("strength", snap) then
        return
      end
      if not job.pending then
        job.pending = inventory.move("strength", snap, job.tool, job.from, job.to, true)
        return
      end
      if not inventory.confirm(job.pending, snap) then
        return
      end
      job.stage = "close"
    end
    if job.stage == "close" then
      if not inventory.finish("strength", snap) then
        return
      end
      job.stage = "equip"
    end
    if job.stage == "equip" then
      if not target.quiet(snap, 4) or snap.now < quietUntil then
        return
      end
      if not job.equipped then
        job.equipped = native.equip(snap, job.tool)
        return
      end
      if snap.tool ~= job.tool or native.blocked(snap) then
        return
      end
      if snap.character:GetAttribute("VoxelGrounded") == false or math.abs(snap.root.AssemblyLinearVelocity.Y) > 5 then
        return
      end
      job.count = tonumber(job.tool:GetAttribute("Count")) or 1
      -- Set the latch BEFORE dispatch, including a failed attempt. Never send a second Use.
      used, nextAttempt, job.sent = true, snap.now + native.strengthDuration(), true
      snap.character:SetAttribute("ExodusStrengthAttemptAt", workspace:GetServerTimeNow())
      snap.character:SetAttribute("ExodusStrengthAttemptPop", popAt or 0)
      job.sentAt, job.stage = snap.now, "confirm"
      job.dispatched = native.useItem(snap, job.tool, Vector3.new(0, -1, 0))
      if not job.dispatched then
        restore(snap)
        job = nil
      end
      return
    end
    if job.stage == "confirm" then
      local consumed = not job.tool.Parent or (tonumber(job.tool:GetAttribute("Count")) or job.count) < job.count
      if consumed then
        restore(snap)
        job = nil
      elseif snap.now - job.sentAt > 5 and not job.reported then
        job.reported = true
        utils.recordError("mcpvp.strength", "Poção enviada uma vez; aguardando consumo replicado. Sem reenvio automático.")
      end
      return
    end
    return
  end
  if used or snap.now < nextAttempt or snap.now < quietUntil or active(snap) or not target.quiet(snap, 4) or native.blocked(snap) then
    return
  end
  local values = inventory.slots()
  if not values then
    return
  end
  local tool = find(values, 1, 9)
  local from, destination
  if not tool then
    tool, from = find(values, 10, 36)
    if not tool then
      return
    end
    for slot = 1, 9 do
      if not alive(values[slot]) then
        destination = slot
        break
      end
    end
    if not destination then
      for slot = 1, 9 do
        if values[slot]:GetAttribute("ClassItem") == "SpeedPotion" then
          destination = slot
          break
        end
      end
    end
    if not destination or not inventory.begin("strength", snap) then
      return
    end
  end
  job = { character = snap.character, previousTool = snap.tool, tool = tool, from = from, to = destination, stage = from and "inventory" or "equip" }
end
Strength.__contract = {
  provides = { "setup", "reset", "observe", "step", "busy" },
  requires = { Native = "mcpnative", Inventory = "mcpinventory", Utils = "utils", Target = "mcptarget" },
  requiresMethods = {
    Native = { "snapshot", "equip", "blocked", "useItem", "strengthDuration" },
    Inventory = { "slots", "begin", "ready", "move", "confirm", "finish", "cancel" },
    Utils = { "isActive", "getConfigValue", "recordError" },
    Target = { "quiet" },
  },
}
return Strength
