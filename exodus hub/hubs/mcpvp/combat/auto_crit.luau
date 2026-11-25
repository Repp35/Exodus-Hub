-- [[ autocrit ]]
--!optimize 2
local Crit = {}
local native, utils
local character, jumpAt, previousY, learnedApex, fallbackUntil = nil, nil, 0, 0.25, 0
function Crit.setup(deps) native, utils = deps.Native, deps.Utils return true end
function Crit.reset()
  character, jumpAt, previousY, learnedApex, fallbackUntil = nil, nil, 0, 0.25, 0
end
function Crit.observe(snap)
  if character ~= snap.character then Crit.reset() character = snap.character end
  local vertical = snap.root.AssemblyLinearVelocity.Y
  if jumpAt and previousY > 0 and vertical <= 0 then
    local measured = snap.now - jumpAt
    if measured >= 0.1 and measured <= 0.8 then learnedApex = learnedApex * 0.5 + measured * 0.5 end
  end
  if jumpAt and snap.now - jumpAt > 0.18 and snap.humanoid.FloorMaterial ~= Enum.Material.Air then
    fallbackUntil = snap.now + 0.2
    jumpAt = nil
  end
  previousY = vertical
end
local function unavailable(snap)
  local state = snap.humanoid:GetState()
  local now = workspace:GetServerTimeNow()
  return snap.humanoid.Sit or snap.humanoid.PlatformStand
    or state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Climbing
    or state == Enum.HumanoidStateType.Seated
    or snap.character:GetAttribute("InWater") == true or snap.character:GetAttribute("InLava") == true
    or snap.player:GetAttribute("LocalGliding") == true
    or (tonumber(snap.character:GetAttribute("Effect_blindness")) or 0) > now
    or (tonumber(snap.character:GetAttribute("Effect_slow_falling")) or 0) > now
end
local function room(snap, chosen, reach)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  params.FilterDescendantsInstances = { snap.character, snap.camera, chosen.character }
  if workspace:Raycast(snap.eye, Vector3.new(0, 5, 0), params) then return false end
  local velocity = snap.root.AssemblyLinearVelocity
  local landing = snap.root.Position + Vector3.new(velocity.X, 0, velocity.Z) * (learnedApex * 2)
  local ground = workspace:Raycast(landing, Vector3.new(0, -8, 0), params)
  if not ground or ground.Normal.Y < 0.55 or ground.Material == Enum.Material.Water then return false end
  local block = ground.Instance:GetAttribute("BlockKey")
  if block == "lava" or block == "water" then return false end
  local relative = chosen.root.AssemblyLinearVelocity - velocity
  local future = chosen.root.Position - snap.root.Position + relative * learnedApex
  return Vector3.new(future.X, 0, future.Z).Magnitude <= reach
end
function Crit.ready(snap, chosen, tool, readyAt)
  if not utils.getConfigValue("MCAutoCrit") or unavailable(snap) then return snap.now >= readyAt end
  if snap.now < fallbackUntil then return snap.now >= readyAt end
  local grounded = snap.humanoid.FloorMaterial ~= Enum.Material.Air
  if not grounded then
    if snap.now >= readyAt and snap.root.AssemblyLinearVelocity.Y < -0.2 then
      native.prepareCritical()
      return true
    end
    if jumpAt and snap.now - jumpAt > 1.2 then
      jumpAt, fallbackUntil = nil, snap.now + 0.5
      return snap.now >= readyAt
    end
    return false
  end
  if jumpAt and snap.now - jumpAt < 0.3 then return false end
  if jumpAt then
    jumpAt, fallbackUntil = nil, snap.now + 0.5
    return snap.now >= readyAt
  end
  if readyAt - snap.now > learnedApex then return false end
  if not room(snap, chosen, native.stats(tool).reach) or snap.humanoid.JumpPower == 0 and snap.humanoid.JumpHeight == 0 then
    return snap.now >= readyAt
  end
  if not snap.humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then return snap.now >= readyAt end
  native.prepareCritical()
  snap.humanoid.Jump = true
  jumpAt = snap.now
  return false
end
Crit.__contract = {
  provides = { "setup", "reset", "observe", "ready" },
  requires = { Native = "mcpnative", Utils = "utils" },
  requiresMethods = { Native = { "prepareCritical", "stats" }, Utils = { "getConfigValue" } },
}
return Crit
