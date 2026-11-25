-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players
local escapes
local heldCharacter, heldUntil = nil, 0
local hitSerial, hitAt, hitTarget, attempt = 0, -math.huge, nil, nil
local current, pending, clicks, lastClick, contact = nil, nil, 0, -math.huge, -math.huge
local swings, threats = {}, {}
local watchedCharacter, lastHealth, hurtAt, switchedAt = nil, nil, -math.huge, -math.huge
function Target.setup(deps)
  native, tuning, players = deps.Native, deps.Options.tuning, game:GetService("Players")
  return true
end
function Target.reset()
  escapes = nil
  heldCharacter, heldUntil = nil, 0
  hitAt, hitTarget, attempt = -math.huge, nil, nil
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
  if (root.Position - snap.root.Position).Magnitude > ((heldCharacter == char and snap.now < heldUntil) and math.huge or (char == (current and current.character) and 64 * 3.2 or tuning.maxRange)) then return nil end
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
function Target.noteAttack(snap, chosen)
  attempt = { character = chosen.character, human = chosen.humanoid, health = chosen.humanoid.Health, time = snap.now }
end
function Target.confirmHit(now)
  if not attempt or now - attempt.time > 0.7 then return end
  hitSerial, hitAt, hitTarget = hitSerial + 1, now, attempt.character
  if current and current.character == hitTarget then contact = now end
  attempt = nil
end
function Target.hitToken() return hitSerial, hitAt, hitTarget end
local function escaped(snap)
  if not current or not current.root.Parent then return false end
  local position = current.root.Position
  local epoch = current.character:GetAttribute("PearlTeleportAt")
  if not escapes or escapes.character ~= current.character then
    escapes = { character = current.character, position = position, at = snap.now, epoch = epoch, count = 0 }
    return false
  end
  if epoch ~= nil and epoch ~= escapes.epoch then escapes.markAt = snap.now end
  local moved = (position - escapes.position).Magnitude
  local marked = escapes.markAt and snap.now - escapes.markAt <= 0.35
  local teleported = moved > (marked and 4 or math.max(16, (snap.now - escapes.at) * 60))
  local before = (escapes.position - snap.root.Position).Magnitude
  local after = (position - snap.root.Position).Magnitude
  local sword = native.findSword(snap)
  local reach = sword and native.stats(sword).reach or 9.6
  if #players:GetPlayers() <= 4 then escapes.count = 0
  elseif teleported and after > reach and after > before + 3.2 then
    escapes.count += 1
    escapes.markAt = nil
  end
  escapes.position, escapes.at, escapes.epoch = position, snap.now, epoch
  return escapes.count > 2
end
function Target.observe(snap)
  if escaped(snap) then
    threats[current.character], swings[current.character] = nil, nil
    Target.abandon(snap)
    return
  end
  if attempt then
    if not attempt.character.Parent or snap.now - attempt.time > 0.6 then
      attempt = nil
    elseif attempt.human.Health < attempt.health then
      hitSerial, hitAt, hitTarget = hitSerial + 1, snap.now, attempt.character
      if current and current.character == hitTarget then contact = snap.now end
      attempt = nil
    end
  end
  if watchedCharacter ~= snap.character then
    swings, threats = {}, {}
    watchedCharacter, lastHealth, hurtAt = snap.character, snap.humanoid.Health, -math.huge
  end
  local health = snap.humanoid.Health
  if lastHealth and health < lastHealth then hurtAt = snap.now end
  lastHealth = health
  for char, time in pairs(swings) do
    if not char.Parent or snap.now - time > tuning.threatWindow then swings[char] = nil end
  end
  for char, entry in pairs(threats) do
    if not char.Parent or snap.now - entry.time > tuning.threatWindow then threats[char] = nil end
  end
  for _, other in ipairs(players:GetPlayers()) do
    local threat = candidate(other, snap)
    local swing = threat and swings[threat.character]
    if not threat or not swing or snap.now - swing > 0.5 or (threat.root.Position - snap.root.Position).Magnitude > 16 or not native.visible(snap, threat.root.Position, threat.character) then continue end
    local tool = threat.character:FindFirstChildOfClass("Tool")
    local stats = native.stats(tool)
    if stats.type ~= "sword" and stats.type ~= "axe" and stats.type ~= "mace" then continue end
    local incoming = snap.root.Position - threat.root.Position
    local horizontal = Vector3.new(incoming.X, 0, incoming.Z)
    local facing = threat.root.CFrame.LookVector
    local forward = Vector3.new(facing.X, 0, facing.Z)
    if horizontal.Magnitude < 0.01 or forward.Magnitude < 0.01 then continue end
    if incoming.Magnitude > stats.reach + 1.6 or horizontal.Unit:Dot(forward.Unit) < 0.35 then continue end
    if not native.incomingHit(snap, threat) and math.abs(hurtAt - swing) > 0.4 then continue end
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
  Target.noteAttack(snap, chosen)
  if clicks >= tuning.clicksToStart then
    current, contact, switchedAt = chosen, snap.now, snap.now
    heldCharacter, heldUntil = chosen.character, math.huge
  end
end
function Target.nearThreat(snap, excluded)
  local best, score
  for _, other in ipairs(players:GetPlayers()) do
    local challenger = candidate(other, snap)
    local entry = challenger and threats[challenger.character]
    if challenger and challenger.character ~= excluded and not native.aerialMace(snap, challenger) and entry and snap.now - entry.time <= tuning.threatWindow
      and (challenger.root.Position - snap.root.Position).Magnitude <= 16
      and native.visible(snap, challenger.root.Position, challenger.character) then
      local value = entry.time + (entry.hurt and 0.4 or 0) - (challenger.root.Position - snap.root.Position).Magnitude * 0.02
      if score == nil or value > score then best, score = challenger, value end
    end
  end
  return best
end
function Target.finishPriority(snap, chosen)
  if chosen then
    local sword = native.findSword(snap)
    local focus = (sword and native.stats(sword).reach or 9.6) * 3
    local privateDuel = #players:GetPlayers() <= 4
    if not privateDuel and (chosen.root.Position - snap.root.Position).Magnitude > focus then return false end
  end
  return chosen ~= nil and chosen.humanoid.Health > 0
    and chosen.humanoid.Health / math.max(1, chosen.humanoid.MaxHealth) <= 0.25
end
function Target.abandon(snap)
  escapes = nil
  local nearby = Target.nearThreat(snap)
  heldCharacter, heldUntil, pending, clicks, attempt = nil, 0, nil, 0, nil
  if nearby then
    current, contact, switchedAt = nearby, snap.now, snap.now
  else
    Target.reset()
  end
end
function Target.get(snap)
  if not current then return nil end
  local fresh = candidate(current.player, snap)
  if fresh and fresh.character ~= current.character then fresh = nil end
  local aerialMace = fresh and native.aerialMace(snap, fresh)
  local currentClose = fresh and not aerialMace and closeVisible(snap, fresh)
  local immediate = Target.nearThreat(snap, fresh and not currentClose and fresh.character or nil)
  if immediate and (not fresh or (not currentClose and immediate.character ~= fresh.character)) then
    if fresh then threats[fresh.character], swings[fresh.character] = nil, nil end
    escapes, attempt = nil, nil
    current, contact, switchedAt = immediate, snap.now, snap.now
    heldCharacter, heldUntil, pending, clicks = nil, 0, nil, 0
    return current
  end
  if not fresh then Target.reset() return nil end
  if aerialMace then return nil end
  if Target.finishPriority(snap, fresh) then current = fresh return current end
  local currentThreat = threats[fresh.character]
  local best, bestScore
  for _, other in ipairs(players:GetPlayers()) do
    local challenger = candidate(other, snap)
    local entry = challenger and threats[challenger.character]
    if not challenger or native.aerialMace(snap, challenger) or challenger.character == fresh.character or not entry
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
  local sword = native.findSword(snap)
  local focusRange = (sword and native.stats(sword).reach or 9.6) * 6
  local nearby = (fresh.root.Position - snap.root.Position).Magnitude <= focusRange
  if not nearby and snap.now - contact > tuning.targetMemory and not (heldCharacter == fresh.character and snap.now < heldUntil) then Target.reset() return nil end
  current = fresh
  return current
end
function Target.locked() return current end
function Target.hold(char, untilTime)
  if current and current.character == char then
    heldCharacter, heldUntil = char, math.max(heldCharacter == char and heldUntil or 0, untilTime)
  end
end
function Target.release(char)
  if heldCharacter == char then heldCharacter, heldUntil = nil, 0 end
end
function Target.touch(now) contact = now end
Target.__contract = {
  provides = { "setup", "reset", "manual", "get", "touch", "noteSwing", "observe", "noteAttack", "hitToken", "confirmHit", "locked", "hold", "nearThreat", "release", "finishPriority", "abandon" },
  requires = { Native = "mcpnative", Options = "mcpoptions" },
  requiresMethods = { Native = { "aerialMace", "stats", "findSword", "canHit", "visible", "incomingHit" } },
  requiresData = { Options = { "tuning" } },
}
return Target
