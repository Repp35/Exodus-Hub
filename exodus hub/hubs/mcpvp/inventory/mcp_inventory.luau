-- [[ mcpinventory ]]
--!optimize 2
local Inventory = {}
local utils, bridge, cachedFn, values, lease, pending
local retryAt, nextToggle = 0, 0
local controller
local nextControllerScan = 0
function Inventory.setup(deps)
  utils, bridge = deps.Utils, deps.Bridge
  controller, nextControllerScan = nil, 0
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
  if not owned(tool) or slot < 1 or slot > 9 then
    return false
  end
  if select then
    pcall(select, slot)
  end
  snap.tool = snap.character:FindFirstChildOfClass("Tool")
  if snap.tool == tool then
    return true
  end
  -- EquipTool is a fallback only for an item already proved to be in the hotbar.
  if slots[slot] ~= tool or not owned(tool) then
    return false
  end
  pcall(snap.humanoid.EquipTool, snap.humanoid, tool)
  snap.tool = snap.character:FindFirstChildOfClass("Tool")
  return snap.tool == tool
end
local function visible()
  local gui = utils.getLocalPlayer():FindFirstChildOfClass("PlayerGui")
  local hud = gui and gui:FindFirstChild("VoxelPackHUD")
  local panel = hud and hud:FindFirstChild("Inventory", true)
  if not panel or not panel:IsA("GuiObject") or panel.AbsoluteSize.X <= 0 or panel.AbsoluteSize.Y <= 0 then
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
local function setOpen(value)
  if not controller and os.clock() >= nextControllerScan then
    nextControllerScan = os.clock() + 0.5
    local source = game:GetService("ReplicatedStorage"):FindFirstChild("ControllerInput")
    local ok, loaded = pcall(function() return source and require(source) end)
    controller = ok and type(loaded) == "table" and loaded or nil
  end
  local function matches() return visible() == value and (utils.getLocalPlayer():GetAttribute("MenuOpen") == true) == value end
  if matches() then
    return true
  end
  local fn = bridge.get("open")
  if fn then
    pcall(fn, value)
  end
  if matches() then
    return true
  end
  -- Use the real inventory binding when direct access is unavailable.
  if controller and type(controller.BeginTouch) == "function" and type(controller.EndTouch) == "function" and os.clock() >= nextToggle then
    nextToggle = os.clock() + 0.2
    pcall(function()
      if controller.BeginTouch("Inventory") then
        controller.EndTouch("Inventory")
      end
    end)
  end
  return matches()
end
function Inventory.open(snap)
  if lease and lease.character ~= snap.character then
    Inventory.reset()
  end
  if snap.now < retryAt or not visible() and snap.player:GetAttribute("MenuOpen") then
    return false
  end
  if not lease then
    lease = { character = snap.character, owned = not visible(), frames = 0, deadline = snap.now + 3 }
  end
  lease.closeRequested = nil
  if not visible() then
    lease.frames, lease.visibleAt = 0, nil
    setOpen(true)
  end
  return visible() and snap.player:GetAttribute("MenuOpen") == true and lease.frames >= 2 and lease.visibleAt ~= nil and snap.now - lease.visibleAt >= 0.12
end
function Inventory.present()
  if lease and visible() then
    lease.frames += 1
    lease.visibleAt = lease.visibleAt or os.clock()
  end
end
function Inventory.close(force)
  if not lease then
    return true
  end
  if lease.owned then
    if not force and lease.visibleAt and os.clock() - lease.visibleAt < 0.3 then
      lease.closeRequested = true
      return false
    end
    if not setOpen(false) then
      lease.closeRequested = true
      return false
    end
  end
  lease = nil
  return true
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
local function restoreHand(snap, operation)
  if operation.hand and operation.previous and (not snap.tool or snap.tool == operation.tool) then
    local slots = Inventory.slots()
    for slot = 1, 9 do
      if slots and slots[slot] == operation.previous then
        Inventory.select(snap, slot)
        return
      end
    end
  end
end
function Inventory.step(snap)
  if lease then
    if lease.character ~= snap.character or snap.now >= lease.deadline then
      Inventory.close(true)
      retryAt = snap.now + 1
    elseif lease.closeRequested then
      Inventory.close()
    end
  end
  if not pending then
    return
  end
  if pending.character ~= snap.character then
    pending = nil
    return
  end
  local consumed = not owned(pending.tool) or (tonumber(pending.tool:GetAttribute("Count")) or 0) < pending.count
  local popped = snap.character:GetAttribute("TotemPoppedAt")
  local confirmed = consumed and (snap.character:GetAttribute("OffhandItem") == "totem" or popped ~= nil and popped ~= pending.pop)
    or pending.done and pending.accepted and snap.character:GetAttribute("OffhandItem") == "totem"
  if confirmed or pending.done and not pending.accepted then
    restoreHand(snap, pending)
    pending, retryAt = nil, confirmed and 0 or snap.now + 1
  elseif snap.now - pending.at >= 3 then
    if not pending.expired then
      pending.expired = true
      restoreHand(snap, pending)
      Inventory.close(true)
    end
    -- A yielding RPC may finish later; don't launch a duplicate while it is outstanding.
    if pending.done then
      pending, retryAt = nil, snap.now + 1
    end
  end
end
function Inventory.totem(snap)
  Inventory.step(snap)
  if pending then
    if pending.expired then
      return nil
    end
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
    at = snap.now,
  }
  pending = operation
  task.spawn(function()
    -- Never send a reserve transfer if the inventory closed before dispatch.
    if utils.getLocalPlayer().Character ~= operation.character or not operation.hand and not visible() then
      operation.done, operation.accepted = true, false
      return
    end
    local ok, result = pcall(remote.InvokeServer, remote, "EquipOffhand", tool)
    operation.done, operation.accepted = true, ok and result ~= nil and result ~= false
    if operation.accepted and utils.getLocalPlayer().Character == operation.character and cachedFn then
      pcall(cachedFn)
    end
  end)
  return false
end
function Inventory.busy() return lease ~= nil or pending ~= nil and pending.hand and not pending.expired end
function Inventory.reset()
  Inventory.close(true)
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
