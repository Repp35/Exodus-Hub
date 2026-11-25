-- [[ mcpnative ]]
--!optimize 2
local Native = {}
local player, world, storage, weapons, geometry, config, controller, utils
local functions, nextScan, dispatching = {}, 0, false
local function load(name)
  local source = storage:FindFirstChild(name)
  if not source then return nil end
  local ok, result = pcall(require, source)
  return ok and type(result) == "table" and result or nil
end
local function owned(tool)
  return typeof(tool) == "Instance" and tool:IsA("Tool") and tool.Parent ~= nil
    and (tool.Parent == player.Character or tool.Parent == player:FindFirstChild("Backpack"))
end
local function discover()
  if os.clock() < nextScan then return end
  nextScan = os.clock() + 5
  local env = type(getgenv) == "function" and getgenv() or _G
  if type(env.getgc) ~= "function" then return end
  local ok, objects = pcall(env.getgc, false)
  if not ok or type(objects) ~= "table" then return end
  local scripts = player:FindFirstChild("PlayerScripts")
  local wanted = { VoxelCombatClient = { performAttack = "attack" }, ItemClient = { use = "use" }, VoxelPackHUD = { selectSlot = "select" } }
  for _, fn in pairs(objects) do
    if type(fn) ~= "function" then continue end
    local gotEnv, fnEnv = pcall(getfenv, fn)
    local scriptObject = gotEnv and fnEnv and fnEnv.script
    if typeof(scriptObject) ~= "Instance" or not scripts or scriptObject.Parent ~= scripts then continue end
    local names = wanted[scriptObject.Name]
    if not names then continue end
    local gotName, name = pcall(debug.info, fn, "n")
    if gotName and names[name] then functions[names[name]] = fn end
  end
end
function Native.setup(deps)
  utils = deps.Utils
  player, world = utils.getLocalPlayer(), utils.getWorkspace()
  storage = game:GetService("ReplicatedStorage")
  weapons, geometry, config, controller = load("VoxelWeapons"), load("VoxelMeleeGeometry"), load("GameConfig"), load("ControllerInput")
  functions, nextScan, dispatching = {}, 0, false
  discover()
  return true
end
function Native.isDispatching() return dispatching end
function Native.snapshot()
  local char = player.Character
  local root = char and char:FindFirstChild("HumanoidRootPart")
  local human = char and char:FindFirstChildOfClass("Humanoid")
  local camera = world.CurrentCamera
  if not root or not human or human.Health <= 0 or not camera or player:GetAttribute("InArena") == false
    or player:GetAttribute("ArenaProtected") == true then return nil end
  local sneaking = char:GetAttribute("Sneaking") == true
  local eye = geometry and geometry.Eye(root.Position, sneaking) or root.Position + Vector3.new(0, sneaking and 0.064 or 1.184, 0)
  return { player = player, character = char, root = root, humanoid = human, camera = camera, eye = eye, tool = char:FindFirstChildOfClass("Tool"), now = os.clock() }
end
function Native.stats(tool)
  if weapons and type(weapons.Stats) == "function" then return weapons.Stats(tool) end
  return { type = tool and tool:GetAttribute("WeaponType"), speed = 1.6, reach = 9.6 }
end
local function find(snap, predicate)
  for _, parent in pairs({ snap.character, player:FindFirstChild("Backpack") }) do
    for _, tool in ipairs(parent:GetChildren()) do
      if tool:IsA("Tool") and predicate(tool) then return tool end
    end
  end
  return nil
end
function Native.findSword(snap)
  if owned(snap.tool) and Native.stats(snap.tool).type == "sword" then return snap.tool end
  return find(snap, function(tool) return Native.stats(tool).type == "sword" end)
end
function Native.findPearl(snap)
  return find(snap, function(tool)
    return tool:GetAttribute("ClassItem") == "Pearl" and (tonumber(tool:GetAttribute("Count")) or 0) > 0
  end)
end
function Native.visible(snap, point, target)
  local params = RaycastParams.new()
  params.RespectCanCollide = true
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = { snap.character, snap.camera }
  local hit = world:Raycast(snap.eye, point - snap.eye, params)
  return not hit or (target ~= nil and hit.Instance:IsDescendantOf(target))
end
function Native.canHit(snap, target, tool)
  tool = tool or Native.findSword(snap)
  if not tool or Native.stats(tool).type ~= "sword" then return false end
  local delta = target.root.Position - snap.eye
  if delta.Magnitude < 0.01 then return false end
  local direction = delta.Unit
  local reach = Native.stats(tool).reach
  local distance
  if geometry and type(geometry.Hit) == "function" then
    distance = geometry.Hit(snap.eye, direction, target.root.Position, target.character:GetAttribute("Sneaking"), reach)
    if distance == nil then return false end
  else
    distance = delta.Magnitude
    if distance > reach then return false end
  end
  return Native.visible(snap, snap.eye + direction * distance, target.character)
end
function Native.incomingHit(snap, opponent)
  local tool = opponent.character:FindFirstChildOfClass("Tool")
  local stats = Native.stats(tool)
  if stats.type ~= "sword" and stats.type ~= "axe" and stats.type ~= "mace" then return false end
  local sneak = opponent.character:GetAttribute("Sneaking") == true
  local eye = geometry and geometry.Eye(opponent.root.Position, sneak)
    or opponent.root.Position + Vector3.new(0, sneak and 0.064 or 1.184, 0)
  local aim = opponent.player:GetAttribute("FrontCameraAimDirection")
  local direction = typeof(aim) == "Vector3" and aim.Magnitude > 0.001 and aim.Unit or opponent.root.CFrame.LookVector
  if geometry and type(geometry.Hit) == "function" then
    local distance = geometry.Hit(eye, direction, snap.root.Position, snap.character:GetAttribute("Sneaking"), stats.reach)
    if distance == nil then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    params.FilterDescendantsInstances = { opponent.character }
    local hit = world:Raycast(eye, direction * distance, params)
    return not hit or hit.Instance:IsDescendantOf(snap.character)
  end
  local delta = snap.root.Position - eye
  return delta.Magnitude <= stats.reach and delta.Magnitude > 0.01
    and direction:Dot(delta.Unit) >= 0.95
    and Native.visible(snap, eye, opponent.character)
end
function Native.blocked(snap)
  return (controller and controller.IsBlocked()) or snap.character:GetAttribute("EatingApple") == true
    or snap.character:GetAttribute("DrinkingPotion") == true or snap.character:GetAttribute("BowDrawStarted")
    or player:GetAttribute("OffhandUsing") == true
end
local function invoke(action, direction)
  discover()
  local previous = player:GetAttribute("FrontCameraAimDirection")
  dispatching = true
  player:SetAttribute("FrontCameraAimDirection", direction)
  local ok, result = pcall(function()
    local fn = functions[action == "Attack" and "attack" or "use"]
    if fn then fn(direction) return true end
    if controller and type(controller.BeginTouch) == "function" and type(controller.EndTouch) == "function" then
      if not controller.BeginTouch(action) then return false end
      controller.EndTouch(action)
      return true
    end
    return false
  end)
  if player:GetAttribute("FrontCameraAimDirection") == direction then player:SetAttribute("FrontCameraAimDirection", previous) end
  dispatching = false
  if not ok then utils.recordError("mcpvp.native." .. action, tostring(result)) end
  return ok and result == true
end
function Native.attack(snap, target)
  if Native.blocked(snap) or not snap.tool or Native.stats(snap.tool).type ~= "sword" or not Native.canHit(snap, target, snap.tool) then return false end
  return invoke("Attack", (target.root.Position - snap.eye).Unit)
end
function Native.pearlCooldown()
  return config and config.Items and config.Items.Pearl and config.Items.Pearl.cooldown or 1
end
function Native.pearlReady()
  return (tonumber(player:GetAttribute("ItemCooldown_Pearl")) or 0) <= world:GetServerTimeNow()
end
function Native.usePearl(snap, tool, direction)
  if Native.blocked(snap) or not owned(tool) or tool.Parent ~= snap.character or not Native.pearlReady() then return false end
  return invoke("Use", direction)
end
function Native.equip(snap, tool)
  if not owned(tool) then return false end
  if tool.Parent == snap.character then return true end
  discover()
  local select = functions.select
  if select then
    local env = type(getgenv) == "function" and getgenv() or _G
    local getter = env.getupvalues or (env.debug and env.debug.getupvalues)
    if type(getter) == "function" then
      local ok, values = pcall(getter, select)
      if ok and type(values) == "table" then
        for _, value in pairs(values) do
          if type(value) ~= "table" then continue end
          for slot = 1, 9 do
            if rawget(value, slot) == tool then
              local selected = pcall(select, slot)
              return selected
            end
          end
        end
      end
    end
  end
  -- Same equip operation as selectSlot; no repeated selection when already held.
  snap.humanoid:EquipTool(tool)
  return true
end
Native.__contract = {
  provides = { "setup", "snapshot", "stats", "visible", "canHit", "attack", "findSword", "findPearl", "pearlCooldown", "pearlReady", "usePearl", "equip", "blocked", "isDispatching", "incomingHit" },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getLocalPlayer", "getWorkspace", "recordError" } },
}
return Native
