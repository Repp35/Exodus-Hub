-- [[ mcpmelee ]]
--!optimize 2
local Melee = {}
local native, target, utils
local owner, jump, selected, manualJump
local nextAttack, equipAt, fallbackAt, apex = 0, 0, 0, 0.25
function Melee.setup(deps)
  native, target, utils = deps.Native, deps.Target, deps.Utils
  return true
end
function Melee.reset()
  owner, jump, selected, manualJump = nil, nil, nil, nil
  nextAttack, equipAt, fallbackAt, apex = 0, 0, 0, 0.25
end
local function grounded(snap)
  local state = snap.character:GetAttribute("VoxelGrounded")
  if type(state) == "boolean" then
    return state
  end
  return snap.humanoid.FloorMaterial ~= Enum.Material.Air
end
local function canJump(snap, chosen, reach)
  local human, char = snap.humanoid, snap.character
  local state = human:GetState()
  if
    human.Sit
    or human.PlatformStand
    or state == Enum.HumanoidStateType.Swimming
    or state == Enum.HumanoidStateType.Climbing
    or char:GetAttribute("LocalInWater")
    or char:GetAttribute("InLava")
    or snap.player:GetAttribute("LocalGliding")
  then
    return false
  end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
  params.FilterDescendantsInstances = { char, snap.camera }
  if chosen then
    params.FilterDescendantsInstances = { char, snap.camera, chosen.character }
  end
  if workspace:Raycast(snap.eye, Vector3.new(0, 5, 0), params) then
    return false
  end
  local velocity = snap.root.AssemblyLinearVelocity
  local landing = snap.root.Position + Vector3.new(velocity.X, 0, velocity.Z) * apex * 2
  local floor = workspace:Raycast(landing, Vector3.new(0, -10, 0), params)
  if not floor or floor.Normal.Y < 0.65 or floor.Material == Enum.Material.Water then
    return false
  end
  local key = floor.Instance:GetAttribute("BlockKey")
  if key == "lava" or key == "water" then
    return false
  end
  if chosen then
    local future = chosen.root.Position - snap.root.Position + (chosen.root.AssemblyLinearVelocity - velocity) * apex
    if Vector3.new(future.X, 0, future.Z).Magnitude > reach + 1.28 then
      return false
    end
  end
  local crystals = game:GetService("CollectionService"):GetTagged("EndCrystal")
  local folder = workspace:FindFirstChild("EndCrystals")
  if folder then
    for _, item in ipairs(folder:GetChildren()) do
      crystals[#crystals + 1] = item
    end
  end
  for _, item in ipairs(crystals) do
    local position = item:GetAttribute("CrystalFeet")
    if typeof(position) ~= "Vector3" and item:IsA("PVInstance") then
      position = item:GetPivot().Position
    end
    if typeof(position) == "Vector3" and (snap.root.Position + Vector3.new(0, 4.1, 0) - position).Magnitude < 38.4 then
      return false
    end
  end
  return true
end
function Melee.manual(snap)
  if owner ~= snap.character then
    Melee.reset()
    owner = snap.character
  end
  if not utils.getConfigValue("MCAutoCrit") or native.blocked(snap) or manualJump or not grounded(snap) then
    return false
  end
  local kind = native.stats(snap.tool).type
  if snap.tool and not kind then
    return false
  end
  if not canJump(snap) then
    return false
  end
  native.prepareCritical()
  manualJump = { character = snap.character, at = snap.now, airborne = false }
  snap.humanoid.Jump = true
  return true
end
function Melee.preSimulation(snap)
  if not manualJump then
    return
  end
  if not snap or snap.character ~= manualJump.character or not utils.getConfigValue("MCAutoCrit") or native.blocked(snap) or snap.now - manualJump.at > 1.5 then
    manualJump = nil
    return
  end
  local ground = grounded(snap)
  if not ground then
    manualJump.airborne = true
  end
  if manualJump.airborne then
    if ground then
      manualJump = nil
    elseif snap.root.AssemblyLinearVelocity.Y < -0.2 then
      native.prepareCritical()
    end
  elseif snap.now - manualJump.at <= 0.35 then
    -- VoxelAirMovement consumes and clears Humanoid.Jump in PreSimulation.
    snap.humanoid.Jump = true
  else
    manualJump = nil
  end
end
local function critical(snap, chosen, tool, readyAt)
  local enabled = utils.getConfigValue("MCAutoCrit")
  local vertical, ground = snap.root.AssemblyLinearVelocity.Y, grounded(snap)
  if not enabled then
    jump = nil
    return snap.now >= readyAt
  end
  if jump then
    if not ground then
      jump.airborne = true
    end
    if jump.airborne and jump.vertical > 0 and vertical <= 0 then
      apex = math.clamp(apex * 0.5 + (snap.now - jump.at) * 0.5, 0.1, 0.8)
    end
    jump.vertical = vertical
    if jump.airborne and ground or not jump.airborne and snap.now - jump.at > 0.35 then
      fallbackAt, jump = snap.now + 0.3, nil
    elseif not jump.airborne then
      snap.humanoid.Jump = true
    end
  end
  if
    not manualJump
    and not jump
    and ground
    and snap.now >= fallbackAt
    and readyAt - snap.now <= apex + 0.03
    and canJump(snap, chosen, native.stats(tool).reach)
  then
    native.prepareCritical()
    jump = { at = snap.now, airborne = false, vertical = vertical }
    snap.humanoid.Jump = true
  end
  if snap.now < readyAt then
    return false
  end
  if not ground and vertical < -0.2 then
    native.prepareCritical()
    return true
  end
  return ground and jump == nil or snap.now < fallbackAt
end
function Melee.step(snap, chosen)
  if owner ~= snap.character then
    Melee.reset()
    owner = snap.character
  end
  if not utils.getConfigValue("MCAutoSword") or not chosen or native.blocked(snap) or native.aerialMace(snap, chosen) then
    jump = nil
    return false
  end
  local tool = native.findSword(snap)
  local stats = native.stats(tool)
  if not tool or stats.type ~= "sword" or type(stats.speed) ~= "number" or stats.speed <= 0 then
    jump = nil
    return false
  end
  if not native.canHit(snap, chosen, tool) then
    jump = nil
    return false
  end
  if snap.tool ~= tool then
    if selected ~= tool or snap.now >= equipAt + 0.75 then
      if native.equip(snap, tool) then
        selected, equipAt = tool, snap.now
      end
    end
    return false
  end
  local swing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or -math.huge
  local readyAt = math.max(nextAttack, swing + 1 / stats.speed)
  local ready = critical(snap, chosen, tool, readyAt)
  if not ready or not native.canHit(snap, chosen, tool, snap.camera.CFrame.LookVector) then
    return false
  end
  if native.attack(snap, chosen) then
    target.noteAttack(snap, chosen)
    nextAttack = snap.now + 1 / stats.speed
    return true
  end
  nextAttack = snap.now + 0.1
  return false
end
Melee.__contract = {
  provides = { "setup", "reset", "step", "manual", "preSimulation" },
  requires = { Native = "mcpnative", Target = "mcptarget", Utils = "utils" },
  requiresMethods = {
    Native = { "blocked", "aerialMace", "findSword", "stats", "canHit", "equip", "prepareCritical", "attack" },
    Target = { "noteAttack" },
    Utils = { "getConfigValue" },
  },
}
return Melee
