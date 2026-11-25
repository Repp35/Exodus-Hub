-- [[ mcpinventory ]]
--!optimize 2
local Inventory = {}
local utils
local functions, scanAt, slotTable, session, nextTransition = {}, 0, nil, nil, 0
local panel, hud, outstandingOffhand
local MIN_DELAY = 0.4
local function owned(tool)
  local player = utils.getLocalPlayer()
  return typeof(tool) == "Instance" and tool:IsA("Tool") and (tool.Parent == player.Character or tool.Parent == player:FindFirstChild("Backpack"))
end
local function available(tool) return owned(tool) and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function discover()
  if functions.refresh and functions.open then
    return
  end
  if os.clock() < scanAt then
    return
  end
  scanAt = os.clock() + 5
  local env = type(getgenv) == "function" and getgenv() or _G
  if type(env.getgc) ~= "function" then
    return
  end
  local ok, objects = pcall(env.getgc, false)
  if not ok or type(objects) ~= "table" then
    return
  end
  local scripts = utils.getLocalPlayer():FindFirstChild("PlayerScripts")
  for _, fn in pairs(objects) do
    if type(fn) ~= "function" then
      continue
    end
    local got, environment = pcall(getfenv, fn)
    local source = got and environment and environment.script
    if typeof(source) ~= "Instance" or source.Parent ~= scripts or source.Name ~= "VoxelPackHUD" then
      continue
    end
    local named, name = pcall(debug.info, fn, "n")
    if named and name == "refreshTools" then
      functions.refresh = fn
    end
    if named and name == "setOpen" then
      functions.open = fn
    end
  end
end
function Inventory.setup(deps)
  utils = deps.Utils
  return true
end
function Inventory.visible()
  local gui = utils.getLocalPlayer():FindFirstChildOfClass("PlayerGui")
  local currentHud = gui and gui:FindFirstChild("VoxelPackHUD")
  if not currentHud then
    panel, hud = nil, nil
    return false
  end
  if currentHud ~= hud or not panel or not panel:IsDescendantOf(currentHud) then
    panel, hud = currentHud:FindFirstChild("Inventory", true), currentHud
  end
  local parent = panel
  if not parent or not parent:IsA("GuiObject") then
    return false
  end
  while parent and parent ~= gui do
    if parent:IsA("GuiObject") and not parent.Visible or parent:IsA("ScreenGui") and not parent.Enabled then
      return false
    end
    parent = parent.Parent
  end
  return parent == gui
end
function Inventory.slots()
  discover()
  if slotTable then
    return slotTable
  end
  local env = type(getgenv) == "function" and getgenv() or _G
  local getter = env.getupvalues or (env.debug and env.debug.getupvalues)
  if not functions.refresh or type(getter) ~= "function" then
    return nil
  end
  local ok, values = pcall(getter, functions.refresh)
  if not ok or type(values) ~= "table" then
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
      if found and found ~= value then
        return nil
      end
      found = value
    end
  end
  slotTable = found
  return found
end
function Inventory.begin(actor, snap)
  if session then
    return session.actor == actor and not session.cancelled
  end
  if
    not Inventory.visible()
    and (
      snap.player:GetAttribute("MenuOpen") == true
      or snap.character:GetAttribute("EatingApple") == true
      or snap.character:GetAttribute("DrinkingPotion") == true
      or snap.character:GetAttribute("BowDrawStarted")
      or snap.player:GetAttribute("OffhandUsing") == true
    )
  then
    return false
  end
  discover()
  if not functions.open or not Inventory.slots() then
    return false
  end
  session = { actor = actor, character = snap.character, started = snap.now, lastAction = snap.now, owned = not Inventory.visible(), tickets = {} }
  return true
end
function Inventory.ready(actor, snap, urgent)
  local current = session
  if not current or current.actor ~= actor or current.cancelled or current.character ~= snap.character then
    return false
  end
  if not current.requested then
    if snap.now < nextTransition then
      return false
    end
    current.requested, current.lastAction = true, snap.now
    if current.owned then
      nextTransition = snap.now + MIN_DELAY
      local ok = pcall(functions.open, true)
      if not ok then
        current.failed = true
      end
    end
  end
  if current.failed or not Inventory.visible() or utils.getLocalPlayer():GetAttribute("MenuOpen") ~= true then
    current.visibleAt = nil
    return false
  end
  current.visibleAt = current.visibleAt or snap.now
  return urgent or snap.now - current.visibleAt >= MIN_DELAY
end
local function ticket(actor, snap, kind)
  if not Inventory.ready(actor, snap, actor == "totem") or session.closing then
    return nil
  end
  for _, pending in ipairs(session.tickets) do
    if not pending.confirmed then
      return nil
    end
  end
  local value = { kind = kind, character = snap.character, at = snap.now }
  session.tickets[#session.tickets + 1] = value
  session.lastAction = snap.now
  return value
end
function Inventory.move(actor, snap, tool, from, destination, allowSpeed)
  local values = Inventory.slots()
  if not values or from < 10 or from > 36 or destination < 1 or destination > 9 or values[from] ~= tool or not available(tool) then
    return nil
  end
  local previous = values[destination]
  if available(previous) and not (allowSpeed and previous:GetAttribute("ClassItem") == "SpeedPotion") then
    return nil
  end
  local operation = ticket(actor, snap, "move")
  if not operation then
    return nil
  end
  operation.tool, operation.from, operation.destination = tool, from, destination
  values[from], values[destination] = allowSpeed and previous or nil, tool
  operation.done = pcall(functions.refresh)
  return operation
end
function Inventory.offhand(actor, snap, tool, immediate)
  if outstandingOffhand and not outstandingOffhand.confirmed then
    if not outstandingOffhand.done then
      return nil
    end
    if outstandingOffhand.accepted and outstandingOffhand.character == snap.character then
      return nil
    end
    outstandingOffhand = nil
  end
  if not available(tool) or tool:GetAttribute("ClassItem") ~= "Totem" then
    return nil
  end
  local values = Inventory.slots()
  if not values then
    return nil
  end
  local from
  for index = 1, 36 do
    if values[index] == tool then
      from = index
      break
    end
  end
  if not from then
    return nil
  end
  local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
  local remote = remotes and remotes:FindFirstChild("InventoryAction")
  if not remote or not remote:IsA("RemoteFunction") then
    return nil
  end
  if immediate and from > 9 and not Inventory.visible() then return nil end
  local operation = immediate and { kind = "offhand", character = snap.character, at = snap.now, immediate = true }
    or ticket(actor, snap, "offhand")
  if not operation then
    return nil
  end
  operation.tool, operation.from, operation.count = tool, from, tonumber(tool:GetAttribute("Count")) or 1
  operation.popAt = snap.character:GetAttribute("TotemPoppedAt")
  if session then
    for _, previous in ipairs(session.tickets) do
      if previous.kind == "move" and previous.tool == tool and previous.destination == from then previous.usedBy = operation end
    end
  end
  outstandingOffhand = operation
  task.spawn(function()
    local ok, result = pcall(remote.InvokeServer, remote, "EquipOffhand", tool)
    operation.done, operation.accepted = true, ok and result ~= nil and result ~= false
    if not operation.accepted or operation.character ~= utils.getLocalPlayer().Character then
      return
    end
    -- Mirror VoxelPackHUD.swapHovered: consume source and keep any returned shield in its slot.
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
    pcall(functions.refresh)
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
  local values = Inventory.slots()
  local valid = false
  if operation.kind == "move" then
    valid = operation.done
      and values
      and values[operation.destination] == operation.tool
      and values[operation.from] ~= operation.tool
      and available(operation.tool)
    if not valid and operation.done and operation.usedBy then valid = Inventory.confirm(operation.usedBy, snap) end
  else
    local consumed = not owned(operation.tool) or (tonumber(operation.tool:GetAttribute("Count")) or operation.count) < operation.count
        local popped = snap.character:GetAttribute("TotemPoppedAt")
    local equipped = snap.character:GetAttribute("OffhandItem") == "totem" or popped ~= nil and popped ~= operation.popAt
    valid = operation.done and operation.accepted and consumed and equipped
    if valid and values then
      if not owned(operation.tool) and values[operation.from] == operation.tool then
        values[operation.from] = nil
        pcall(functions.refresh)
      end
      for _, tool in pairs(values) do
        if tool == operation.tool and not available(tool) then
          valid = false
          break
        end
      end
    end
  end
  if not valid then
    operation.stableAt = nil
    return false
  end
  operation.stableAt = operation.stableAt or snap.now
  operation.confirmed = operation.immediate or snap.now - operation.stableAt >= (operation.kind == "offhand" and 0 or MIN_DELAY)
  return operation.confirmed
end
function Inventory.finish(actor, snap)
  local current = session
  if not current then
    return true
  end
  if current.actor ~= actor or current.cancelled then
    return false
  end
  for _, pending in ipairs(current.tickets) do
    if not Inventory.confirm(pending, snap) then
      return false
    end
  end
  if snap.now - current.lastAction < MIN_DELAY or snap.now < nextTransition then
    return false
  end
  if current.owned and Inventory.visible() then
    if current.closing then
      return false
    end
    current.closing = true
    nextTransition = snap.now + MIN_DELAY
    pcall(functions.open, false)
    return false
  end
  if current.owned and utils.getLocalPlayer():GetAttribute("MenuOpen") == true then
    return false
  end
  session = nil
  return true
end
function Inventory.cancel(actor)
  if session and (not actor or session.actor == actor) then
    session.cancelled = true
  end
end
function Inventory.step()
  local current = session
  if not current then
    return
  end
  local now = os.clock()
  if current.cancelled then
    if now < math.max(nextTransition, current.lastAction + MIN_DELAY) then
      return
    end
    if current.owned and Inventory.visible() and functions.open then
      pcall(functions.open, false)
      nextTransition = now + MIN_DELAY
    end
    session = nil
  elseif now - current.started > 5 and not current.reported then
    current.reported = true
    utils.recordError(
      "mcpvp.inventory",
      "Aguardando confirmação: " .. current.actor .. ". Nenhuma nova tentativa será enviada enquanto houver ação pendente."
    )
  end
end
function Inventory.busy() return session ~= nil end
function Inventory.status() return session and { actor = session.actor, pending = true, reported = session.reported == true } or { pending = false } end
function Inventory.teardown()
  local current = session
  Inventory.cancel()
  Inventory.step()
  if current and session == current then
    local delay = math.max(nextTransition, current.lastAction + MIN_DELAY) - os.clock()
    task.delay(math.max(0, delay), function()
      if session == current then
        Inventory.step()
      end
    end)
  end
end
Inventory.__contract = {
  provides = { "setup", "visible", "slots", "begin", "ready", "move", "offhand", "confirm", "finish", "cancel", "step", "busy", "status", "teardown" },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getLocalPlayer", "recordError" } },
}
return Inventory
