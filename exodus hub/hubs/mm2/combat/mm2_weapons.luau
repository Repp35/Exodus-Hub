-- [[ mm2 weapons ]]
--!optimize 2

local Weapons = {}
local State, Targeting, Utils
local lastShot, lastStab, lastThrow, equipped, equippedAt = -math.huge, -math.huge, -math.huge, nil, 0
local random = Random.new()
function Weapons.setup(deps)
  State, Targeting, Utils = deps.State, deps.Targeting, deps.Utils
  return true
end
function Weapons.reset()
  equipped, equippedAt = nil, 0
  lastShot, lastStab, lastThrow = -math.huge, -math.huge, -math.huge
end
local function equip(snap, name)
  local tool = State.tool(snap, name, true)
  if tool ~= equipped then
    equipped, equippedAt = tool, os.clock()
    return
  end
  if not tool or tool.Parent ~= snap.character or os.clock() - equippedAt < 0.2 then
    return
  end
  return tool
end
local function event(parent, name)
  local object = parent and parent:FindFirstChild(name)
  return object and object:IsA("RemoteEvent") and object
end
function Weapons.shoot(automatic)
  local now = os.clock()
  if not Utils.isActive() or now - lastShot < 3.1 then
    return false
  end
  local snap = State.live(Utils.getLocalPlayer(), true)
  local target = State.findRole("Murderer")
  if not snap or not target or target.player == snap.player or snap.role == "Murderer" then
    return false
  end
  if Utils.getConfigValue("MM2LegitSheriff") and not target.character:FindFirstChild("Knife") then
    return false
  end
  local gun = equip(snap, "Gun")
  if not gun then
    return false
  end
  local shoot = event(gun, "Shoot")
  if not shoot then
    return false
  end
  local attachment = snap.root:FindFirstChild("GunRaycastAttachment") or gun:FindFirstChild("GunRaycastAttachment", true)
  local handle = gun:FindFirstChild("Handle")
  local origin = attachment and attachment:IsA("Attachment") and attachment.WorldPosition
    or handle and handle:IsA("BasePart") and handle.Position
    or snap.root.Position
  local point = Targeting.predict(origin, target, 1200)
  if not Targeting.clear(snap, target, origin, point) then
    return false
  end
  local accuracy = math.clamp(tonumber(Utils.getConfigValue(automatic and "MM2AutoAccuracy" or "MM2ManualAccuracy")) or 100, 0, 100)
  if random:NextNumber(0, 100) > accuracy then
    point += Vector3.new(random:NextNumber(5, 9), random:NextNumber(4, 7), 0)
  end
  lastShot = now
  shoot:FireServer(origin, CFrame.new(point))
  return true
end
function Weapons.step()
  if Utils.getConfigValue("MM2ManualShoot") then
    local snap = State.live(Utils.getLocalPlayer(), true)
    if snap and snap.role ~= "Murderer" and State.tool(snap, "Gun", false) then
      equip(snap, "Gun")
    end
  end
  if Utils.getConfigValue("MM2AutoShoot") then
    Weapons.shoot(true)
  end
  local snap = State.live(Utils.getLocalPlayer(), true)
  if not snap or snap.role ~= "Murderer" then
    return
  end
  if not Utils.getConfigValue("MM2AutoStab") and not Utils.getConfigValue("MM2AutoThrow") then
    return
  end
  local knife = equip(snap, "Knife")
  if not knife then
    return
  end
  local now = os.clock()
  local events = knife:FindFirstChild("Events")
  local charge = math.clamp(tonumber(knife:GetAttribute("ThrowSpeed")) or 0.5, 0.05, 3)
  if Utils.getConfigValue("MM2AutoStab") and now - lastStab >= 0.85 and now - lastThrow >= charge then
    local target = Targeting.select(snap, Utils.getConfigValue("MM2StabTargets"), 6)
    local stabbed, touched = event(events, "KnifeStabbed"), event(events, "HandleTouched")
    if target and stabbed and touched then
      lastStab = now
      stabbed:FireServer()
      touched:FireServer(target.character:FindFirstChild("UpperTorso") or target.character:FindFirstChild("Torso") or target.root)
      return
    end
  end
  if Utils.getConfigValue("MM2AutoThrow") and snap.character:GetAttribute("Zombie") ~= true and now - lastThrow >= charge * 2 and now - lastStab >= 0.85 then
    local target = Targeting.select(snap, Utils.getConfigValue("MM2ThrowTargets"), 250)
    local thrown = event(events, "KnifeThrown")
    local handle = knife:FindFirstChild("Handle")
    if target and thrown and handle and handle:IsA("BasePart") then
      local point = Targeting.predict(handle.Position, target, 100)
      if Targeting.clear(snap, target, handle.Position, point) then
        lastThrow = now
        thrown:FireServer(handle.CFrame, CFrame.new(point))
      end
    end
  end
end
Weapons.__contract = {
  provides = { "setup", "reset", "shoot", "step" },
  requires = { State = "mm2state", Targeting = "mm2targeting", Utils = "utils" },
  requiresMethods = {
    State = { "live", "findRole", "tool" },
    Targeting = { "clear", "select", "predict" },
    Utils = { "isActive", "getConfigValue", "getLocalPlayer" },
  },
}
return Weapons
