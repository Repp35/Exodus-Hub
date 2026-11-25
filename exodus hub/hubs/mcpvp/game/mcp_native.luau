-- [[ mcpnative ]]
--!optimize 2
local Native = {}
local player, world, input, storage, environment, api, modules
local functions = {}
local nextScan = 0
local dispatched = {}
local slotTable
local inventorySession
local function owned(tool)
  return typeof(tool) == "Instance"
    and tool:IsA("Tool")
    and tool.Parent ~= nil
    and (tool.Parent == player.Character or tool.Parent == player:FindFirstChild("Backpack"))
end
local function loadModule(name)
  local source = storage:FindFirstChild(name)
  if not source or not source:IsA("ModuleScript") then
    return nil
  end
  local ok, result = pcall(require, source)
  return ok and type(result) == "table" and result or nil
end
function Native.setup(deps)
  api = deps.Utils
  player, world = api.getLocalPlayer(), api.getWorkspace()
  storage, input = game:GetService("ReplicatedStorage"), game:GetService("UserInputService")
  environment = type(getgenv) == "function" and getgenv() or _G
  modules = {
    config = loadModule("GameConfig"),
    controller = loadModule("ControllerInput"),
    weapons = loadModule("VoxelWeapons"),
    geometry = loadModule("VoxelMeleeGeometry"),
    placement = loadModule("VoxelBlockPlacement"),
    shield = loadModule("ShieldRules"),
  }
  return true
end
function Native.discover()
  if functions.attack and functions.use and functions.place and functions.refresh and functions.open and functions.select then
    return
  end
  if os.clock() < nextScan then
    return
  end
  nextScan = os.clock() + 5
  local gc = environment.getgc
  if type(gc) ~= "function" then
    return
  end
  local ok, objects = pcall(gc, false)
  if not ok or type(objects) ~= "table" then
    return
  end
  local scripts = player:FindFirstChild("PlayerScripts")
  local wanted = {
    VoxelCombatClient = { performAttack = "attack" },
    ItemClient = { use = "use" },
    VoxelBuildingClient = { place = "place" },
    VoxelPackHUD = { refreshTools = "refresh", setOpen = "open", selectSlot = "select" },
  }
  for _, fn in pairs(objects) do
    if type(fn) ~= "function" then
      continue
    end
    local envOK, env = pcall(getfenv, fn)
    local source = envOK and env and env.script
    if typeof(source) ~= "Instance" or not scripts or source.Parent ~= scripts then
      continue
    end
    local names = wanted[source.Name]
    if not names then
      continue
    end
    local nameOK, name = pcall(debug.info, fn, "n")
    if nameOK and names[name] then
      functions[names[name]] = fn
    end
  end
  slotTable = nil
end
function Native.slots()
  if slotTable then
    for _, value in pairs(slotTable) do
      if owned(value) then
        return slotTable
      end
    end
    slotTable = nil
  end
  local getter = environment.getupvalues or (environment.debug and environment.debug.getupvalues)
  if type(getter) ~= "function" or not functions.refresh then
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
    for key, item in pairs(value) do
      if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 36 or not owned(item) then
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
function Native.move(tool, destination)
  local slots = Native.slots()
  if not Native.inventoryOpen() or not slots or not owned(tool) or destination < 1 or destination > 9 or slots[destination] then
    return false
  end
  local index = table.find(slots, tool)
  -- The native table is sparse; table.find alone does not traverse inventory holes.
  if not index then
    for key, value in pairs(slots) do
      if value == tool then
        index = key
        break
      end
    end
  end
  if not index then
    return false
  end
  slots[index], slots[destination] = nil, tool
  local ok = pcall(functions.refresh)
  if not ok then
    slots[index], slots[destination] = tool, nil
  end
  return ok
end
function Native.items()
  local items, slots = {}, Native.slots()
  for _, parent in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
    if not parent then
      continue
    end
    for _, tool in ipairs(parent:GetChildren()) do
      if not tool:IsA("Tool") then
        continue
      end
      local slot
      if slots then
        for key, value in pairs(slots) do
          if value == tool then
            slot = key
            break
          end
        end
      end
      items[#items + 1] = {
        tool = tool,
        class = tool:GetAttribute("ClassItem"),
        block = tool:GetAttribute("BlockKey"),
        weapon = tool:GetAttribute("WeaponType"),
        count = tonumber(tool:GetAttribute("Count")) or 1,
        slot = slot,
      }
    end
  end
  table.sort(items, function(a, b) return (a.slot or 99) < (b.slot or 99) end)
  return items
end
function Native.find(class, hotbar)
  for _, item in ipairs(Native.items()) do
    if item.count > 0 and (item.class == class or item.block == class or item.weapon == class) and (not hotbar or (item.slot and item.slot <= 9)) then
      return item
    end
  end
  return nil
end
function Native.equipped()
  local character = player.Character
  return character and character:FindFirstChildOfClass("Tool")
end
function Native.equip(tool)
  if not owned(tool) then
    return false
  end
  if Native.equipped() == tool then
    return true
  end
  local slots = Native.slots()
  if not slots or type(functions.select) ~= "function" then
    return false
  end
  for slot = 1, 9 do
    if slots[slot] == tool then
      local ok = pcall(functions.select, slot)
      return ok and Native.equipped() == tool
    end
  end
  return false
end
local function inventoryFrame()
  local gui = player:FindFirstChildOfClass("PlayerGui")
  if gui then
    for _, object in ipairs(gui:GetDescendants()) do
      if object.Name == "Inventory" and object:IsA("GuiObject") and object.Visible then
        local parent = object.Parent
        local visible = true
        while parent and parent ~= gui do
          if (parent:IsA("GuiObject") and not parent.Visible) or (parent:IsA("ScreenGui") and not parent.Enabled) then
            visible = false
            break
          end
          parent = parent.Parent
        end
        if visible then
          return object
        end
      end
    end
  end
  return nil
end
function Native.inventoryOpen() return inventorySession ~= nil and inventoryFrame() ~= nil end
function Native.closeInventory()
  local session = inventorySession
  inventorySession = nil
  if not session then
    return
  end
  if session.connection then
    session.connection:Disconnect()
  end
  game:GetService("ContextActionService"):UnbindAction("ExodusMCPInventory")
  local human = session.humanoid
  if human.Parent then
    human:SetStateEnabled(Enum.HumanoidStateType.Jumping, session.jumping)
    if human.WalkSpeed == 0 then
      human.WalkSpeed = session.speed
    end
    human.Jump = false
  end
  if session.opened and functions.open then
    pcall(functions.open, false)
  end
end
function Native.openInventory()
  if Native.inventoryOpen() then
    return true
  end
  if inventorySession then
    Native.closeInventory()
  end
  if not Native.ready() or type(functions.open) ~= "function" then
    return false
  end
  local human = player.Character:FindFirstChildOfClass("Humanoid")
  local session = { humanoid = human, speed = human.WalkSpeed, jumping = human:GetStateEnabled(Enum.HumanoidStateType.Jumping), opened = true }
  inventorySession = session
  game:GetService("ContextActionService"):BindActionAtPriority(
    "ExodusMCPInventory",
    function() return Enum.ContextActionResult.Sink end,
    false,
    4000,
    Enum.PlayerActions.CharacterForward,
    Enum.PlayerActions.CharacterBackward,
    Enum.PlayerActions.CharacterLeft,
    Enum.PlayerActions.CharacterRight,
    Enum.PlayerActions.CharacterJump
  )
  local function freeze()
    if not human.Parent then
      return
    end
    human.WalkSpeed, human.Jump = 0, false
    human:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    human:Move(Vector3.zero, false)
    local root = human.Parent:FindFirstChild("HumanoidRootPart")
    if root then
      local velocity = root.AssemblyLinearVelocity
      root.AssemblyLinearVelocity = Vector3.new(0, math.min(0, velocity.Y), 0)
    end
  end
  freeze()
  session.connection = game:GetService("RunService").Heartbeat:Connect(freeze)
  local ok = pcall(functions.open, true)
  if not ok or not Native.inventoryOpen() then
    Native.closeInventory()
    return false
  end
  return true
end
function Native.restore(tool, expected)
  -- Obsidian is equipped only by an explicit block-placement job or player input.
  if tool and tool:GetAttribute("BlockKey") == "obsidian" then
    return
  end
  local current = Native.equipped()
  if current ~= expected and not (current == nil and expected and not owned(expected)) then
    return
  end
  if tool and owned(tool) then
    Native.equip(tool)
  elseif not tool then
    local human = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if human then
      human:UnequipTools()
    end
  end
end
function Native.ready()
  if not inventorySession and modules.controller and type(modules.controller.IsBlocked) == "function" and modules.controller.IsBlocked() then
    return false
  end
  if not api.isActive() or input:GetFocusedTextBox() then
    return false
  end
  if
    player:GetAttribute("InArena") ~= true
    or player:GetAttribute("ArenaProtected") == true
    or (player:GetAttribute("MenuOpen") and not Native.inventoryOpen())
    or player:GetAttribute("LobbyFreeMouse") == true
  then
    return false
  end
  local char = player.Character
  local human = char and char:FindFirstChildOfClass("Humanoid")
  return human ~= nil
    and human.Health > 0
    and char:FindFirstChild("Head") ~= nil
    and char:FindFirstChild("HumanoidRootPart") ~= nil
    and world.CurrentCamera ~= nil
end
function Native.snapshot()
  if not Native.ready() then
    return nil
  end
  local char = player.Character
  local pingOK, ping = pcall(player.GetNetworkPing, player)
  return {
    ping = pingOK and math.clamp(tonumber(ping) or 0, 0, 0.3) or 0,
    character = char,
    humanoid = char:FindFirstChildOfClass("Humanoid"),
    root = char.HumanoidRootPart,
    eye = modules.geometry and modules.geometry.Eye(char.HumanoidRootPart.Position, char:GetAttribute("Sneaking")) or char.Head.Position,
    camera = world.CurrentCamera,
    now = os.clock(),
    server = world:GetServerTimeNow(),
    equipped = Native.equipped(),
    player = player,
    world = world,
  }
end
function Native.raycast(origin, delta, extra)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  local ignore = { player.Character }
  for _, name in ipairs({ "PredictedBlocks", "LocalItemVisuals", "LocalBowVisuals" }) do
    local folder = world:FindFirstChild(name)
    if folder then
      ignore[#ignore + 1] = folder
    end
  end
  for _, object in ipairs(extra or {}) do
    ignore[#ignore + 1] = object
  end
  params.FilterDescendantsInstances, params.RespectCanCollide = ignore, true
  return world:Raycast(origin, delta, params)
end
function Native.visible(origin, point, target)
  local delta = point - origin
  if delta.Magnitude < 0.01 then
    return true
  end
  local hit = Native.raycast(origin, delta)
  return not hit or hit.Distance >= delta.Magnitude - 0.15 or (target and (hit.Instance == target or hit.Instance:IsDescendantOf(target)))
end
function Native.aim(point, dt, speed)
  local camera = world.CurrentCamera
  if not camera then
    return false
  end
  local delta = point - camera.CFrame.Position
  if delta.Magnitude < 0.01 then
    return false
  end
  local angle = math.acos(math.clamp(camera.CFrame.LookVector:Dot(delta.Unit), -1, 1))
  local alpha = angle < 0.001 and 1 or math.min(1, math.rad(speed) * dt / angle)
  camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position, point), alpha)
  return angle <= math.rad(2)
end
-- Native closures retain their sequence counters, cooldowns and placement validation.
-- No fabricated attack packets or server acknowledgements are generated here.
function Native.canAct(kind, item)
  local now = os.clock()
  if kind == "anchor" then
    return now - math.max(dispatched.anchor or -math.huge, dispatched.Glowstone or -math.huge) >= 0.2
  end
  if kind == "attack" then
    return now - (dispatched.attack or -math.huge) >= 1 / 15
  end
  if kind == "use" then
    local tool = item or Native.equipped()
    local class = tool and tool:GetAttribute("ClassItem")
    if not class then
      return false
    end
    local config = modules.config and modules.config.Items[class]
    local delay = math.max(config and (tonumber(config.useDelay) or 0.35) + 0.01 or 0.36, config and (tonumber(config.cooldown) or 0) - 0.02 or 0)
    return now - (dispatched[class] or -math.huge) >= delay and (tonumber(player:GetAttribute("ItemCooldown_" .. class)) or 0) <= world:GetServerTimeNow()
  end
  return true
end
function Native.action(kind, point)
  if not Native.canAct(kind) then
    return false
  end
  local fn = functions[kind]
  if type(fn) ~= "function" or not Native.ready() then
    return false
  end
  if Native.inventoryOpen() then
    return false
  end
  local oldCF, oldDir = player:GetAttribute("FrontCameraAimCFrame"), player:GetAttribute("FrontCameraAimDirection")
  if point then
    local origin = Native.snapshot().eye
    if (point - origin).Magnitude < 0.01 then
      return false
    end
    local cf = CFrame.lookAt(origin, point)
    -- Both native aim readers accept these attributes without changing CurrentCamera.
    player:SetAttribute("FrontCameraAimCFrame", cf)
    player:SetAttribute("FrontCameraAimDirection", cf.LookVector)
  end
  local tool = Native.equipped()
  local key = kind == "use" and tool and tool:GetAttribute("ClassItem") or kind
  if key then
    dispatched[key] = os.clock()
  end
  local ok, err = pcall(fn)
  if point then
    player:SetAttribute("FrontCameraAimCFrame", oldCF)
    player:SetAttribute("FrontCameraAimDirection", oldDir)
  end
  if not ok then
    error(err)
  end
  return true
end
function Native.usingHeld()
  local controller = modules.controller
  return controller and type(controller.IsHeld) == "function" and controller.IsHeld("Use") or false
end
function Native.observeAttacks(callback)
  local controller = modules.controller
  if not controller or not controller.InputBegan or type(controller.Matches) ~= "function" then
    return { Disconnect = function() end }
  end
  return controller.InputBegan:Connect(function(event, processed)
    if not processed and controller.Matches(event, "Attack") then
      callback()
    end
  end)
end
function Native.strike(point)
  local snap = Native.snapshot()
  local fn = functions.attack
  if not snap or Native.inventoryOpen() or type(fn) ~= "function" or not Native.canAct("attack") then
    return false
  end
  local delta = point - snap.eye
  if delta.Magnitude < 0.01 then
    return false
  end
  -- performAttack(direction) is an explicit native parameter in the dump; its geometry and server packet validation remain intact.
  dispatched.attack = os.clock()
  local ok, err = pcall(fn, delta.Unit)
  if not ok then
    error(err)
  end
  return true
end
function Native.anchor(point)
  if not Native.canAct("anchor") then
    return false
  end
  local remote = storage:FindFirstChild("Remotes")
  remote = remote and remote:FindFirstChild("RespawnAnchor")
  local snap = Native.snapshot()
  if not snap or not remote or not remote:IsA("RemoteEvent") then
    return false
  end
  local delta = point - snap.eye
  if delta.Magnitude < 0.01 then
    return false
  end
  local hit = Native.raycast(snap.eye, delta.Unit * (delta.Magnitude + 2))
  if not hit or hit.Instance:GetAttribute("BlockKey") ~= "respawn_anchor" or (hit.Position - snap.eye).Magnitude > 14.9 then
    return false
  end
  dispatched.anchor = os.clock()
  remote:FireServer(delta.Unit, hit.Position)
  return true
end
function Native.offhand(tool, done, directTotem)
  local folder = storage:FindFirstChild("Remotes")
  local remote = folder and folder:FindFirstChild("InventoryAction")
  local inHotbar, knownSlot = false, false
  for slot, value in pairs(Native.slots() or {}) do
    if value == tool then
      inHotbar, knownSlot = slot <= 9, true
    end
  end
  if
    not remote
    or not remote:IsA("RemoteFunction")
    or not owned(tool)
    or not knownSlot
    or (not directTotem and inHotbar and Native.equipped() ~= tool)
    or (not directTotem and not inHotbar and not Native.inventoryOpen())
  then
    done(false)
    return
  end
  task.spawn(function()
    local ok, result = pcall(remote.InvokeServer, remote, "EquipOffhand", tool)
    done(ok and result ~= nil and result ~= false)
  end)
end
function Native.prepareCritical()
  local combat = storage:FindFirstChild("VoxelCombat")
  local sprint = combat and combat:FindFirstChild("Sprint")
  if sprint and sprint:IsA("RemoteEvent") then
    sprint:FireServer(false)
  end
end
function Native.apple(begin)
  local remote = storage:FindFirstChild("EatGoldenApple")
  if not remote or not remote:IsA("RemoteEvent") then
    return false
  end
  remote:FireServer(begin and "Begin" or "Cancel")
  return true
end
function Native.stats(tool)
  if modules.weapons then
    return modules.weapons.Stats(tool)
  end
  return { type = tool and tool:GetAttribute("WeaponType"), speed = 1.6, reach = 9.6 }
end
function Native.data() return modules end
function Native.capabilities()
  return {
    attack = functions.attack ~= nil,
    use = functions.use ~= nil,
    place = functions.place ~= nil,
    inventory = Native.slots() ~= nil and functions.open ~= nil and functions.select ~= nil,
  }
end
function Native.teardown()
  Native.closeInventory()
  functions, slotTable, nextScan, dispatched = {}, nil, 0, {}
end
Native.__contract = {
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getLocalPlayer", "getWorkspace", "isActive" } },
  provides = {
    "setup",
    "teardown",
    "discover",
    "slots",
    "move",
    "inventoryOpen",
    "openInventory",
    "closeInventory",
    "items",
    "find",
    "equipped",
    "equip",
    "restore",
    "ready",
    "snapshot",
    "raycast",
    "visible",
    "aim",
    "action",
    "strike",
    "observeAttacks",
    "usingHeld",
    "canAct",
    "anchor",
    "offhand",
    "prepareCritical",
    "apple",
    "stats",
    "data",
    "capabilities",
  },
}
return Native
