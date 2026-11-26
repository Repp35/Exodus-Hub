-- [[ mcpinventory ]]
--!optimize 2
local Inventory = {}
local utils, bridge, cachedFn, values, lease, pending
local retryAt = 0
function Inventory.setup(deps)
  utils, bridge = deps.Utils, deps.Bridge
  return true
end
local function owned(tool)
  local player = utils.getLocalPlayer()
  return typeof(tool) == "Instance"
    and tool:IsA("Tool")
    and (tool.Parent == player.Character or tool.Parent == player:FindFirstChild("Backpack"))
    and (tonumber(tool:GetAttribute("Count")) or 1) > 0
end
function Inventory.slots()
  local fn = bridge.get("refresh")
  if fn ~= cachedFn then
    cachedFn, values = fn, nil
  end
  if values then
    return values
  end
  local upvalues = bridge.upvalues(fn)
  if not upvalues then
    return nil
  end
  for _, value in pairs(upvalues) do
    if type(value) ~= "table" or getmetatable(value) ~= nil then
      continue
    end
    local valid, count = true, 0
    for slot, tool in pairs(value) do
      if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 36 or typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
        valid = false
        break
      end
      count += 1
    end
    if valid and count > 0 then
      values = value
      return value
    end
  end
  return nil
end
function Inventory.find(kind, first, last)
  local slots = Inventory.slots()
  if slots then
    for slot = first or 1, last or 36 do
      local tool = slots[slot]
      if owned(tool) and tool:GetAttribute("ClassItem") == kind then
        return tool, slot
      end
    end
  end
  return nil
end
function Inventory.select(snap, slot)
  local slots, select = Inventory.slots(), bridge.get("select")
  local tool = slots and slots[slot]
  if not select or not owned(tool) or slot < 1 or slot > 9 then
    return false
  end
  local ok = pcall(select, slot)
  snap.tool = snap.character:FindFirstChildOfClass("Tool")
  return ok and snap.tool == tool
end
local function visible()
  local gui = utils.getLocalPlayer():FindFirstChildOfClass("PlayerGui")
  local hud = gui and gui:FindFirstChild("VoxelPackHUD")
  local panel = hud and hud:FindFirstChild("Inventory", true)
  if not panel or not panel:IsA("GuiObject") then
    return false
  end
  local ancestor = panel
  while ancestor and ancestor ~= gui do
    if ancestor:IsA("GuiObject") and not ancestor.Visible or ancestor:IsA("ScreenGui") and not ancestor.Enabled then
      return false
    end
    ancestor = ancestor.Parent
  end
  return ancestor == gui
end
function Inventory.open(snap)
  if lease and lease.character ~= snap.character then
    Inventory.reset()
  end
  if not visible() and snap.player:GetAttribute("MenuOpen") then
    return false
  end
  if not lease then
    lease = { character = snap.character, owned = not visible() }
  end
  if not visible() then
    if snap.player:GetAttribute("MenuOpen") then
      return false
    end
    local fn = bridge.get("open")
    if not fn or not pcall(fn, true) then
      lease = nil
      return false
    end
  end
  local ready = visible() and snap.player:GetAttribute("MenuOpen") == true
  if not ready then
    lease = nil
  end
  return ready and lease.presented == true
end
function Inventory.present()
  if lease and visible() then
    lease.presented = true
  end
end
function Inventory.close()
  if not lease then
    return
  end
  if lease.owned and visible() then
    local fn = bridge.get("open")
    if fn then
      pcall(fn, false)
    end
  end
  lease = nil
end
function Inventory.move(snap, tool, from, to)
  local slots = Inventory.slots()
  if not slots or not owned(tool) or slots[from] ~= tool or to < 1 or to > 9 or owned(slots[to]) or not Inventory.open(snap) then
    return false
  end
  local previous = slots[to]
  slots[from], slots[to] = previous, tool
  if not pcall(cachedFn) then
    slots[from], slots[to] = tool, previous
    return false
  end
  return slots[to] == tool
end
function Inventory.step(snap)
  if lease and lease.character ~= snap.character then
    Inventory.close()
  end
  if pending then
    if pending.character ~= snap.character then
      pending = nil
    else
      local consumed = not owned(pending.tool) or (tonumber(pending.tool:GetAttribute("Count")) or 0) < pending.count
      local popped = snap.character:GetAttribute("TotemPoppedAt")
      local confirmed = consumed and (snap.character:GetAttribute("OffhandItem") == "totem" or popped ~= nil and popped ~= pending.pop)
      if confirmed or pending.done and not pending.accepted then
        if pending.hand and pending.previous and (not snap.tool or snap.tool == pending.tool) then
          local slots = Inventory.slots()
          for slot = 1, 9 do
            if slots and slots[slot] == pending.previous then
              Inventory.select(snap, slot)
              break
            end
          end
        end
        pending, retryAt = nil, confirmed and 0 or snap.now + 0.15
      end
    end
  end
end
function Inventory.totem(snap)
  Inventory.step(snap)
  if pending then
    return false
  end
  if snap.character:GetAttribute("OffhandItem") == "totem" then
    return true
  end
  if snap.now < retryAt then
    return false
  end
  local tool, slot = Inventory.find("Totem")
  if not tool then
    return false
  end
  local previous = snap.tool
  if slot <= 9 then
    if not Inventory.select(snap, slot) then
      return false
    end
  elseif not Inventory.open(snap) then
    return false
  end
  local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
  local remote = folder and folder:FindFirstChild("InventoryAction")
  if not remote then
    return false
  end
  local operation = {
    tool = tool,
    character = snap.character,
    count = tonumber(tool:GetAttribute("Count")) or 1,
    pop = snap.character:GetAttribute("TotemPoppedAt"),
    hand = slot <= 9,
    previous = previous,
  }
  pending = operation
  task.spawn(function()
    local ok, result = pcall(remote.InvokeServer, remote, "EquipOffhand", tool)
    operation.done, operation.accepted = true, ok and result ~= nil and result ~= false
    if operation.accepted and utils.getLocalPlayer().Character == operation.character and cachedFn then
      pcall(cachedFn)
    end
  end)
  return false
end
function Inventory.busy() return lease ~= nil or pending ~= nil and pending.hand end
function Inventory.reset()
  Inventory.close()
  if pending and pending.character ~= utils.getLocalPlayer().Character then
    pending = nil
  end
  retryAt = 0
end
function Inventory.teardown()
  Inventory.reset()
  cachedFn, values = nil, nil
end
Inventory.__contract = {
  provides = { "setup", "slots", "find", "select", "open", "present", "close", "move", "step", "totem", "busy", "reset", "teardown" },
  requires = { Utils = "utils", Bridge = "mcpbridge" },
  requiresMethods = { Utils = { "getLocalPlayer" }, Bridge = { "get", "upvalues" } },
}
return Inventory
