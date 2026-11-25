-- [[ mcpnative ]]
--!optimize 2
local Native = {}
local player, world, storage, weapons, geometry, config
local sequence = 0
local function load(name)
  local source = storage:FindFirstChild(name)
  if not source then
    return nil
  end
  local ok, result = pcall(require, source)
  return ok and type(result) == "table" and result or nil
end
function Native.setup(deps)
  player, world = deps.Utils.getLocalPlayer(), deps.Utils.getWorkspace()
  storage = game:GetService("ReplicatedStorage")
  weapons, geometry, config = load("VoxelWeapons"), load("VoxelMeleeGeometry"), load("GameConfig")
  return true
end
function Native.snapshot()
  local char = player.Character
  local root = char and char:FindFirstChild("HumanoidRootPart")
  local human = char and char:FindFirstChildOfClass("Humanoid")
  local camera = world.CurrentCamera
  if not root or not human or human.Health <= 0 or not camera or player:GetAttribute("InArena") == false then
    return nil
  end
  local head = char:FindFirstChild("Head")
  return {
    player = player,
    character = char,
    root = root,
    humanoid = human,
    camera = camera,
    eye = head and head.Position or root.Position,
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
function Native.visible(snap, point, target)
  local params = RaycastParams.new()
  params.RespectCanCollide = true
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances = { snap.character }
  local hit = world:Raycast(snap.eye, point - snap.eye, params)
  return not hit or (target ~= nil and hit.Instance:IsDescendantOf(target))
end
function Native.canHit(snap, target)
  local stats = Native.stats(snap.tool)
  if stats.type ~= "sword" then
    return false
  end
  local delta = target.root.Position - snap.eye
  if delta.Magnitude < 0.01 then
    return false
  end
  if geometry and type(geometry.Hit) == "function" then
    if not geometry.Hit(snap.eye, delta.Unit, target.root.Position, target.character:GetAttribute("Sneaking"), stats.reach) then
      return false
    end
  elseif delta.Magnitude > stats.reach then
    return false
  end
  return Native.visible(snap, target.root.Position, target.character)
end
function Native.attack(snap, target)
  if not Native.canHit(snap, target) then
    return false
  end
  local folder = storage:FindFirstChild("VoxelCombat")
  local remote = folder and folder:FindFirstChild("Attack")
  if not remote or not remote:IsA("RemoteEvent") then
    return false
  end
  local direction = (target.root.Position - snap.eye).Unit
  sequence += 1
  remote:FireServer(
    target.character,
    snap.eye + direction * Native.stats(snap.tool).reach,
    direction,
    nil,
    { version = 2, character = snap.character, seq = sequence, sentAt = world:GetServerTimeNow(), targetRoot = target.root.Position, eye = snap.eye }
  )
  snap.character:SetAttribute("LocalAttackSwing", snap.now)
  return true
end
function Native.findPearl(snap)
  local backpack = player:FindFirstChild("Backpack")
  for _, parent in ipairs({ snap.character, backpack }) do
    if not parent then
      continue
    end
    for _, tool in ipairs(parent:GetChildren()) do
      if tool:IsA("Tool") and tool:GetAttribute("ClassItem") == "Pearl" and (tonumber(tool:GetAttribute("Count")) or 1) > 0 then
        return tool
      end
    end
  end
  return nil
end
function Native.pearlCooldown() return config and config.Items and config.Items.Pearl and config.Items.Pearl.cooldown or 1 end
function Native.usePearl(snap, tool, direction)
  if not tool or tool.Parent ~= snap.character then
    return false
  end
  local folder = storage:FindFirstChild("Remotes")
  local remote = folder and folder:FindFirstChild("ItemAction")
  if not remote or not remote:IsA("RemoteEvent") then
    return false
  end
  if (tonumber(player:GetAttribute("ItemCooldown_Pearl")) or 0) > world:GetServerTimeNow() then
    return false
  end
  remote:FireServer("Use", "Pearl", direction)
  return true
end
function Native.equip(snap, tool)
  if not tool or not tool.Parent then
    return false
  end
  if tool.Parent ~= snap.character and tool.Parent ~= player:FindFirstChild("Backpack") then
    return false
  end
  snap.humanoid:EquipTool(tool)
  return tool.Parent == snap.character
end
Native.__contract = {
  provides = { "setup", "snapshot", "stats", "visible", "canHit", "attack", "findPearl", "pearlCooldown", "usePearl", "equip" },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getLocalPlayer", "getWorkspace" } },
}
return Native
