-- [[ mcpnative ]]
--!optimize 2
local Native = {}
local player, world, storage, weapons, geometry, config, controller, utils, units
local shields
local bridge, charge, dispatching, criticalAt = nil, nil, false, 0
local gate, hookedAttack, originalAttack, hooker
local sprintOwner, resumeSprint
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
  utils, bridge, units = deps.Utils, deps.Bridge, deps.Units
  player, world = utils.getLocalPlayer(), utils.getWorkspace()
  storage = game:GetService("ReplicatedStorage")
  weapons, geometry, config, controller = load("VoxelWeapons"), load("VoxelMeleeGeometry"), load("GameConfig"), load("ControllerInput")
  charge, shields = load("HeldItemFov"), load("ShieldRules")
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
  local eye = geometry and geometry.Eye(root.Position, sneaking) or root.Position + units.offset(0, sneaking and 0.02 or 0.37, 0)
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
  local stats = weapons and type(weapons.Stats) == "function" and weapons.Stats(tool)
  if not stats then
    return { type = tool and tool:GetAttribute("WeaponType"), speed = 1.6, reachBlocks = 3 }
  end
  return {
    type = stats.type,
    speed = stats.speed,
    damage = stats.damage,
    reachBlocks = tonumber(stats.reachBlocks) or units.toBlocks(stats.reach or units.toWorld(3)),
  }
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
function Native.hitDistanceBlocks(snap, target, tool, direction)
  local delta = units.toBlocks(target.root.Position - snap.eye)
  if delta.Magnitude < 1 / 320 then
    return nil
  end
  direction = direction or delta.Unit
  local reachBlocks = Native.stats(tool).reachBlocks
  if type(reachBlocks) ~= "number" or reachBlocks <= 0 then
    return nil
  end
  local distanceBlocks
  if geometry and type(geometry.Hit) == "function" then
    local worldDistance = geometry.Hit(snap.eye, direction, target.root.Position, target.character:GetAttribute("Sneaking"), units.toWorld(reachBlocks))
    if worldDistance == nil then
      return nil
    end
    distanceBlocks = units.toBlocks(worldDistance)
  else
    distanceBlocks = delta.Magnitude
    if distanceBlocks > reachBlocks or direction:Dot(delta.Unit) < 0.995 then
      return nil
    end
  end
  if not Native.visible(snap, snap.eye + direction * units.toWorld(distanceBlocks), target.character) then
    return nil
  end
  return distanceBlocks
end
function Native.canHit(snap, target, tool, direction) return Native.hitDistanceBlocks(snap, target, tool or snap.tool, direction) ~= nil end
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
local function releaseAttackGate()
  if hookedAttack and originalAttack and hooker then
    local ok, reason = pcall(hooker, hookedAttack, originalAttack)
    if not ok then
      utils.recordError("mcpvp.critical.restore", tostring(reason))
    end
  end
  hookedAttack, originalAttack, hooker = nil, nil, nil
end
function Native.setAttackGate(callback)
  gate = callback
  if not callback then
    releaseAttackGate()
    return false
  end
  local fn = bridge.get("attack")
  if fn and fn == hookedAttack then
    return true
  end
  local env = type(getgenv) == "function" and getgenv() or _G
  if not fn or type(env.hookfunction) ~= "function" then
    return false
  end
  releaseAttackGate()
  local original
  local ok, result = pcall(env.hookfunction, fn, function(direction)
    if dispatching or not gate then
      return original(direction)
    end
    local snap = Native.snapshot()
    if not snap then
      return original(direction)
    end
    local success, allow = pcall(gate, snap, direction)
    if not success then
      utils.recordError("mcpvp.critical.gate", tostring(allow))
      return
    end
    if allow then
      return original(direction)
    end
    return nil
  end)
  if not ok or type(result) ~= "function" then
    return false
  end
  original = result
  hookedAttack, originalAttack, hooker = fn, original, env.hookfunction
  return true
end
function Native.attackGateReady() return hookedAttack ~= nil and gate ~= nil end
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
    local hit = geometry.Hit(snap.eye, direction, root.Position, character:GetAttribute("Sneaking"), units.toWorld(distance))
    return hit ~= nil and units.toBlocks(hit) <= distance
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
      local hit = geometry.Box(snap.eye, direction, feet - units.offset(1, 0, 1), feet + units.offset(1, 2, 1), units.toWorld(distance))
      if hit and units.toBlocks(hit) < distance then
        return true
      end
    end
  end
  return false
end
function Native.incomingHit(snap, opponent)
  local tool = opponent.character:FindFirstChildOfClass("Tool")
  local reach = Native.stats(tool).reachBlocks
  if type(reach) ~= "number" or reach <= 0 then
    return false
  end
  local sneaking = opponent.character:GetAttribute("Sneaking") == true
  local eye = geometry and geometry.Eye(opponent.root.Position, sneaking) or opponent.root.Position + units.offset(0, sneaking and 0.02 or 0.37, 0)
  local aim = opponent.player:GetAttribute("FrontCameraAimDirection")
  local direction = typeof(aim) == "Vector3" and aim.Magnitude > 0.001 and aim.Unit or opponent.root.CFrame.LookVector
  local distance
  if geometry and type(geometry.Hit) == "function" then
    distance = geometry.Hit(eye, direction, snap.root.Position, snap.character:GetAttribute("Sneaking"), units.toWorld(reach))
    if distance == nil then
      return false
    end
  else
    local delta = snap.root.Position - eye
    if units.toBlocks(delta).Magnitude > reach or delta.Magnitude < 0.001 or direction:Dot(delta.Unit) < 0.995 then
      return false
    end
    distance = delta.Magnitude
  end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide, params.IgnoreWater = Enum.RaycastFilterType.Exclude, true, true
  params.FilterDescendantsInstances = { opponent.character, snap.camera }
  local hit = world:Raycast(eye, direction * distance, params)
  return not hit or hit.Instance:IsDescendantOf(snap.character)
end
function Native.shieldRear(character, root)
  local now = world:GetServerTimeNow()
  local blocking
  if shields and type(shields.IsBlocking) == "function" then
    blocking = shields.IsBlocking(character, now)
  else
    local raised = tonumber(character:GetAttribute("ShieldRaisedAt"))
    blocking = raised ~= nil and now - raised >= 0.25 and (tonumber(character:GetAttribute("ShieldDisabledUntil")) or 0) <= now
  end
  if not blocking then
    return nil
  end
  local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
  return facing.Magnitude > 0.001 and -facing.Unit or nil
end
function Native.shieldBlocks(snap, chosen)
  if shields and type(shields.Blocks) == "function" then
    return shields.Blocks(chosen.character, snap.eye, world:GetServerTimeNow())
  end
  local rear = Native.shieldRear(chosen.character, chosen.root)
  if not rear then
    return false
  end
  local towardUs = (snap.eye - chosen.root.Position) * Vector3.new(1, 0, 1)
  return towardUs.Magnitude > 0.001 and towardUs.Unit:Dot(rear) < 0
end
function Native.aimPoint(character, root)
  local rear = Native.shieldRear(character, root)
  local height = character:GetAttribute("Sneaking") == true and 3 / 64 or 5 / 32
  return root.Position + units.offset(0, height, 0) + (rear and rear * units.toWorld(0.25) or Vector3.zero)
end
function Native.attackDirection(snap, chosen, tool)
  if not chosen.character.Parent or not chosen.root.Parent or chosen.humanoid.Health <= 0 then
    return nil
  end
  local function valid(direction)
    local distance = Native.hitDistanceBlocks(snap, chosen, tool, direction)
    return distance and not intercepted(snap, chosen, direction, distance)
  end
  local rear = Native.shieldRear(chosen.character, chosen.root)
  if rear then
    local delta = Native.aimPoint(chosen.character, chosen.root) - snap.eye
    if units.toBlocks(delta).Magnitude > 1 / 3200 and valid(delta.Unit) then
      return delta.Unit
    end
  end
  local aim = Native.aimDirection(snap)
  if valid(aim) then
    return aim
  end
  local root = chosen.root.Position
  local crouch = chosen.character:GetAttribute("Sneaking") == true and 0.3 or 0
  local relative = units.toBlocks(snap.eye - root)
  -- Use current body/head boxes from VoxelMeleeGeometry, with points inside their margins.
  local nearest = Vector3.new(math.clamp(relative.X, -3 / 8, 3 / 8), math.clamp(relative.Y, -21 / 16, 3 / 16 - crouch), math.clamp(relative.Z, -3 / 8, 3 / 8))
  local head =
    Vector3.new(math.clamp(relative.X, -3 / 8, 3 / 8), math.clamp(relative.Y, 1 / 4 - crouch, 25 / 32 - crouch), math.clamp(relative.Z, -3 / 8, 3 / 8))
  for _, offset in ipairs({ nearest, head, Vector3.new(0, 3 / 32 - crouch, 0), Vector3.new(0, 15 / 32 - crouch, 0) }) do
    local delta = units.toBlocks(root - snap.eye) + offset
    if delta.Magnitude > 1 / 3200 and valid(delta.Unit) then
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
function Native.replayAttack(snap, direction)
  if Native.blocked(snap) or snap.now + 1e-6 < Native.readyAt(snap, snap.tool) then
    return false
  end
  attemptAt = snap.now
  local sent = invoke("Attack", direction or Native.aimDirection(snap))
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
function Native.crystalJumpRisk(snap)
  local folder = world:FindFirstChild("EndCrystals")
  local crystals = game:GetService("CollectionService"):GetTagged("EndCrystal")
  if folder then
    for _, crystal in ipairs(folder:GetChildren()) do
      crystals[#crystals + 1] = crystal
    end
  end
  if #crystals == 0 then
    return false
  end
  local seen, params = {}, RaycastParams.new()
  params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
  local ignored = { snap.character, snap.camera }
  for _, crystal in ipairs(crystals) do
    ignored[#ignored + 1] = crystal
  end
  params.FilterDescendantsInstances = ignored
  local motion = units.toBlocks(snap.root.AssemblyLinearVelocity) * Vector3.new(1, 0, 1)
  -- Native movement in blocks: 8.4 blocks/s jump, 0.05 s ticks, then (vy - 1.6) * 0.98.
  local trajectory, height, vertical = {}, 0, 8.4
  for tick = 1, 20 do
    height += vertical * 0.05
    if height < 0 then
      break
    end
    trajectory[#trajectory + 1] = units.toBlocks(snap.root.Position) - Vector3.new(0, 1.25, 0) + motion * (tick * 0.05) + Vector3.new(0, height, 0)
    vertical = (vertical - 1.6) * 0.98
  end
  for _, crystal in ipairs(crystals) do
    if seen[crystal] or not crystal.Parent then
      continue
    end
    seen[crystal] = true
    local origin = crystal:GetAttribute("CrystalFeet")
    if typeof(origin) ~= "Vector3" then
      continue
    end
    origin = units.toBlocks(origin)
    for _, feet in ipairs(trajectory) do
      -- Narrow client estimate: feet at/above the crystal in its immediate one-block space,
      -- with full body exposure. The server's exact damage formula is not replicated.
      if feet.Y < origin.Y or (feet - origin).Magnitude > 1 then
        continue
      end
      local exposed = true
      for _, heightOffset in ipairs({ 3 / 64, 1, 31 / 16 }) do
        for _, side in ipairs({
          Vector3.zero,
          Vector3.new(-9 / 32, 0, -9 / 32),
          Vector3.new(-9 / 32, 0, 9 / 32),
          Vector3.new(9 / 32, 0, -9 / 32),
          Vector3.new(9 / 32, 0, 9 / 32),
        }) do
          local from = origin + Vector3.new(0, 1 / 64, 0)
          local destination = feet + side + Vector3.new(0, heightOffset, 0)
          if world:Raycast(units.toWorld(from), units.toWorld(destination - from), params) then
            exposed = false
            break
          end
        end
        if not exposed then
          break
        end
      end
      if exposed then
        return true
      end
    end
  end
  return false
end
function Native.requestJump(snap)
  if Native.blocked(snap) or snap.humanoid.Health <= 0 then
    return false
  end
  snap.humanoid.Jump = true
  -- The game's VoxelAirMovement listens to the native Jumping state as well as Jump.
  snap.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
  return true
end
function Native.prepareCritical(force)
  local character = player.Character
  if not character then
    return
  end
  if sprintOwner ~= character then
    sprintOwner, resumeSprint = character, false
  end
  if character:GetAttribute("Sprinting") == true or character:GetAttribute("SprintRequested") == true then
    resumeSprint = true
  end
  if not force and os.clock() < criticalAt then
    return
  end
  criticalAt = os.clock() + 0.1
  local combat = storage:FindFirstChild("VoxelCombat")
  local sprint = combat and combat:FindFirstChild("Sprint")
  if sprint and sprint:IsA("RemoteEvent") then
    sprint:FireServer(false)
  end
end
function Native.finishCritical()
  local character, shouldResume = sprintOwner, resumeSprint
  sprintOwner, resumeSprint = nil, false
  if not character or character ~= player.Character or not shouldResume or player:GetAttribute("SprintToggleEnabled") ~= true then
    return
  end
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if not humanoid or humanoid.Health <= 0 then
    return
  end
  local snap = Native.snapshot()
  if not snap or Native.blocked(snap) then
    return
  end
  local forward
  if controller and type(controller.ForwardHeld) == "function" then
    forward = controller.ForwardHeld()
  else
    forward = humanoid.MoveDirection.Magnitude > 0.05
  end
  if not forward then
    return
  end
  local combat = storage:FindFirstChild("VoxelCombat")
  local sprint = combat and combat:FindFirstChild("Sprint")
  if sprint and sprint:IsA("RemoteEvent") then
    sprint:FireServer(true)
  end
end
function Native.criticalReady(snap)
  if Native.blocked(snap) or snap.humanoid.Sit or snap.humanoid.PlatformStand then
    return false
  end
  local ground = snap.character:GetAttribute("VoxelGrounded")
  if ground == true or ground == nil and snap.humanoid.FloorMaterial ~= Enum.Material.Air then
    return false
  end
  local fall = units.toBlocks(tonumber(snap.character:GetAttribute("LocalFallDistance")) or 0)
  -- performAttack sends LocalFallDistance as the native fall metadata. Velocity alone is insufficient.
  if fall <= 0 or units.toBlocks(snap.root.AssemblyLinearVelocity.Y) >= -1 / 32 then
    return false
  end
  if snap.character:GetAttribute("Sprinting") == true or snap.character:GetAttribute("SprintRequested") == true then
    return false
  end
  if
    snap.character:GetAttribute("LocalInWater") == true
    or snap.character:GetAttribute("InLava") == true
    or snap.player:GetAttribute("LocalGliding") == true
    or snap.character:GetAttribute("Gliding") == true
  then
    return false
  end
  local state = snap.humanoid:GetState()
  return state ~= Enum.HumanoidStateType.Swimming and state ~= Enum.HumanoidStateType.Climbing and state ~= Enum.HumanoidStateType.Seated
end
function Native.teardown()
  gate = nil
  releaseAttackGate()
  Native.finishCritical()
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
  -- A normal jump rises about 1.25 blocks; aerial mace detection needs more clearance.
  local support = world:Raycast(target.root.Position, units.offset(0, -3.75, 0), params)
  local above = units.toBlocks(target.root.Position.Y - snap.root.Position.Y)
  local fall = units.toBlocks(tonumber(target.character:GetAttribute("LocalFallDistance")) or 0)
  return not support or above > 2.5 or fall > 2.5
end
Native.__contract = {
  provides = {
    "setup",
    "snapshot",
    "stats",
    "visible",
    "canHit",
    "aimDirection",
    "hitDistanceBlocks",
    "incomingHit",
    "attack",
    "readyAt",
    "attackDirection",
    "shieldRear",
    "shieldBlocks",
    "aimPoint",
    "findSword",
    "findPearl",
    "pearlCooldown",
    "pearlReady",
    "usePearl",
    "equip",
    "blocked",
    "isDispatching",
    "prepareCritical",
    "finishCritical",
    "criticalReady",
    "setAttackGate",
    "attackGateReady",
    "replayAttack",
    "teardown",
    "requestJump",
    "crystalJumpRisk",
    "useItem",
    "aerialMace",
  },
  requires = { Utils = "utils", Bridge = "mcpbridge", Units = "mcpunits" },
  requiresMethods = {
    Units = { "toBlocks", "toWorld", "offset" },
    Bridge = { "get", "upvalues" },
    Utils = { "getLocalPlayer", "getWorkspace", "recordError" },
  },
}
return Native
