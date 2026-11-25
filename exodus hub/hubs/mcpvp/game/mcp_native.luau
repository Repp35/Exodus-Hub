-- [[ mcpnative ]]
--!optimize 2
local Native = {}
local player, world, storage, weapons, geometry, config, controller, utils, rules, anchor
local functions, nextScan, dispatching = {}, 0, false
local lastPearlUse = -math.huge
local function load(name)
  local source = storage:FindFirstChild(name)
  if not source then
    return nil
  end
  local ok, result = pcall(require, source)
  return ok and type(result) == "table" and result or nil
end
local function owned(tool)
  return typeof(tool) == "Instance"
    and tool:IsA("Tool")
    and tool.Parent ~= nil
    and (tool.Parent == player.Character or tool.Parent == player:FindFirstChild("Backpack"))
end
local function discover()
  if functions.attack and functions.use and functions.select then
    return
  end
  if os.clock() < nextScan then
    return
  end
  nextScan = os.clock() + 5
  local env = type(getgenv) == "function" and getgenv() or _G
  if type(env.getgc) ~= "function" then
    return
  end
  local ok, objects = pcall(env.getgc, false)
  if not ok or type(objects) ~= "table" then
    return
  end
  local scripts = player:FindFirstChild("PlayerScripts")
  local wanted = { VoxelCombatClient = { performAttack = "attack" }, ItemClient = { use = "use" }, VoxelPackHUD = { selectSlot = "select" } }
  for _, fn in pairs(objects) do
    if type(fn) ~= "function" then
      continue
    end
    local gotEnv, fnEnv = pcall(getfenv, fn)
    local scriptObject = gotEnv and fnEnv and fnEnv.script
    if typeof(scriptObject) ~= "Instance" or not scripts or scriptObject.Parent ~= scripts then
      continue
    end
    local names = wanted[scriptObject.Name]
    if not names then
      continue
    end
    local gotName, name = pcall(debug.info, fn, "n")
    if gotName and names[name] then
      functions[names[name]] = fn
    end
  end
end
function Native.setup(deps)
  utils = deps.Utils
  player, world = utils.getLocalPlayer(), utils.getWorkspace()
  storage = game:GetService("ReplicatedStorage")
  weapons, geometry, config, controller = load("VoxelWeapons"), load("VoxelMeleeGeometry"), load("GameConfig"), load("ControllerInput")
  rules, anchor = load("SpawnBowRules"), load("RespawnAnchorTarget")
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
  if not root or not human or human.Health <= 0 or not camera or player:GetAttribute("InArena") == false or player:GetAttribute("ArenaProtected") == true then
    return nil
  end
  if
    char:GetAttribute("ArenaProtected") == true
    or char:GetAttribute("DuelCombatActive") == false
    or player:GetAttribute("DuelCombatActive") == false
    or rules and not rules.CanShoot(char)
  then
    return nil
  end
  local sneaking = char:GetAttribute("Sneaking") == true
  local eye = geometry and geometry.Eye(root.Position, sneaking) or root.Position + Vector3.new(0, sneaking and 0.064 or 1.184, 0)
  return {
    player = player,
    character = char,
    root = root,
    humanoid = human,
    camera = camera,
    eye = eye,
    tool = char:FindFirstChildOfClass("Tool"),
    now = os.clock(),
  }
end
function Native.stats(tool)
  if weapons and type(weapons.Stats) == "function" then
    return weapons.Stats(tool)
  end
  return { type = tool and tool:GetAttribute("WeaponType"), speed = 1.6, reach = 9.6 }
end
local function find(snap, predicate)
  for _, parent in pairs({ snap.character, player:FindFirstChild("Backpack") }) do
    if not parent then
      continue
    end
    for _, tool in ipairs(parent:GetChildren()) do
      if tool:IsA("Tool") and predicate(tool) then
        return tool
      end
    end
  end
  return nil
end
function Native.isWeapon(tool)
  if not owned(tool) then
    return false
  end
  local stats = Native.stats(tool)
  if not stats.type then
    return false
  end
  return stats.type ~= "mace" or (tonumber(tool:GetAttribute("Breach")) or 0) > 0
end
function Native.findWeapon(snap)
  -- Respect the weapon the player chose; never replace a held axe/mace with a sword.
  if Native.isWeapon(snap.tool) then
    return snap.tool
  end
  local best, bestScore
  for _, parent in pairs({ snap.character, player:FindFirstChild("Backpack") }) do
    if not parent then
      continue
    end
    for _, tool in ipairs(parent:GetChildren()) do
      if not tool:IsA("Tool") or not Native.isWeapon(tool) then
        continue
      end
      local stats = Native.stats(tool)
      local score = (stats.damage or 0) * (stats.speed or 0)
      if not best or score > bestScore or score == bestScore and tool.Name < best.Name then
        best, bestScore = tool, score
      end
    end
  end
  return best
end
function Native.findSword(snap) return Native.findWeapon(snap) end
function Native.strengthDuration()
  local item = config and config.Items and config.Items.StrengthPotion
  return item and tonumber(item.seconds) or 90
end
function Native.findPearl(snap)
  return find(snap, function(tool) return tool:GetAttribute("ClassItem") == "Pearl" and (tonumber(tool:GetAttribute("Count")) or 0) > 0 end)
end
function Native.visible(snap, point, target)
  local params = RaycastParams.new()
  params.RespectCanCollide = true
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = { snap.character, snap.camera }
  local hit = world:Raycast(snap.eye, point - snap.eye, params)
  return not hit or (target ~= nil and hit.Instance:IsDescendantOf(target))
end
function Native.hitDirection(snap, target, tool)
  if not target or not target.root.Parent then return nil end
  tool = tool or Native.findWeapon(snap)
  if not Native.isWeapon(tool) then return nil end
  local root, eye = target.root.Position, snap.eye
  local sneak = target.character:GetAttribute("Sneaking") == true and 0.96 or 0
  -- VoxelMeleeGeometry.Hit uses separate body/head boxes, not the camera crosshair.
  for _, bounds in ipairs({ { -4.32, 0.7 - sneak }, { 0.7 - sneak, 2.62 - sneak } }) do
    local point = root + Vector3.new(math.clamp(eye.X - root.X, -1.23, 1.23),
      math.clamp(eye.Y - root.Y, bounds[1] + 0.05, bounds[2] - 0.05), math.clamp(eye.Z - root.Z, -1.23, 1.23))
    local delta = point - eye
    if delta.Magnitude > 0.001 and Native.canHit(snap, target, tool, delta.Unit) then return delta.Unit end
  end
  return nil
end
function Native.canHit(snap, target, tool, direction)
  if rules and not rules.CanMelee(snap.character, target.character) then
    return false
  end
  tool = tool or Native.findWeapon(snap)
  if not Native.isWeapon(tool) then
    return false
  end
  local delta = target.root.Position - snap.eye
  if delta.Magnitude < 0.01 then
    return false
  end
  direction = direction or Native.hitDirection(snap, target, tool)
  if not direction then return false end
  local reach = Native.stats(tool).reach
  local distance
  if geometry and type(geometry.Hit) == "function" then
    distance = geometry.Hit(snap.eye, direction, target.root.Position, target.character:GetAttribute("Sneaking"), reach)
    if distance == nil then
      return false
    end
  else
    local along = delta:Dot(direction)
    if along <= 0 or along > reach or (delta - direction * along).Magnitude > 1.2 then
      return false
    end
    distance = along
  end
  return Native.visible(snap, snap.eye + direction * distance, target.character)
end
function Native.incomingHit(snap, opponent)
  local tool = opponent.character:FindFirstChildOfClass("Tool")
  local stats = Native.stats(tool)
  if not stats.type then
    return false
  end
  local sneak = opponent.character:GetAttribute("Sneaking") == true
  local eye = geometry and geometry.Eye(opponent.root.Position, sneak) or opponent.root.Position + Vector3.new(0, sneak and 0.064 or 1.184, 0)
  local aim = opponent.player:GetAttribute("FrontCameraAimDirection")
  local direction = typeof(aim) == "Vector3" and aim.Magnitude > 0.001 and aim.Unit or opponent.root.CFrame.LookVector
  if geometry and type(geometry.Hit) == "function" then
    local distance = geometry.Hit(eye, direction, snap.root.Position, snap.character:GetAttribute("Sneaking"), stats.reach)
    if distance == nil then
      return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    params.FilterDescendantsInstances = { opponent.character }
    local hit = world:Raycast(eye, direction * distance, params)
    return not hit or hit.Instance:IsDescendantOf(snap.character)
  end
  local delta = snap.root.Position - eye
  return delta.Magnitude <= stats.reach and delta.Magnitude > 0.01 and direction:Dot(delta.Unit) >= 0.95 and Native.visible(snap, eye, opponent.character)
end
function Native.blocked(snap)
  return (controller and controller.IsBlocked())
    or snap.character:GetAttribute("EatingApple") == true
    or snap.character:GetAttribute("DrinkingPotion") == true
    or snap.character:GetAttribute("BowDrawStarted")
    or player:GetAttribute("OffhandUsing") == true
end
local function invoke(action, direction)
  discover()
  local previous = player:GetAttribute("FrontCameraAimDirection")
  local previousCF = player:GetAttribute("FrontCameraAimCFrame")
  local snap = Native.snapshot()
  if not snap then
    return false
  end
  local aimCF = CFrame.lookAt(snap.eye, snap.eye + direction)
  dispatching = true
  player:SetAttribute("FrontCameraAimDirection", direction)
  player:SetAttribute("FrontCameraAimCFrame", aimCF)
  local ok, result = pcall(function()
    local fn = functions[action == "Attack" and "attack" or "use"]
    if fn then
      fn(direction)
      return true
    end
    if controller and type(controller.BeginTouch) == "function" and type(controller.EndTouch) == "function" then
      if not controller.BeginTouch(action) then
        return false
      end
      controller.EndTouch(action)
      return true
    end
    return false
  end)
  if player:GetAttribute("FrontCameraAimDirection") == direction then
    player:SetAttribute("FrontCameraAimDirection", previous)
  end
  if player:GetAttribute("FrontCameraAimCFrame") == aimCF then
    player:SetAttribute("FrontCameraAimCFrame", previousCF)
  end
  dispatching = false
  if not ok then
    utils.recordError("mcpvp.native." .. action, tostring(result))
  end
  return ok and result == true
end
function Native.attack(snap, target)
  if Native.blocked(snap) or not Native.isWeapon(snap.tool) then return false end
  local direction = Native.hitDirection(snap, target, snap.tool)
  if not direction then return false end
  local before = snap.character:GetAttribute("LocalAttackSwing")
  local dispatched = invoke("Attack", direction)
  return dispatched and snap.character:GetAttribute("LocalAttackSwing") ~= before
end
function Native.pearlCooldown() return config and config.Items and config.Items.Pearl and config.Items.Pearl.cooldown or 1 end
function Native.pearlReady()
  return (tonumber(player:GetAttribute("ItemCooldown_Pearl")) or 0) <= world:GetServerTimeNow()
    and os.clock() - lastPearlUse >= math.max(0.36, Native.pearlCooldown())
end
function Native.usePearl(snap, tool, direction)
  if anchor and anchor.Claims() then return false end
  if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then return false end
  if Native.blocked(snap) or not owned(tool) or tool.Parent ~= snap.character or not Native.pearlReady() then return false end
  if snap.now - lastPearlUse < math.max(0.36, Native.pearlCooldown()) then return false end
  local remotes = storage:FindFirstChild("Remotes")
  local remote = remotes and remotes:FindFirstChild("ItemAction")
  if not remote or not remote:IsA("RemoteEvent") then return false end
  -- ItemClient.use's exact request, without touching camera or FrontCameraAim attributes.
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
  local ignored = { snap.character }
  for _, name in ipairs({ "LocalItemVisuals", "PredictedBlocks", "LocalBowVisuals" }) do
    local folder = world:FindFirstChild(name)
    if folder then ignored[#ignored + 1] = folder end
  end
  params.FilterDescendantsInstances = ignored
  local hit = world:Raycast(snap.eye, direction.Unit * 30, params)
  lastPearlUse = snap.now
  remote:FireServer("Use", "Pearl", direction.Unit, hit and hit.Position or nil)
  return true
end
function Native.equip(snap, tool)
  if not owned(tool) then
    return false
  end
  if tool.Parent == snap.character then
    return true
  end
  discover()
  local select = functions.select
  if select then
    local env = type(getgenv) == "function" and getgenv() or _G
    local getter = env.getupvalues or (env.debug and env.debug.getupvalues)
    if type(getter) == "function" then
      local ok, values = pcall(getter, select)
      if ok and type(values) == "table" then
        for _, value in pairs(values) do
          if type(value) ~= "table" then
            continue
          end
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
function Native.prepareCritical()
  local combat = storage:FindFirstChild("VoxelCombat")
  local sprint = combat and combat:FindFirstChild("Sprint")
  if sprint and sprint:IsA("RemoteEvent") then
    sprint:FireServer(false)
  end
end
function Native.useItem(snap, tool, direction)
  if anchor and anchor.Claims() then
    return false
  end
  if Native.blocked(snap) or not owned(tool) or tool.Parent ~= snap.character then
    return false
  end
  local class = tool:GetAttribute("ClassItem")
  if type(class) ~= "string" then
    return false
  end
  if (tonumber(player:GetAttribute("ItemCooldown_" .. class)) or 0) > world:GetServerTimeNow() then
    return false
  end
  return invoke("Use", direction)
end
local recentMaces = setmetatable({}, { __mode = "k" })
function Native.aerialMace(snap, target)
  if not target or not target.character.Parent or not target.root.Parent then
    return false
  end
  local tool = target.character:FindFirstChildOfClass("Tool")
  local stats = Native.stats(tool)
  local now = os.clock()
  if stats.type == "mace" then
    recentMaces[target.character] = now + 1
  end
  if (recentMaces[target.character] or 0) < now then
    return false
  end
  local grounded = target.character:GetAttribute("VoxelGrounded")
  if grounded == true then
    return false
  end
  if grounded == nil and target.humanoid.FloorMaterial ~= Enum.Material.Air then
    return false
  end
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  params.FilterDescendantsInstances = { snap.character, target.character, snap.camera }
  -- A normal jump rises about four studs. Require much more clearance for aerial mace mode.
  local support = world:Raycast(target.root.Position, Vector3.new(0, -12, 0), params)
  local above = target.root.Position.Y - snap.root.Position.Y
  local fall = tonumber(target.character:GetAttribute("LocalFallDistance")) or 0
  return not support or above > 8 or fall > 8
end
Native.__contract = {
  provides = {
    "setup",
    "snapshot",
    "stats",
    "visible",
    "canHit", "hitDirection",
    "attack",
    "findSword",
    "findWeapon",
    "isWeapon",
    "strengthDuration",
    "findPearl",
    "pearlCooldown",
    "pearlReady",
    "usePearl",
    "equip",
    "blocked",
    "isDispatching",
    "incomingHit",
    "prepareCritical",
    "useItem",
    "aerialMace",
  },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getLocalPlayer", "getWorkspace", "recordError" } },
}
return Native
