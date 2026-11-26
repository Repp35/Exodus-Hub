-- [[ mcpinventory ]]
--!optimize 2
local Inventory = {}
local utils, bridge
local refresh, slots, hud, panel, session, offhand
local transitionAt = 0
local DELAY = 0.4
local function owned(tool)
  local player = utils.getLocalPlayer()
  return typeof(tool) == "Instance"
    and tool:IsA("Tool")
    and tool.Parent ~= nil
    and (tool.Parent == player.Character or tool.Parent == player:FindFirstChild("Backpack"))
end
local function available(tool) return owned(tool) and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
function Inventory.setup(deps)
  utils, bridge = deps.Utils, deps.Bridge
  return true
end
function Inventory.visible()
  local gui = utils.getLocalPlayer():FindFirstChildOfClass("PlayerGui")
  local current = gui and gui:FindFirstChild("VoxelPackHUD")
  if current ~= hud or not panel or not panel:IsDescendantOf(current) then
    hud, panel = current, current and current:FindFirstChild("Inventory", true)
  end
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
function Inventory.slots()
  local fn = bridge.get("refresh")
  if fn ~= refresh then
    refresh, slots = fn, nil
  end
  if slots then
    return slots
  end
  local values = bridge.upvalues(refresh)
  if not values then
    return nil
  end
  local found
  for _, value in pairs(values) do
    if type(value) ~= "table" or getmetatable(value) ~= nil then
      continue
    end
    local valid, count = true, 0
    for index, tool in pairs(value) do
      if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 36 or typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
        valid = false
        break
      end
      count += 1
    end
    if valid and count > 0 then
      if found then
        return nil
      end
      found = value
    end
  end
  slots = found
  return slots
end
function Inventory.begin(actor, snap)
  if session then
    if actor == "totem" and session.actor ~= actor and session.character == snap.character and not session.cancelled and not session.closing then
      session.actor, session.at = actor, snap.now
      if session.pending then
        session.pending.urgent = true
      end
    end
    return session.actor == actor and not session.cancelled
  end
  if not bridge.get("open") or not Inventory.slots() then
    return false
  end
  local visible = Inventory.visible()
  if
    not visible
    and (
      snap.player:GetAttribute("MenuOpen")
      or snap.character:GetAttribute("EatingApple")
      or snap.character:GetAttribute("DrinkingPotion")
      or snap.character:GetAttribute("BowDrawStarted")
      or snap.player:GetAttribute("OffhandUsing")
    )
  then
    return false
  end
  session = { actor = actor, character = snap.character, owned = not visible, at = snap.now, actionAt = snap.now }
  return true
end
function Inventory.ready(actor, snap, urgent)
  local current = session
  if not current or current.actor ~= actor or current.character ~= snap.character or current.cancelled or current.closing then
    return false
  end
  if not current.opened then
    if not urgent and snap.now < transitionAt then
      return false
    end
    current.opened = true
    if current.owned then
      transitionAt = snap.now + (urgent and 0 or DELAY)
      local fn = bridge.get("open")
      if not fn or not pcall(fn, true) then
        current.cancelled = true
        return false
      end
    end
  end
  if not Inventory.visible() or snap.player:GetAttribute("MenuOpen") ~= true then
    current.visibleAt = nil
    return false
  end
  current.visibleAt = current.visibleAt or snap.now
  return urgent or snap.now - current.visibleAt >= DELAY
end
local function ticket(actor, snap, kind)
  if not Inventory.ready(actor, snap, actor == "totem") then
    return nil
  end
  if session.pending and not Inventory.confirm(session.pending, snap) then
    return nil
  end
  local operation = { kind = kind, character = snap.character, at = snap.now, urgent = actor == "totem" }
  session.pending, session.actionAt = operation, snap.now
  return operation
end
function Inventory.move(actor, snap, tool, from, destination, swap)
  local values = Inventory.slots()
  if
    not values
    or type(from) ~= "number"
    or type(destination) ~= "number"
    or from < 10
    or from > 36
    or destination < 1
    or destination > 9
    or values[from] ~= tool
    or not available(tool)
  then
    return nil
  end
  local previous = values[destination]
  if available(previous) and not (swap == "totem" or swap == true and previous:GetAttribute("ClassItem") == "SpeedPotion") then
    return nil
  end
  local operation = ticket(actor, snap, "move")
  if not operation then
    return nil
  end
  operation.tool, operation.from, operation.destination = tool, from, destination
  values[from], values[destination] = swap and previous or nil, tool
  operation.done = pcall(refresh)
  if not operation.done then
    values[from], values[destination] = tool, previous
    session.cancelled = true
  end
  return operation
end
function Inventory.offhand(actor, snap, tool, immediate)
  if offhand and not offhand.confirmed then
    if not offhand.done or offhand.accepted and offhand.character == snap.character then
      return nil
    end
    offhand = nil
  end
  local values = Inventory.slots()
  if not values or not available(tool) or tool:GetAttribute("ClassItem") ~= "Totem" then
    return nil
  end
  local from
  for slot = 1, 36 do
    if values[slot] == tool then
      from = slot
      break
    end
  end
  if not from or immediate and from > 9 and not Inventory.visible() then
    return nil
  end
  local remoteFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
  local remote = remoteFolder and remoteFolder:FindFirstChild("InventoryAction")
  if not remote or not remote:IsA("RemoteFunction") then
    return nil
  end
  local previous = session and session.pending
  local operation = immediate and { kind = "offhand", character = snap.character, at = snap.now, urgent = true } or ticket(actor, snap, "offhand")
  if not operation then
    return nil
  end
  operation.tool, operation.from, operation.count = tool, from, tonumber(tool:GetAttribute("Count")) or 1
  operation.popAt = snap.character:GetAttribute("TotemPoppedAt")
  if previous and previous.kind == "move" and previous.tool == tool then
    previous.usedBy = operation
  end
  offhand = operation
  task.spawn(function()
    local ok, result = pcall(remote.InvokeServer, remote, "EquipOffhand", tool)
    operation.done, operation.accepted = true, ok and result ~= nil and result ~= false
    if not operation.accepted or utils.getLocalPlayer().Character ~= operation.character then
      return
    end
    if values[from] == tool and not tool.Parent then
      values[from] = nil
    end
    if typeof(result) == "Instance" and not values[from] then
      for index, other in pairs(values) do
        if other == result then
          values[index] = nil
        end
      end
      values[from] = result
    end
    if refresh then
      pcall(refresh)
    end
  end)
  return operation
end
function Inventory.confirm(operation, snap)
  if not operation or operation.character ~= snap.character then
    return false
  end
  if operation.confirmed then
    return true
  end
  local valid
  if operation.kind == "move" then
    local values = Inventory.slots()
    valid = operation.done
      and values
      and values[operation.destination] == operation.tool
      and values[operation.from] ~= operation.tool
      and available(operation.tool)
    if not valid and operation.usedBy then
      valid = Inventory.confirm(operation.usedBy, snap)
    end
  else
    local consumed = not owned(operation.tool) or (tonumber(operation.tool:GetAttribute("Count")) or operation.count) < operation.count
    local popped = snap.character:GetAttribute("TotemPoppedAt")
    -- Replicated consumption plus offhand/pop state already confirms the equip.
    -- Do not wait for InvokeServer's return before replacing a totem that just popped.
    valid = consumed
      and (snap.character:GetAttribute("OffhandItem") == "totem" or popped ~= nil and popped ~= operation.popAt)
  end
  if not valid then
    operation.stableAt = nil
    return false
  end
  operation.stableAt = operation.stableAt or snap.now
  operation.confirmed = operation.urgent or snap.now - operation.stableAt >= DELAY
  return operation.confirmed
end
function Inventory.finish(actor, snap)
  if not session then
    return true
  end
  local current = session
  if current.actor ~= actor or current.cancelled then
    return false
  end
  if current.pending and not Inventory.confirm(current.pending, snap) then
    return false
  end
  if actor ~= "totem" and snap.now < math.max(transitionAt, current.actionAt + DELAY) then
    return false
  end
  if current.owned and Inventory.visible() then
    if not current.closing then
      current.closing, transitionAt = true, snap.now + (actor == "totem" and 0 or DELAY)
      local fn = bridge.get("open")
      if not fn or not pcall(fn, false) then
        current.cancelled = true
      end
    end
    return false
  end
  if current.owned and snap.player:GetAttribute("MenuOpen") then
    return false
  end
  session = nil
  return true
end
function Inventory.cancel(actor)
  if session and (not actor or actor == session.actor) then
    session.cancelled = true
  end
end
function Inventory.step()
  local current = session
  if not current then
    return
  end
  local now = os.clock()
  if now - current.at > 5 and not current.cancelled then
    current.cancelled = true
    utils.recordError("mcpvp.inventory", "Operação sem confirmação; sessão cancelada sem repetir a ação pendente.")
  end
  if not current.cancelled or now < math.max(transitionAt, current.actionAt + DELAY) then
    return
  end
  if current.owned and Inventory.visible() then
    local fn = bridge.get("open")
    if fn then
      pcall(fn, false)
    end
    transitionAt = now + DELAY
  end
  session = nil
end
function Inventory.busy() return session ~= nil end
function Inventory.teardown()
  Inventory.cancel()
  local current = session
  Inventory.step()
  if current and session == current then
    task.delay(math.max(0, math.max(transitionAt, current.actionAt + DELAY) - os.clock()), function()
      if session == current then
        Inventory.step()
      end
    end)
  end
end
Inventory.__contract = {
  provides = { "setup", "visible", "slots", "begin", "ready", "move", "offhand", "confirm", "finish", "cancel", "step", "busy", "teardown" },
  requires = { Utils = "utils", Bridge = "mcpbridge" },
  requiresMethods = { Utils = { "getLocalPlayer", "recordError" }, Bridge = { "get", "upvalues" } },
}
return Inventory
