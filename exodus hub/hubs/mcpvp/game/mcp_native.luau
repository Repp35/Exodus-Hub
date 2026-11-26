-- [[ mcpnative ]]
--!optimize 2
local Native = {}
local utils, bridge, geometry, player, storage, controller, charge
local dispatching, callback, hooked, original, hooker, restoreAim
local lastAttack, lastUse, nextHook = -math.huge, {}, 0
local observed, heldTool, equippedAt = nil, nil, -math.huge
local sprintOwner, sprintWasOn, sprintAt
local missingInput = false
local function library(name)
  local source = storage:FindFirstChild(name)
  local ok, value = pcall(function() return source and require(source) end)
  return ok and type(value) == "table" and value or nil
end
function Native.setup(deps)
  utils, bridge, geometry = deps.Utils, deps.Bridge, deps.Geometry
  player, storage = utils.getLocalPlayer(), game:GetService("ReplicatedStorage")
  controller, charge = library("ControllerInput"), library("HeldItemFov")
  return true
end
function Native.snapshot()
  local character = player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  local human = character and character:FindFirstChildOfClass("Humanoid")
  local camera = workspace.CurrentCamera
  if not root or not human or human.Health <= 0 or not camera or not geometry.allowed(character) then
    return nil
  end
  local tool, now = character:FindFirstChildOfClass("Tool"), os.clock()
  if observed ~= character then
    observed, heldTool, equippedAt = character, tool, -math.huge
  elseif heldTool ~= tool then
    heldTool, equippedAt = tool, now
  end
  return { player = player, character = character, root = root, humanoid = human, camera = camera, eye = geometry.eye(root, character), tool = tool, now = now }
end
function Native.blocked(snap)
  return dispatching == true
    or (controller and controller.IsBlocked())
    or player:GetAttribute("MenuOpen") == true
    or snap.character:GetAttribute("EatingApple") == true
    or snap.character:GetAttribute("DrinkingPotion") == true
    or snap.character:GetAttribute("BowDrawStarted")
    or player:GetAttribute("OffhandUsing") == true
    or snap.root.Anchored
end
function Native.find(snap, kind)
  for _, parent in ipairs({ snap.character, player:FindFirstChild("Backpack") }) do
    for _, tool in ipairs(parent:GetChildren()) do
      if
        tool:IsA("Tool")
        and (geometry.stats(tool).type == kind or tool:GetAttribute("ClassItem") == kind)
        and (tonumber(tool:GetAttribute("Count")) or 1) > 0
      then
        return tool
      end
    end
  end
  return nil
end
function Native.equip(snap, tool)
  if not tool or not tool.Parent or (tool.Parent ~= snap.character and tool.Parent ~= player:FindFirstChild("Backpack")) then
    return false
  end
  if dispatching and tool.Parent ~= snap.character then
    return false
  end
  if tool.Parent ~= snap.character then
    snap.humanoid:EquipTool(tool)
  end
  return tool.Parent == snap.character
end
function Native.charge(snap)
  local speed = geometry.stats(snap.tool).speed or 1.6
  local at = math.max(lastAttack, equippedAt, tonumber(snap.character:GetAttribute("LocalAttackSwing")) or -math.huge)
  local current = math.clamp((snap.now - at) * speed, 0, 1)
  if charge and type(charge.Charge) == "function" then
    local ok, value = pcall(charge.Charge)
    if ok and type(value) == "number" then
      current = math.min(current, math.clamp(value, 0, 1))
    end
  end
  return current
end
local function call(action, snap, direction)
  if Native.blocked(snap) then
    return false
  end
  local fn = bridge.get(action == "Attack" and "attack" or "use")
  local oldDirection, oldFrame = player:GetAttribute("FrontCameraAimDirection"), player:GetAttribute("FrontCameraAimCFrame")
  dispatching = true
  player:SetAttribute("FrontCameraAimDirection", direction)
  local aimFrame = CFrame.lookAt(snap.eye, snap.eye + direction)
  player:SetAttribute("FrontCameraAimCFrame", aimFrame)
  local function restore()
    if restoreAim ~= restore then
      return
    end
    if player:GetAttribute("FrontCameraAimDirection") == direction then
      player:SetAttribute("FrontCameraAimDirection", oldDirection)
    end
    if player:GetAttribute("FrontCameraAimCFrame") == aimFrame then
      player:SetAttribute("FrontCameraAimCFrame", oldFrame)
    end
    restoreAim, dispatching = nil, false
  end
  restoreAim = restore
  local marker = snap.character:GetAttribute("LocalAttackSwing")
  local ok, accepted = pcall(function()
    if fn then
      return fn(direction) ~= false
    end
    if not controller or type(controller.BeginTouch) ~= "function" then
      if not missingInput then
        utils.recordError("mcpvp.input", "Sem acesso ao ataque/uso nativo e ao ControllerInput deste jogo.")
        missingInput = true
      end
      return false
    end
    if not controller.BeginTouch(action) then
      return false
    end
    controller.EndTouch(action)
    return true
  end)
  if fn then
    restore()
  else
    task.defer(restore)
  end
  if not ok then
    utils.recordError("mcpvp.native." .. action, tostring(accepted))
    return false
  end
  if action == "Use" and fn then
    -- This is local submission evidence only. Pearl owns server-side completion checks.
    local class = snap.tool and snap.tool:GetAttribute("ClassItem")
    if class == "Pearl" then
      return snap.character:GetAttribute("LocalAttackSwing") ~= marker
    end
  end
  return accepted == true
end
function Native.attack(snap, target, direction)
  if snap.now - lastAttack < 1 / 7 or Native.blocked(snap) then
    return false
  end
  direction = direction or geometry.direction(snap, target, snap.tool)
  if not direction then
    return false
  end
  lastAttack = snap.now
  return call("Attack", snap, direction)
end
function Native.use(snap, tool, direction)
  local class = tool and tool:GetAttribute("ClassItem")
  if type(class) ~= "string" or (tonumber(tool:GetAttribute("Count")) or 0) < 1 or not Native.equip(snap, tool) or Native.blocked(snap) then
    return false
  end
  local config = library("GameConfig")
  local cooldown = config and config.Items[class] and config.Items[class].cooldown or 0.36
  if snap.now - (lastUse[class] or -math.huge) < cooldown then
    return false
  end
  if (tonumber(player:GetAttribute("ItemCooldown_" .. class)) or 0) > workspace:GetServerTimeNow() then
    return false
  end
  snap.tool = tool
  local sent = call("Use", snap, direction)
  if sent then
    lastUse[class] = snap.now
  end
  return sent
end
function Native.jump(snap)
  if Native.blocked(snap) or snap.humanoid.Sit or snap.humanoid.PlatformStand then
    return false
  end
  snap.humanoid.Jump = true
  snap.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
  return true
end
function Native.sprint(snap, stop, force)
  local folder = storage:FindFirstChild("VoxelCombat")
  local remote = folder and folder:FindFirstChild("Sprint")
  if not remote then
    return
  end
  if stop then
    if sprintOwner ~= snap.character then
      sprintOwner, sprintWasOn = snap.character, snap.character:GetAttribute("Sprinting") == true or snap.character:GetAttribute("SprintRequested") == true
    end
    if force or snap.now >= (sprintAt or 0) then
      remote:FireServer(false)
      sprintAt = snap.now + 0.08
    end
  elseif sprintOwner then
    if
      sprintOwner == snap.character
      and sprintWasOn
      and player:GetAttribute("SprintToggleEnabled") == true
      and snap.humanoid.MoveDirection.Magnitude > 0.05
    then
      remote:FireServer(true)
    end
    sprintOwner, sprintWasOn, sprintAt = nil, nil, nil
  end
end
function Native.gate(fn)
  callback = fn
  if hooked or not fn or os.clock() < nextHook then
    return hooked ~= nil
  end
  nextHook = os.clock() + 1
  local env = type(getgenv) == "function" and getgenv() or _G
  local attack = bridge.get("attack")
  if not attack or type(env.hookfunction) ~= "function" then
    return false
  end
  local previous
  local ok, value = pcall(env.hookfunction, attack, function(direction)
    if dispatching or not callback then
      return previous(direction)
    end
    local snap = Native.snapshot()
    if not snap then
      return previous(direction)
    end
    local success, allow = pcall(callback, snap, direction)
    if not success then
      utils.recordError("mcpvp.manual", tostring(allow))
      return previous(direction)
    end
    if allow then
      return previous(direction)
    end
  end)
  if ok and type(value) == "function" then
    previous, original, hooked, hooker = value, value, attack, env.hookfunction
  end
  return hooked ~= nil
end
function Native.isDispatching() return dispatching == true end
function Native.busy() return dispatching == true end
function Native.reset()
  if restoreAim then
    restoreAim()
  end
  local snap = Native.snapshot()
  if snap then
    Native.sprint(snap, false)
  end
  lastAttack, lastUse, observed, heldTool, equippedAt = -math.huge, {}, nil, nil, -math.huge
end
function Native.teardown()
  callback = nil
  if hooked and original and hooker then
    pcall(hooker, hooked, original)
  end
  hooked, original, hooker = nil, nil, nil
  Native.reset()
end
Native.__contract = {
  provides = {
    "setup",
    "snapshot",
    "blocked",
    "find",
    "equip",
    "charge",
    "attack",
    "use",
    "jump",
    "sprint",
    "gate",
    "isDispatching",
    "busy",
    "reset",
    "teardown",
  },
  requires = { Utils = "utils", Bridge = "mcpbridge", Geometry = "mcpgeometry" },
  requiresMethods = { Utils = { "getLocalPlayer", "recordError" }, Bridge = { "get" }, Geometry = { "allowed", "eye", "stats", "direction" } },
}
return Native
