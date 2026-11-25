-- [[ autopearl ]]
--!optimize 2
local Pearl = {}
local native, target, ballistics
local shot, sending, retryAt = nil, false, 0
local speed, gravity, drag = 96, 38.4, 0.99

local function restore()
  local snap = native.snapshot()
  if not snap or not shot or snap.character ~= shot.character then return end
  if snap.tool == shot.tool or snap.tool == nil then
    local sword = native.findSword(snap)
    if sword then native.equip(snap, sword) end
  end
end
function Pearl.setup(deps)
  native, target, ballistics = deps.Native, deps.Target, deps.Ballistics
  return true
end
function Pearl.reset()
  restore()
  shot, sending = nil, false
end
function Pearl.busy() return sending or (shot ~= nil and shot.phase == "confirm") end
function Pearl.observeProjectile(action, _id, kind, _position, velocity, acceleration, resistance)
  if action ~= "Projectile" or kind ~= "Pearl" or typeof(velocity) ~= "Vector3" then return end
  if velocity.Magnitude > 0 and velocity.Magnitude < 1000 then speed = velocity.Magnitude end
  if type(acceleration) == "number" and acceleration > 0 and acceleration < 1000 then gravity = acceleration end
  if type(resistance) == "number" and resistance > 0 and resistance <= 1 then drag = resistance end
end

local function plan(snap, chosen)
  local params, ignored = RaycastParams.new(), { snap.camera }
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player.Character then ignored[#ignored + 1] = player.Character end
  end
  for _, name in ipairs({ "LocalItemVisuals", "PredictedBlocks", "ArenaPvPBots" }) do
    local folder = workspace:FindFirstChild(name)
    if folder then ignored[#ignored + 1] = folder end
  end
  params.FilterType, params.RespectCanCollide, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  local motion = chosen.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
  if motion.Magnitude > 45 then motion = Vector3.zero end
  local flight = 0.3
  for _ = 1, 8 do
    local point = chosen.root.Position + motion * flight
    local floor = workspace:Raycast(point + Vector3.new(0, 0.5, 0), Vector3.new(0, -128, 0), params)
    if not floor then break end
    local aim, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 6, drag)
    if not aim then break end
    if math.abs(duration - flight) * math.max(1, motion.Magnitude) < 0.5 then return aim, duration end
    flight = duration
  end
  local delta = chosen.root.Position - snap.root.Position
  for _, distance in ipairs({ 160, 128, 96, 64, 32 }) do
    if delta.Magnitude <= distance then continue end
    local point = snap.root.Position + delta.Unit * distance
    local floor = workspace:Raycast(point + Vector3.new(0, 32, 0), Vector3.new(0, -256, 0), params)
    if floor and (floor.Position - chosen.root.Position).Magnitude + 8 < delta.Magnitude then
      local aim, duration = ballistics.solve(snap.eye, floor.Position, speed, gravity, params, 6, drag)
      if aim then return aim, duration end
    end
  end
end

function Pearl.step(snap, chosen)
  if shot and shot.character ~= snap.character then Pearl.reset() end
  if shot then
    if shot.phase == "confirm" then
      local confirmed = not shot.tool.Parent or (tonumber(shot.tool:GetAttribute("Count")) or 0) < shot.count or not native.pearlReady()
      if not confirmed then
        if snap.now >= shot.timeout then Pearl.reset() retryAt = snap.now + 0.25 end
        return false
      end
      restore()
      shot.phase = "flight"
    end
    restore()
    local teleported = snap.character:GetAttribute("PearlTeleportAt") ~= shot.teleportAt
    if not teleported and snap.now < shot.arrivalAt then return false end
    shot = nil
  end
  if not chosen.character.Parent or chosen.humanoid.Health <= 0 then return false end
  target.hold(chosen.character, math.huge)
  if snap.now < retryAt or native.blocked(snap) or not native.pearlReady() or native.canHit(snap, chosen)
    or native.aerialMace(snap, chosen) or not native.visible(snap, chosen.root.Position, chosen.character) then return false end
  retryAt = snap.now + 0.15
  local tool = native.findPearl(snap)
  if not tool then return false end
  local direction, flight = plan(snap, chosen)
  if not direction then return false end
  shot = { character = snap.character, tool = tool, count = tonumber(tool:GetAttribute("Count")) or 1,
    teleportAt = snap.character:GetAttribute("PearlTeleportAt"), phase = "confirm",
    timeout = snap.now + 0.9, arrivalAt = snap.now + flight + 0.4 }
  sending = true
  local ok, sent = pcall(function()
    if not native.equip(snap, tool) then return false end
    local fresh = native.snapshot()
    return fresh and fresh.tool == tool and native.usePearl(fresh, tool, direction)
  end)
  sending = false
  if not ok or not sent then Pearl.reset() if not ok then error(sent) end return false end
  return true
end
Pearl.__contract = {
  provides = { "setup", "reset", "busy", "step", "observeProjectile" },
  requires = { Native = "mcpnative", Target = "mcptarget", Ballistics = "mcpballistics" },
  requiresMethods = { Native = { "snapshot", "findSword", "equip", "findPearl", "usePearl", "pearlReady", "blocked", "canHit", "aerialMace", "visible" }, Target = { "hold" }, Ballistics = { "solve" } },
}
return Pearl
