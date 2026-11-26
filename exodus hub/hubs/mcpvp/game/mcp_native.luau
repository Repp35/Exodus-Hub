-- [[ mcpnative ]]
--!optimize 2
local Native = {}
local player, world, storage, weapons, geometry, config, controller, utils
local bridge, charge, dispatching, criticalAt = nil, nil, false, 0
local observedCharacter, observedTool
local equippedAt, attackAt, attemptAt = -math.huge, -math.huge, -math.huge
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
function Native.setup(deps)
  utils, bridge = deps.Utils, deps.Bridge
  player, world = utils.getLocalPlayer(), utils.getWorkspace()
  storage = game:GetService("ReplicatedStorage")
  weapons, geometry, config, controller = load("VoxelWeapons"), load("VoxelMeleeGeometry"), load("GameConfig"), load("ControllerInput")
  charge = load("HeldItemFov")
  dispatching, criticalAt = false, 0
  observedCharacter, observedTool = nil, nil
  equippedAt, attackAt, attemptAt = -math.huge, -math.huge, -math.huge
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
  local now, tool = os.clock(), char:FindFirstChildOfClass("Tool")
  if observedCharacter ~= char then
    observedCharacter, observedTool = char, tool
    equippedAt, attackAt, attemptAt = -math.huge, -math.huge, -math.huge
  elseif observedTool ~= tool then
    observedTool, equippedAt = tool, now
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
    tool = tool,
    now = now,
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
function Native.findSword(snap)
  if owned(snap.tool) and Native.stats(snap.tool).type == "sword" then
    return snap.tool
  end
  return find(snap, function(tool) return Native.stats(tool).type == "sword" end)
end
function Native.findPearl(snap)
  return find(snap, function(tool) return tool:GetAttribute("ClassItem") == "Pearl" and (tonumber(tool:GetAttribute("Count")) or 0) > 0 end)
end
function Native.visible(snap, point, target, origin)
  origin = origin or snap.eye
  local params = RaycastParams.new()
  params.RespectCanCollide = true
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = { snap.character, snap.camera }
  local hit = world:Raycast(origin, point - origin, params)
  return not hit or (target ~= nil and hit.Instance:IsDescendantOf(target))
end
function Native.aimDirection(snap)
  local aim = snap.player:GetAttribute("FrontCameraAimDirection")
  return typeof(aim) == "Vector3" and aim.Magnitude > 0.001 and aim.Unit or snap.camera.CFrame.LookVector
end
function Native.hitDistance(snap, target, tool, direction)
  local delta = target.root.Position - snap.eye
  if delta.Magnitude < 0.01 then
    return nil
  end
  direction = direction or delta.Unit
  local reach = Native.stats(tool).reach
  if type(reach) ~= "number" or reach <= 0 then
    return nil
  end
  local distance
  if geometry and type(geometry.Hit) == "function" then
    distance = geometry.Hit(snap.eye, direction, target.root.Position, target.character:GetAttribute("Sneaking"), reach)
    if distance == nil then
      return nil
    end
  else
    distance = delta.Magnitude
    if distance > reach or direction:Dot(delta.Unit) < 0.995 then
      return nil
    end
  end
  if not Native.visible(snap, snap.eye + direction * distance, target.character) then
    return nil
  end
  return distance
end
function Native.canHit(snap, target, tool, direction) return Native.hitDistance(snap, target, tool or snap.tool, direction) ~= nil end
function Native.blocked(snap)
  return (controller and type(controller.IsBlocked) == "function" and controller.IsBlocked())
    or player:GetAttribute("MenuOpen") == true
    or snap.character:GetAttribute("EatingApple") == true
    or snap.character:GetAttribute("DrinkingPotion") == true
    or snap.character:GetAttribute("BowDrawStarted")
    or player:GetAttribute("OffhandUsing") == true
end
local function invoke(action, direction)
  local previous = player:GetAttribute("FrontCameraAimDirection")
  local previousCF = player:GetAttribute("FrontCameraAimCFrame")
  local snap = Native.snapshot()
  if not snap or dispatching or typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then
    return false
  end
  direction = direction.Unit
  local aimCF = CFrame.lookAt(snap.eye, snap.eye + direction)
  dispatching = true
  player:SetAttribute("FrontCameraAimDirection", direction)
  player:SetAttribute("FrontCameraAimCFrame", aimCF)
  local ok, result = pcall(function()
    local fn = bridge.get(action == "Attack" and "attack" or "use")
    if fn then
      return fn(direction) ~= false
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
function Native.readyAt(snap, tool)
  local speed = Native.stats(tool).speed
  if type(speed) ~= "number" or speed <= 0 then
    return math.huge
  end
  -- VoxelWeapons.Strength reaches full damage at (elapsed + 0.025) * speed == 1.
  local period = math.max(1 / 15, 1 / speed - 0.025)
  local swing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or -math.huge
  local ready = math.max(attackAt + period, attemptAt + 1 / 15, equippedAt + period, swing + period)
  -- The native HUD tracks charge after manual attacks and equipment changes too.
  if tool == snap.tool and charge and type(charge.Charge) == "function" then
    local ok, value = pcall(charge.Charge)
    if ok and type(value) == "number" and value == value and value >= 0 and value <= 1 then
      return math.max(ready, snap.now + math.max(0, (1 - value) / speed - 0.025))
    end
  end
  return math.max(ready, swing + period)
end
local function intercepted(snap, chosen, direction, distance)
  if not geometry or type(geometry.Hit) ~= "function" then
    return false
  end
  local function closer(character)
    if not character or character == snap.character or character == chosen.character then
      return false
    end
    local human = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root or not human or human.Health <= 0 then
      return false
    end
    local hit = geometry.Hit(snap.eye, direction, root.Position, character:GetAttribute("Sneaking"), distance)
    return hit ~= nil and hit <= distance
  end
  for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
    if closer(other.Character) then
      return true
    end
  end
  local bots = world:FindFirstChild("ArenaPvPBots")
  if bots then
    for _, character in ipairs(bots:GetChildren()) do
      if closer(character) then
        return true
      end
    end
  end
  local crystals = world:FindFirstChild("EndCrystals")
  if crystals and type(geometry.Box) == "function" then
    for _, crystal in ipairs(crystals:GetChildren()) do
      local feet = crystal:GetAttribute("CrystalFeet")
      if typeof(feet) ~= "Vector3" then
        continue
      end
      -- performAttack prioritizes crystalPick before the selected melee target.
      local hit = geometry.Box(snap.eye, direction, feet - Vector3.new(3.2, 0, 3.2), feet + Vector3.new(3.2, 6.4, 3.2), distance)
      if hit and hit < distance then
        return true
      end
    end
  end
  return false
end
function Native.attackDirection(snap, chosen, tool)
  if not chosen.character.Parent or not chosen.root.Parent or chosen.humanoid.Health <= 0 then
    return nil
  end
  local function valid(direction)
    local distance = Native.hitDistance(snap, chosen, tool, direction)
    return distance and not intercepted(snap, chosen, direction, distance)
  end
  local aim = Native.aimDirection(snap)
  if valid(aim) then
    return aim
  end
  local root = chosen.root.Position
  local crouch = chosen.character:GetAttribute("Sneaking") == true and 0.96 or 0
  local relative = snap.eye - root
  -- Use current body/head boxes from VoxelMeleeGeometry, with points inside their margins.
  local nearest = Vector3.new(math.clamp(relative.X, -1.2, 1.2), math.clamp(relative.Y, -4.2, 0.6 - crouch), math.clamp(relative.Z, -1.2, 1.2))
  local head = Vector3.new(math.clamp(relative.X, -1.2, 1.2), math.clamp(relative.Y, 0.8 - crouch, 2.5 - crouch), math.clamp(relative.Z, -1.2, 1.2))
  for _, offset in ipairs({ nearest, head, Vector3.new(0, 0.3 - crouch, 0), Vector3.new(0, 1.5 - crouch, 0) }) do
    local delta = root + offset - snap.eye
    if delta.Magnitude > 0.001 and valid(delta.Unit) then
      return delta.Unit
    end
  end
  return nil
end
function Native.attack(snap, target, direction)
  if Native.blocked(snap) or not snap.tool or Native.stats(snap.tool).type ~= "sword" or snap.now + 1e-6 < Native.readyAt(snap, snap.tool) then
    return false
  end
  direction = direction or Native.attackDirection(snap, target, snap.tool)
  if not direction then
    return false
  end
  attemptAt = snap.now
  local sent = invoke("Attack", direction)
  if sent then
    attackAt = os.clock()
  end
  return sent
end
function Native.pearlCooldown() return config and config.Items and config.Items.Pearl and config.Items.Pearl.cooldown or 1 end
function Native.pearlReady() return (tonumber(player:GetAttribute("ItemCooldown_Pearl")) or 0) <= world:GetServerTimeNow() end
function Native.usePearl(snap, tool, direction)
  if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then
    return false
  end
  if Native.blocked(snap) or not owned(tool) or tool.Parent ~= snap.character or not Native.pearlReady() then
    return false
  end
  return invoke("Use", direction)
end
function Native.equip(snap, tool)
  if not owned(tool) then
    return false
  end
  if tool.Parent == snap.character then
    return true
  end
  local select = bridge.get("select")
  if select then
    local values = bridge.upvalues(select)
    if values then
      for _, value in pairs(values) do
        if type(value) ~= "table" then
          continue
        end
        for slot = 1, 9 do
          if rawget(value, slot) == tool then
            local ok, result = pcall(select, slot)
            return ok and result ~= false
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
  if os.clock() < criticalAt then
    return
  end
  criticalAt = os.clock() + 0.2
  local combat = storage:FindFirstChild("VoxelCombat")
  local sprint = combat and combat:FindFirstChild("Sprint")
  if sprint and sprint:IsA("RemoteEvent") then
    sprint:FireServer(false)
  end
end
function Native.useItem(snap, tool, direction)
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
    "canHit",
    "aimDirection",
    "hitDistance",
    "attack",
    "readyAt",
    "attackDirection",
    "findSword",
    "findPearl",
    "pearlCooldown",
    "pearlReady",
    "usePearl",
    "equip",
    "blocked",
    "isDispatching",
    "prepareCritical",
    "useItem",
    "aerialMace",
  },
  requires = { Utils = "utils", Bridge = "mcpbridge" },
  requiresMethods = { Bridge = { "get", "upvalues" }, Utils = { "getLocalPlayer", "getWorkspace", "recordError" } },
}
return Native
