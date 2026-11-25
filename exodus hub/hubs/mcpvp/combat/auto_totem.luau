-- [[ autototem ]]
--!optimize 2
local Totem = {}
local native, utils
local reserved
local functions, scanAt, job, nextRun, rpcBusy = {}, 0, nil, 0, false
local function visible()
  local gui = utils.getLocalPlayer():FindFirstChildOfClass("PlayerGui")
  local hud = gui and gui:FindFirstChild("VoxelPackHUD")
  if not hud then return false end
  for _, object in ipairs(hud:GetDescendants()) do
    if object.Name == "Inventory" and object:IsA("GuiObject") and object.Visible then
      local parent, shown = object.Parent, true
      while parent and parent ~= gui do
        if (parent:IsA("GuiObject") and not parent.Visible) or (parent:IsA("ScreenGui") and not parent.Enabled) then shown = false break end
        parent = parent.Parent
      end
      if shown then return true end
    end
  end
  return false
end
local function discover()
  if functions.refresh and functions.open then return end
  if os.clock() < scanAt then return end
  scanAt = os.clock() + 5
  local env = type(getgenv) == "function" and getgenv() or _G
  if type(env.getgc) ~= "function" then return end
  local ok, objects = pcall(env.getgc, false)
  if not ok then return end
  local scripts = utils.getLocalPlayer():FindFirstChild("PlayerScripts")
  for _, fn in pairs(objects) do
    if type(fn) ~= "function" then continue end
    local got, environment = pcall(getfenv, fn)
    local source = got and environment and environment.script
    if typeof(source) ~= "Instance" or source.Parent ~= scripts or source.Name ~= "VoxelPackHUD" then continue end
    local named, name = pcall(debug.info, fn, "n")
    if named and name == "refreshTools" then functions.refresh = fn end
    if named and name == "setOpen" then functions.open = fn end
  end
end
local function slots()
  discover()
  local env = type(getgenv) == "function" and getgenv() or _G
  local getter = env.getupvalues or (env.debug and env.debug.getupvalues)
  if not functions.refresh or type(getter) ~= "function" then return nil end
  local ok, values = pcall(getter, functions.refresh)
  if not ok then return nil end
  local player, found = utils.getLocalPlayer(), nil
  for _, value in pairs(values) do
    if type(value) ~= "table" or getmetatable(value) ~= nil then continue end
    local valid, count = true, 0
    for key, tool in pairs(value) do
      if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 36
        or typeof(tool) ~= "Instance" or not tool:IsA("Tool")
        or (tool.Parent ~= player.Character and tool.Parent ~= player:FindFirstChild("Backpack")) then valid = false break end
      count += 1
    end
    if valid and count > 0 then
      if found and found ~= value then return nil end
      found = value
    end
  end
  return found
end
local function totem(tool)
  return tool and tool.Parent and tool:GetAttribute("ClassItem") == "Totem" and (tonumber(tool:GetAttribute("Count")) or 1) > 0
end
local function find(tableSlots, first, last)
  for slot = first, last do
    if totem(tableSlots[slot]) then return tableSlots[slot], slot end
  end
end
local function empty(tableSlots)
  for slot = 1, 9 do if not tableSlots[slot] and (not reserved or not reserved(slot)) then return slot end end
end
local function finish()
  local previous = job
  job = nil
  if not previous then return end
  if previous.opened and functions.open and visible() then pcall(functions.open, false) end
  local snap = native.snapshot()
  if snap and snap.character == previous.character then
    local current = snap.tool
    if current == previous.tool or current == nil then
      local sword = native.findSword(snap)
      if sword then native.equip(snap, sword) end
    end
  end
  nextRun = os.clock() + 0.35
end
function Totem.setup(deps)
  native, utils = deps.Native, deps.Utils
  return true
end
function Totem.reset() finish() end
function Totem.teardown() finish() functions = {} end
function Totem.busy() return job ~= nil end
function Totem.step(snap)
  if not utils.isActive() or not utils.getConfigValue("MCAutoTotem") then finish() return end
  if job and (job.character ~= snap.character or snap.now > job.deadline) then finish() return end
  local tableSlots = slots()
  if not tableSlots then if job then finish() end return end
  if not job then
    if snap.now < nextRun or rpcBusy or native.blocked(snap) then return end
    local missing = snap.character:GetAttribute("OffhandItem") ~= "totem"
    local hotbar = find(tableSlots, 1, 9)
    local reserve = find(tableSlots, 10, 36)
    if not missing and not (reserve and empty(tableSlots)) then return end
    local tool = missing and (hotbar or reserve) or reserve
    if not tool then return end
    job = { character = snap.character, tool = tool, stage = "prepare", deadline = snap.now + 3, needsInventory = not hotbar or not missing, missing = missing, started = snap.now }
  end
  local current = job
  if current.stage == "prepare" then
    if current.needsInventory then
      if not functions.open then finish() return end
      current.opened = not visible()
      if current.opened then
        local ok = pcall(functions.open, true)
        if not ok then finish() return end
      end
      current.stage, current.ready = "inventory", snap.now + 0.18
      return
    end
    if not native.equip(snap, current.tool) then finish() return end
    current.stage, current.ready = "offhand", snap.now + 0.08
    return
  end
  if current.stage == "inventory" then
    if not visible() then finish() return end
    if snap.now < current.ready then return end
    current.stage = current.missing and "offhand" or "refill"
  end
  if current.stage == "offhand" then
    if snap.now < current.ready then return end
    if current.needsInventory and not visible() then finish() return end
    if not current.needsInventory and snap.character:FindFirstChildOfClass("Tool") ~= current.tool then finish() return end
    if snap.character:GetAttribute("OffhandItem") == "totem" then current.stage = "refill" return end
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("InventoryAction")
    if not remote or not remote:IsA("RemoteFunction") then finish() return end
    current.stage, rpcBusy = "confirm", true
    task.spawn(function()
      local ok, result = pcall(remote.InvokeServer, remote, "EquipOffhand", current.tool)
      rpcBusy = false
      if job == current then current.result = ok and result ~= false and result ~= nil end
    end)
    return
  end
  if current.stage == "confirm" then
    if snap.character:GetAttribute("OffhandItem") == "totem" then
      current.stage = "refill"
    elseif current.result == false then finish() end
    return
  end
  if current.stage == "refill" then
    -- Every inventory-to-hotbar move requires the native inventory to be visibly open.
    local tool, from = find(tableSlots, 10, 36)
    local destination = empty(tableSlots)
    if not tool or not destination then finish() return end
    if not visible() then
      if not functions.open then finish() return end
      current.opened = true
      local ok = pcall(functions.open, true)
      if not ok then finish() return end
      current.stage, current.ready, current.missing = "inventory", snap.now + 0.18, false
      return
    end
    if snap.now < (current.ready or 0) then return end
    if tableSlots[from] ~= tool or tableSlots[destination] then return end
    tableSlots[from], tableSlots[destination] = nil, tool
    local ok = pcall(functions.refresh)
    if not ok then tableSlots[from], tableSlots[destination] = tool, nil finish() return end
    current.ready = snap.now + 0.1
  end
end
function Totem.setReservations(callback) reserved = callback end
function Totem.inventorySlots() return slots() end
function Totem.inventoryVisible() return visible() end
function Totem.openInventory()
  discover()
  if visible() then return true end
  if not functions.open then return false end
  local ok = pcall(functions.open, true)
  return ok and visible()
end
function Totem.closeInventory()
  if functions.open and visible() then pcall(functions.open, false) end
end
function Totem.moveReserve(tool, from, destination)
  if not visible() then return false end
  local values = slots()
  if not values or values[from] ~= tool or from < 10 or destination < 1 or destination > 9 then return false end
  local previous = values[destination]
  if previous and previous.Parent and (tonumber(previous:GetAttribute("Count")) or 1) > 0 then return false end
  values[from], values[destination] = nil, tool
  local ok = pcall(functions.refresh)
  if not ok then values[from], values[destination] = tool, previous end
  return ok
end
Totem.__contract = {
  provides = { "setup", "step", "busy", "reset", "teardown", "inventorySlots", "inventoryVisible", "openInventory", "closeInventory", "moveReserve", "setReservations" },
  requires = { Native = "mcpnative", Utils = "utils" },
  requiresMethods = { Native = { "snapshot", "findSword", "equip", "blocked" }, Utils = { "getLocalPlayer", "isActive", "getConfigValue" } },
}
return Totem
