-- [[ autostrength ]]
--!optimize 2
local Strength = {}
local native, inventory, utils
local job, nextRun = nil, 0
local function alive(tool) return tool and tool.Parent and (tonumber(tool:GetAttribute("Count")) or 1) > 0 end
local function find(values, class, first, last)
  for slot = first, last do
    if alive(values[slot]) and values[slot]:GetAttribute("ClassItem") == class then return values[slot], slot end
  end
end
local function active(snap)
  return (tonumber(snap.character:GetAttribute("Effect_strength")) or 0) > workspace:GetServerTimeNow()
end
local function finish()
  local previous = job
  job = nil
  if not previous then return end
  if previous.opened then inventory.closeInventory() end
  local snap = native.snapshot()
  if snap and snap.character == previous.character and (snap.tool == previous.tool or snap.tool == nil) then
    local sword = native.findSword(snap)
    if sword then native.equip(snap, sword) end
  end
  nextRun = os.clock() + 0.35
end
function Strength.setup(deps) native, inventory, utils = deps.Native, deps.Inventory, deps.Utils return true end
function Strength.reset() finish() end
function Strength.busy() return job ~= nil end
function Strength.step(snap)
  if not utils.isActive() or not utils.getConfigValue("MCAutoStrength") then finish() return end
  if job and (job.character ~= snap.character or snap.now > job.deadline) then finish() return end
  if job then
    local current = job
    if current.stage == "inventory" then
      if not inventory.inventoryVisible() then finish() return end
      if snap.now < current.ready then return end
      inventory.swapSpeedForStrength(current.tool, current.from, current.to)
      finish()
      return
    end
    if current.stage == "confirm" then
      if active(snap) or not current.tool.Parent or (tonumber(current.tool:GetAttribute("Count")) or 0) < current.count then finish() end
      return
    end
    if active(snap) then finish() return end
    if snap.now < current.ready then return end
    if snap.tool ~= current.tool or native.blocked(snap) then finish() return end
    local onGround = snap.character:GetAttribute("VoxelGrounded")
    if onGround == false or math.abs(snap.root.AssemblyLinearVelocity.Y) > 5 then finish() return end
    current.count = tonumber(current.tool:GetAttribute("Count")) or 1
    if native.useItem(snap, current.tool, Vector3.new(0, -1, 0)) then
      current.stage, current.deadline = "confirm", snap.now + 0.9
    else finish() end
    return
  end
  if snap.now < nextRun or native.blocked(snap) then return end
  local values = inventory.inventorySlots()
  if not values then nextRun = snap.now + 0.5 return end
  local hotbar = find(values, "StrengthPotion", 1, 9)
  local reserve, from = find(values, "StrengthPotion", 10, 36)
  local _, speedSlot = find(values, "SpeedPotion", 1, 9)
  local destination = speedSlot
  if not destination and not hotbar then
    for slot = 1, 9 do if not alive(values[slot]) then destination = slot break end end
  end
  if reserve and destination and (not hotbar or active(snap)) then
    local opened = not inventory.inventoryVisible()
    if not inventory.openInventory() then nextRun = snap.now + 0.5 return end
    job = { character = snap.character, tool = reserve, from = from, to = destination, opened = opened,
      stage = "inventory", ready = snap.now + 0.18, deadline = snap.now + 1.5 }
    return
  end
  if active(snap) or not hotbar then nextRun = snap.now + 0.25 return end
  if snap.character:GetAttribute("VoxelGrounded") == false or math.abs(snap.root.AssemblyLinearVelocity.Y) > 5 then return end
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  params.FilterDescendantsInstances = { snap.character, snap.camera }
  if not workspace:Raycast(snap.eye, Vector3.new(0, -10, 0), params) then nextRun = snap.now + 0.25 return end
  if not native.equip(snap, hotbar) then nextRun = snap.now + 0.35 return end
  job = { character = snap.character, tool = hotbar, stage = "use", ready = snap.now + 0.12, deadline = snap.now + 1.3 }
end
Strength.__contract = {
  provides = { "setup", "reset", "step", "busy" },
  requires = { Native = "mcpnative", Inventory = "autototem", Utils = "utils" },
  requiresMethods = { Native = { "snapshot", "findSword", "equip", "blocked", "useItem" },
    Inventory = { "inventorySlots", "inventoryVisible", "openInventory", "closeInventory", "swapSpeedForStrength" },
    Utils = { "isActive", "getConfigValue" } },
}
return Strength
