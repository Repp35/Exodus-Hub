-- [[ autostrength ]]
--!optimize 2
local Strength = {}
local native, inventory, utils
local job, nextRun, failedTool, failedFrom, failedTo, owner = nil, 0, nil, nil, nil, nil
local function alive(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function find(values, class, first, last)
  for slot = first, last do
    if alive(values[slot]) and values[slot]:GetAttribute("ClassItem") == class then
      return values[slot], slot
    end
  end
  return nil
end
local function active(snap) return (tonumber(snap.character:GetAttribute("Effect_strength")) or 0) > workspace:GetServerTimeNow() end
local function finish()
  local previous = job
  job = nil
  if not previous then
    return
  end
  if previous.opened then
    inventory.closeInventory()
  end
  local snap = native.snapshot()
  if
    snap
    and snap.character == previous.character
    and (previous.stage ~= "confirm" or previous.confirmed)
    and (snap.tool == previous.tool or snap.tool == nil)
  then
    local tool = previous.previousTool
    if tool and tool.Parent then
      native.equip(snap, tool)
    elseif utils.getConfigValue("MCAutoSword") then
      local sword = native.findSword(snap)
      if sword then
        native.equip(snap, sword)
      end
    end
  end
  nextRun = os.clock() + 0.35
end
function Strength.setup(deps)
  native, inventory, utils = deps.Native, deps.Inventory, deps.Utils
  return true
end
function Strength.reset() finish() end
function Strength.busy() return job ~= nil end
function Strength.step(snap)
  if owner ~= snap.character then
    finish()
    owner, failedTool = snap.character, nil
  end
  if not utils.isActive() or not utils.getConfigValue("MCAutoStrength") then
    failedTool = nil
    finish()
    return
  end
  if job and job.character ~= snap.character then
    finish()
    return
  end
  if job then
    local current = job
    if current.stage == "inventory" then
      if snap.now > current.deadline then
        failedTool, failedFrom, failedTo = current.tool, current.from, current.to
        finish()
        return
      end
      if not inventory.inventoryVisible() then
        failedTool, failedFrom, failedTo = current.tool, current.from, current.to
        finish()
        return
      end
      if snap.now < current.ready then
        return
      end
      local values = inventory.inventorySlots()
      if not values then
        return
      end
      if current.moved then
        if values[current.to] == current.tool and alive(current.tool) then
          finish()
        end
        return
      end
      if values[current.from] ~= current.tool then
        finish()
        return
      end
      if inventory.swapSpeedForStrength(current.tool, current.from, current.to) then
        current.moved, current.ready = true, snap.now + 0.1
      else
        failedTool, failedFrom, failedTo = current.tool, current.from, current.to
        finish()
      end
      return
    end
    if current.stage == "confirm" then
      local consumed = not current.tool.Parent or (tonumber(current.tool:GetAttribute("Count")) or current.count) < current.count
      if consumed and not current.consumedAt then
        current.consumedAt = snap.now
      end
      if active(snap) or current.consumedAt and snap.now - current.consumedAt >= 0.35 then
        current.confirmed = true
        finish()
      elseif snap.now > current.deadline then
        current.confirmed = true
        finish()
        nextRun = snap.now + 2
      end
      return
    end
    if snap.now > current.deadline then
      finish()
      return
    end
    if active(snap) then
      finish()
      return
    end
    if snap.now < current.ready then
      return
    end
    if snap.tool ~= current.tool then
      return
    end
    if native.blocked(snap) then
      finish()
      return
    end
    local onGround = snap.character:GetAttribute("VoxelGrounded")
    if onGround == false or math.abs(snap.root.AssemblyLinearVelocity.Y) > 5 then
      finish()
      return
    end
    current.count = tonumber(current.tool:GetAttribute("Count")) or 1
    if native.useItem(snap, current.tool, Vector3.new(0, -1, 0)) then
      current.stage, current.deadline = "confirm", snap.now + 2.5
    else
      finish()
    end
    return
  end
  if snap.now < nextRun or native.blocked(snap) then
    return
  end
  local values = inventory.inventorySlots()
  if not values then
    nextRun = snap.now + 0.5
    return
  end
  local hotbar = find(values, "StrengthPotion", 1, 9)
  local reserve, from = find(values, "StrengthPotion", 10, 36)
  local _, speedSlot = find(values, "SpeedPotion", 1, 9)
  local destination = speedSlot
  if not destination and not hotbar then
    for slot = 1, 9 do
      if not alive(values[slot]) then
        destination = slot
        break
      end
    end
  end
  if active(snap) then
    nextRun = snap.now + 0.5
    return
  end
  if reserve and destination and not hotbar then
    if reserve == failedTool and from == failedFrom and destination == failedTo then
      return
    end
    local opened = not inventory.inventoryVisible()
    if not inventory.openInventory() then
      failedTool, failedFrom, failedTo = reserve, from, destination
      nextRun = snap.now + 0.5
      return
    end
    job = {
      character = snap.character,
      tool = reserve,
      previousTool = snap.tool,
      from = from,
      to = destination,
      opened = opened,
      stage = "inventory",
      ready = snap.now + 0.18,
      deadline = snap.now + 1.5,
    }
    return
  end
  if active(snap) or not hotbar then
    nextRun = snap.now + 0.25
    return
  end
  if snap.character:GetAttribute("VoxelGrounded") == false or math.abs(snap.root.AssemblyLinearVelocity.Y) > 5 then
    return
  end
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  params.FilterDescendantsInstances = { snap.character, snap.camera }
  if not workspace:Raycast(snap.eye, Vector3.new(0, -10, 0), params) then
    nextRun = snap.now + 0.25
    return
  end
  if not native.equip(snap, hotbar) then
    nextRun = snap.now + 0.35
    return
  end
  job = { character = snap.character, previousTool = snap.tool, tool = hotbar, stage = "use", ready = snap.now + 0.12, deadline = snap.now + 1.3 }
end
Strength.__contract = {
  provides = { "setup", "reset", "step", "busy" },
  requires = { Native = "mcpnative", Inventory = "autototem", Utils = "utils" },
  requiresMethods = {
    Native = { "snapshot", "findSword", "equip", "blocked", "useItem" },
    Inventory = { "inventorySlots", "inventoryVisible", "openInventory", "closeInventory", "swapSpeedForStrength" },
    Utils = { "isActive", "getConfigValue" },
  },
}
return Strength
