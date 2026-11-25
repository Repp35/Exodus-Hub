-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players
local current, pending, clicks, lastClick, contact = nil, nil, 0, -math.huge, -math.huge
local swings, threats = {}, {}
local watchedCharacter, lastHealth, hurtAt, switchedAt = nil, nil, -math.huge, -math.huge
function Target.setup(deps)
  native, tuning, players = deps.Native, deps.Options.tuning, game:GetService("Players")
  return true
end
function Target.reset()
  current, pending, clicks, lastClick, contact = nil, nil, 0, -math.huge, -math.huge
  swings, threats = {}, {}
  watchedCharacter, lastHealth, hurtAt, switchedAt = nil, nil, -math.huge, -math.huge
end
local function candidate(other, snap)
  if other == snap.player or other.Parent ~= players or other:GetAttribute("ArenaProtected") == true or other:GetAttribute("InArena") == false then return nil end
  local char = other.Character
  local human = char and char:FindFirstChildOfClass("Humanoid")
  local root = char and char:FindFirstChild("HumanoidRootPart")
  if not root or not human or human.Health <= 0 or char:FindFirstChildOfClass("ForceField") then return nil end
  if (root.Position - snap.root.Position).Magnitude > tuning.maxRange then return nil end
  return { player = other, character = char, root = root, humanoid = human }
end
local function closeVisible(snap, other)
  return native.canHit(snap, other) and native.visible(snap, other.root.Position, other.character)
end
function Target.noteSwing(source)
  if typeof(source) ~= "Instance" then return end
  if source:IsA("Player") then source = source.Character end
  if not source or not source:IsA("Model") then return end
  -- Swing identifies its character in the dump, unlike the damage feedback.
  if not players:GetPlayerFromCharacter(source) then return end
  swings[source] = os.clock()
end
function Target.observe(snap)
  if watchedCharacter ~= snap.character then
    swings, threats = {}, {}
    watchedCharacter, lastHealth, hurtAt = snap.character, snap.humanoid.Health, -math.huge
  end
  local health = snap.humanoid.Health
  if lastHealth and health < lastHealth then hurtAt = snap.now end
  lastHealth = health
  if not current then return end
  for char, time in pairs(swings) do
    if not char.Parent or snap.now - time > tuning.threatWindow then swings[char] = nil end
  end
  for char, entry in pairs(threats) do
    if not char.Parent or snap.now - entry.time > tuning.threatWindow then threats[char] = nil end
  end
  for _, other in ipairs(players:GetPlayers()) do
    local threat = candidate(other, snap)
    local swing = threat and swings[threat.character]
    if not threat or not swing or snap.now - swing > 0.5 or not closeVisible(snap, threat) then continue end
    local tool = threat.character:FindFirstChildOfClass("Tool")
    local stats = native.stats(tool)
    if stats.type ~= "sword" and stats.type ~= "axe" and stats.type ~= "mace" then continue end
    local incoming = snap.root.Position - threat.root.Position
    local horizontal = Vector3.new(incoming.X, 0, incoming.Z)
    local facing = threat.root.CFrame.LookVector
    local forward = Vector3.new(facing.X, 0, facing.Z)
    if horizontal.Magnitude < 0.01 or forward.Magnitude < 0.01 then continue end
    if incoming.Magnitude > stats.reach + 1.6 or horizontal.Unit:Dot(forward.Unit) < 0.35 then continue end
    if not native.incomingHit(snap, threat) then continue end
    -- Proximity alone is not evidence of an attacker. Require a recent swing facing us.
    threats[threat.character] = { time = swing, hurt = math.abs(hurtAt - swing) <= 0.5 }
  end
end
function Target.manual(snap)
  if native.stats(snap.tool).type ~= "sword" then return end
  local chosen, best = nil, tuning.acquireAngle
  for _, other in ipairs(players:GetPlayers()) do
    local target = candidate(other, snap)
    if not target or not native.canHit(snap, target) then continue end
    local point, visible = snap.camera:WorldToViewportPoint(target.root.Position)
    if not visible or point.Z <= 0 then continue end
    local delta = target.root.Position - snap.camera.CFrame.Position
    if delta.Magnitude < 0.01 then continue end
    local angle = math.deg(math.acos(math.clamp(delta.Unit:Dot(snap.camera.CFrame.LookVector), -1, 1)))
    if angle < best then chosen, best = target, angle end
  end
  if not chosen then return end
  clicks = pending == chosen.character and snap.now - lastClick <= tuning.clickWindow and clicks + 1 or 1
  pending, lastClick = chosen.character, snap.now
  if clicks >= tuning.clicksToStart then current, contact, switchedAt = chosen, snap.now, snap.now end
end
function Target.get(snap)
  if not current then return nil end
  local fresh = candidate(current.player, snap)
  if not fresh or fresh.character ~= current.character then Target.reset() return nil end
  local currentClose = closeVisible(snap, fresh)
  local currentThreat = threats[fresh.character]
  local best, bestScore
  for _, other in ipairs(players:GetPlayers()) do
    local challenger = candidate(other, snap)
    local entry = challenger and threats[challenger.character]
    if not challenger or challenger.character == fresh.character or not entry
      or snap.now - entry.time > tuning.threatWindow or not closeVisible(snap, challenger) then continue end
    local newer = not currentThreat or entry.time > currentThreat.time + 0.18
    local hurtPriority = entry.hurt and (not currentThreat or not currentThreat.hurt)
    if currentClose and not newer and not hurtPriority then continue end
    local score = entry.time + (entry.hurt and 0.4 or 0) - (challenger.root.Position - snap.root.Position).Magnitude * 0.01
    if bestScore == nil or score > bestScore then best, bestScore = challenger, score end
  end
  if best and (not currentClose or snap.now - switchedAt >= 0.35) then
    current, contact, switchedAt = best, snap.now, snap.now
    pending, clicks = nil, 0
    return current
  end
  if snap.now - contact > tuning.targetMemory then Target.reset() return nil end
  current = fresh
  return current
end
function Target.touch(now) contact = now end
Target.__contract = {
  provides = { "setup", "reset", "manual", "get", "touch", "noteSwing", "observe" },
  requires = { Native = "mcpnative", Options = "mcpoptions" },
  requiresMethods = { Native = { "stats", "canHit", "visible", "incomingHit" } },
  requiresData = { Options = { "tuning" } },
}
return Target
