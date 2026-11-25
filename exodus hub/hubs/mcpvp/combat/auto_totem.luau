-- [[ autototem ]]
--!optimize 2
local Totem = {}
local native, utils
local reserved
local functions, scanAt, job, nextRun, rpcBusy = {}, 0, nil, 0, false
local cachedSlots, cachedRefresh, failed, owner
local function fingerprint(values, snap)
  local parts = { tostring(snap.character:GetAttribute("OffhandItem")) }
  for slot = 1, 36 do
    local tool = values[slot]
    parts[#parts + 1] = tool and tostring(tool) .. tostring(tool:GetAttribute("Count")) or "_"
  end
  return table.concat(parts, ";")
end
local inventoryGui, inventoryHud
local function visible()
  local gui = utils.getLocalPlayer():FindFirstChildOfClass("PlayerGui")
  local hud = gui and gui:FindFirstChild("VoxelPackHUD")
  if not hud then
    inventoryGui, inventoryHud = nil, nil
    return false
  end
  if inventoryHud ~= hud or not inventoryGui or not inventoryGui:IsDescendantOf(hud) then
    inventoryGui, inventoryHud = nil, hud
    for _, object in ipairs(hud:GetDescendants()) do
      if object.Name == "Inventory" and object:IsA("GuiObject") then
        inventoryGui = object
        break
      end
    end
  end
  if not inventoryGui then
    return false
  end
  local parent = inventoryGui
  while parent and parent ~= gui do
    if parent:IsA("GuiObject") and not parent.Visible or parent:IsA("ScreenGui") and not parent.Enabled then
      return false
    end
    parent = parent.Parent
  end
  return parent == gui
end
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
  if not ok then
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
local function slots()
  discover()
  local env = type(getgenv) == "function" and getgenv() or _G
  local getter = env.getupvalues or (env.debug and env.debug.getupvalues)
  if not functions.refresh or type(getter) ~= "function" then
    return nil
  end
  if cachedRefresh == functions.refresh and cachedSlots then
    return cachedSlots
  end
  local ok, values = pcall(getter, functions.refresh)
  if not ok then
    return nil
  end
  local player, found = utils.getLocalPlayer(), nil
  for _, value in pairs(values) do
    if type(value) ~= "table" or getmetatable(value) ~= nil then
      continue
    end
    local valid, count = true, 0
    for key, tool in pairs(value) do
      if
        type(key) ~= "number"
        or key % 1 ~= 0
        or key < 1
        or key > 36
        or typeof(tool) ~= "Instance"
        or not tool:IsA("Tool")
        or (tool.Parent ~= player.Character and tool.Parent ~= player:FindFirstChild("Backpack"))
      then
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
  cachedSlots, cachedRefresh = found, functions.refresh
  return found
end
local function totem(tool) return tool and tool.Parent and tool:GetAttribute("ClassItem") == "Totem" and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function find(tableSlots, first, last)
  for slot = first, last do
    if totem(tableSlots[slot]) then
      return tableSlots[slot], slot
    end
  end
  return nil
end
local function empty(tableSlots)
  for slot = 1, 9 do
    local tool = tableSlots[slot]
    if (not tool or not tool.Parent or (tonumber(tool:GetAttribute("Count")) or 1) <= 0) and (not reserved or not reserved(slot)) then
      return slot
    end
  end
  return nil
end
local function finish()
  local previous = job
  job = nil
  if not previous then
    return
  end
  if previous.opened and functions.open and visible() then
    pcall(functions.open, false)
  end
  local snap = native.snapshot()
  if snap and snap.character == previous.character then
    local current = snap.tool
    if current == previous.tool or current == nil then
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
  end
  nextRun = os.clock() + 0.35
end
function Totem.setup(deps)
  native, utils = deps.Native, deps.Utils
  return true
end
function Totem.reset() finish() end
function Totem.teardown()
  finish()
  functions = {}
  cachedSlots, cachedRefresh, failed, owner = nil, nil, nil, nil
  inventoryGui, inventoryHud = nil, nil
end
function Totem.busy() return job ~= nil end
function Totem.step(snap)
  if not utils.isActive() or not utils.getConfigValue("MCAutoTotem") then
    failed = nil
    finish()
    return
  end
  if owner ~= snap.character then
    finish()
    owner, failed, cachedSlots = snap.character, nil, nil
  end
  if not job and snap.now < nextRun then
    return
  end
  local tableSlots = slots()
  if not tableSlots then
    if job then
      finish()
    end
    nextRun = snap.now + 0.5
    return
  end
  if job and snap.now > job.deadline then
    failed = fingerprint(tableSlots, snap)
    finish()
    return
  end
  if not job then
    nextRun = snap.now + 0.2
    if failed == fingerprint(tableSlots, snap) then
      return
    end
    if rpcBusy or native.blocked(snap) then
      return
    end
    local missing = snap.character:GetAttribute("OffhandItem") ~= "totem"
    local hotbar = find(tableSlots, 1, 9)
    local reserve = find(tableSlots, 10, 36)
    if not missing and not (reserve and empty(tableSlots)) then
      return
    end
    local tool = missing and (hotbar or reserve) or reserve
    if not tool then
      return
    end
    job = {
      character = snap.character,
      tool = tool,
      previousTool = snap.tool,
      stage = "prepare",
      deadline = snap.now + 3,
      needsInventory = not hotbar or not missing,
      missing = missing,
      started = snap.now,
    }
  end
  local current = job
  if current.stage == "prepare" then
    if current.needsInventory then
      if not functions.open then
        failed = fingerprint(tableSlots, snap)
        finish()
        return
      end
      current.opened = not visible()
      if current.opened then
        local ok = pcall(functions.open, true)
        if not ok then
          failed = fingerprint(tableSlots, snap)
          finish()
          return
        end
      end
      current.stage, current.ready = "inventory", snap.now + 0.18
      return
    end
    if not native.equip(snap, current.tool) then
      finish()
      return
    end
    current.stage, current.ready = "offhand", snap.now + 0.08
    return
  end
  if current.stage == "inventory" then
    if not visible() then
      failed = fingerprint(tableSlots, snap)
      finish()
      return
    end
    if snap.now < current.ready then
      return
    end
    current.stage = current.missing and "offhand" or "refill"
  end
  if current.stage == "offhand" then
    if snap.now < current.ready then
      return
    end
    if current.needsInventory and not visible() then
      finish()
      return
    end
    if not current.needsInventory and snap.character:FindFirstChildOfClass("Tool") ~= current.tool then
      return
    end
    if snap.character:GetAttribute("OffhandItem") == "totem" then
      current.stage = "refill"
      return
    end
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("InventoryAction")
    if not remote or not remote:IsA("RemoteFunction") then
      finish()
      return
    end
    current.stage, rpcBusy = "confirm", true
    task.spawn(function()
      local ok, result = pcall(remote.InvokeServer, remote, "EquipOffhand", current.tool)
      rpcBusy = false
      if job == current then
        current.result = ok and result ~= false and result ~= nil
      end
    end)
    return
  end
  if current.stage == "confirm" then
    if snap.character:GetAttribute("OffhandItem") == "totem" then
      current.stage = "refill"
    elseif current.result == false then
      failed = fingerprint(tableSlots, snap)
      finish()
    end
    return
  end
  if current.stage == "refill" then
    if current.pending then
      if tableSlots[current.to] == current.pending and totem(current.pending) then
        current.pending = nil
      else
        if snap.now >= current.confirmAt then
          failed = fingerprint(tableSlots, snap)
          finish()
        end
        return
      end
    end
    -- Every inventory-to-hotbar move requires the native inventory to be visibly open.
    local tool, from = find(tableSlots, 10, 36)
    local destination = empty(tableSlots)
    if not tool or not destination then
      finish()
      return
    end
    if not visible() then
      if not functions.open then
        failed = fingerprint(tableSlots, snap)
        finish()
        return
      end
      current.opened = true
      local ok = pcall(functions.open, true)
      if not ok then
        finish()
        return
      end
      current.stage, current.ready, current.missing = "inventory", snap.now + 0.18, false
      return
    end
    if snap.now < (current.ready or 0) then
      return
    end
    local occupied = tableSlots[destination]
    if tableSlots[from] ~= tool or occupied and occupied.Parent and (tonumber(occupied:GetAttribute("Count")) or 1) > 0 then
      return
    end
    if not Totem.moveReserve(tool, from, destination) then
      failed = fingerprint(tableSlots, snap)
      finish()
      return
    end
    current.pending, current.to, current.confirmAt = tool, destination, snap.now + 0.8
    current.ready = snap.now + 0.1
  end
end
function Totem.setReservations(callback) reserved = callback end
function Totem.inventorySlots() return slots() end
function Totem.inventoryVisible() return visible() end
function Totem.openInventory()
  discover()
  if visible() then
    return true
  end
  if not functions.open then
    return false
  end
  local ok = pcall(functions.open, true)
  return ok and visible()
end
function Totem.closeInventory()
  if functions.open and visible() then
    pcall(functions.open, false)
  end
end
function Totem.moveReserve(tool, from, destination)
  if not visible() then
    return false
  end
  local values = slots()
  if
    not values
    or values[from] ~= tool
    or not tool.Parent
    or (tonumber(tool:GetAttribute("Count")) or 1) <= 0
    or from < 10
    or from > 36
    or destination < 1
    or destination > 9
  then
    return false
  end
  local previous = values[destination]
  if previous and previous.Parent and (tonumber(previous:GetAttribute("Count")) or 1) > 0 then
    return false
  end
  values[from], values[destination] = nil, tool
  local ok = pcall(functions.refresh)
  if not ok then
    if values[destination] == tool then
      values[from], values[destination] = tool, previous
    end
    return false
  end
  return values[destination] == tool and values[from] ~= tool
end
function Totem.swapSpeedForStrength(tool, from, destination)
  if not visible() or not tool.Parent or (tonumber(tool:GetAttribute("Count")) or 1) <= 0 or from < 10 or from > 36 or destination < 1 or destination > 9 then
    return false
  end
  local values = slots()
  if not values or values[from] ~= tool or tool:GetAttribute("ClassItem") ~= "StrengthPotion" then
    return false
  end
  local previous = values[destination]
  if previous and previous.Parent and (tonumber(previous:GetAttribute("Count")) or 1) > 0 and previous:GetAttribute("ClassItem") ~= "SpeedPotion" then
    return false
  end
  values[from], values[destination] = previous, tool
  local ok = pcall(functions.refresh)
  if not ok then
    if values[destination] == tool then
      values[from], values[destination] = tool, previous
    end
    return false
  end
  return values[destination] == tool and values[from] ~= tool
end
Totem.__contract = {
  provides = {
    "setup",
    "step",
    "busy",
    "reset",
    "teardown",
    "inventorySlots",
    "inventoryVisible",
    "openInventory",
    "closeInventory",
    "moveReserve",
    "setReservations",
    "swapSpeedForStrength",
  },
  requires = { Native = "mcpnative", Utils = "utils" },
  requiresMethods = { Native = { "snapshot", "findSword", "equip", "blocked" }, Utils = { "getLocalPlayer", "isActive", "getConfigValue" } },
}
return Totem
