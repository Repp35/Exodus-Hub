-- [[ autocrit ]]
--!optimize 2
local Crit = {}
local native, utils
local character, jumpAt, previousY, apex, airborne, fallbackUntil = nil, nil, 0, 0.25, false, 0
local jumpConnection
local function grounded(snap)
  local value = snap.character:GetAttribute("VoxelGrounded")
  if type(value) == "boolean" then return value end
  return snap.humanoid.FloorMaterial ~= Enum.Material.Air
end
local function stopJump()
  if jumpConnection then jumpConnection:Disconnect() jumpConnection = nil end
end
function Crit.setup(deps) native, utils = deps.Native, deps.Utils return true end
function Crit.reset()
  stopJump()
  character, jumpAt, previousY, apex, airborne, fallbackUntil = nil, nil, 0, 0.25, false, 0
end
function Crit.observe(snap)
  if character ~= snap.character then Crit.reset() character = snap.character end
  local vertical = snap.root.AssemblyLinearVelocity.Y
  if jumpAt then
    if not grounded(snap) and vertical > 0.2 then airborne = true stopJump() end
    if airborne and previousY > 0 and vertical <= 0 then
      local elapsed = snap.now - jumpAt
      if elapsed >= 0.1 and elapsed <= 0.8 then apex = apex * 0.5 + elapsed * 0.5 end
    end
    if (airborne and grounded(snap)) or (not airborne and snap.now - jumpAt > 0.35) then
      stopJump()
      fallbackUntil = snap.now + (airborne and 0.03 or 0.3)
      jumpAt, airborne = nil, false
    end
  end
  previousY = vertical
end
local function possible(snap)
  local state = snap.humanoid:GetState()
  return not snap.humanoid.Sit and not snap.humanoid.PlatformStand
    and state ~= Enum.HumanoidStateType.Swimming and state ~= Enum.HumanoidStateType.Climbing
    and snap.character:GetAttribute("LocalInWater") ~= true
    and snap.character:GetAttribute("InLava") ~= true and snap.player:GetAttribute("LocalGliding") ~= true
end
local function room(snap, chosen, reach)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  params.FilterDescendantsInstances = { snap.character, snap.camera, chosen.character }
  if workspace:Raycast(snap.eye, Vector3.new(0, 5, 0), params) then return false end
  local velocity = snap.root.AssemblyLinearVelocity
  local landing = snap.root.Position + Vector3.new(velocity.X, 0, velocity.Z) * (apex * 2)
  local ground = workspace:Raycast(landing, Vector3.new(0, -10, 0), params)
  if not ground or ground.Normal.Y < 0.55 or ground.Material == Enum.Material.Water then return false end
  local block = ground.Instance:GetAttribute("BlockKey")
  if block == "lava" or block == "water" then return false end
  local future = chosen.root.Position - snap.root.Position + (chosen.root.AssemblyLinearVelocity - velocity) * apex
  return Vector3.new(future.X, 0, future.Z).Magnitude <= reach + 1.28
end
function Crit.plan(snap, chosen, tool, readyAt)
  if not utils.getConfigValue("MCAutoCrit") then stopJump() jumpAt = nil return end
  if native.blocked(snap) or not possible(snap) or not grounded(snap) or jumpAt or snap.now < fallbackUntil then return end
  -- Jump before the weapon finishes recharging; alignment gates the strike, never the jump.
  if readyAt - snap.now > apex + 0.03 then return end
  if not room(snap, chosen, native.stats(tool).reach) then return end
  native.prepareCritical()
  jumpAt, airborne = snap.now, false
  local owner, humanoid, root = snap.character, snap.humanoid, snap.root
  local deadline = snap.now + 0.3
  humanoid.Jump = true
  stopJump()
  jumpConnection = game:GetService("RunService").PreSimulation:Connect(function()
    if not utils.isActive() or not utils.getConfigValue("MCAutoCrit") or not root.Parent
      or utils.getLocalPlayer().Character ~= owner or humanoid.Health <= 0 or os.clock() >= deadline
      or owner:GetAttribute("VoxelGrounded") == false and root.AssemblyLinearVelocity.Y > 0.2 then
      stopJump()
      return
    end
    -- VoxelAirMovement consumes this request in its own simulation; no velocity is fabricated.
    humanoid.Jump = true
  end)
end
function Crit.ready(snap, chosen, tool, readyAt)
  if snap.now < readyAt then return false end
  if not utils.getConfigValue("MCAutoCrit") or not possible(snap) then return true end
  if not grounded(snap) and snap.root.AssemblyLinearVelocity.Y < -0.2 then native.prepareCritical() return true end
  if jumpAt then return false end
  -- If a jump cannot start, do not stall normal combat.
  return grounded(snap) or snap.now < fallbackUntil
end
Crit.__contract = {
  provides = { "setup", "reset", "observe", "plan", "ready" },
  requires = { Native = "mcpnative", Utils = "utils" },
  requiresMethods = { Native = { "prepareCritical", "stats", "blocked" }, Utils = { "getConfigValue", "isActive", "getLocalPlayer" } },
}
return Crit
