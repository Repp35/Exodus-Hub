-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players
local current, pending, attempt, owner
local clicks, clickAt, contact, switchAt = 0, -math.huge, 0, 0
local serial, hitAt, hitCharacter = 0, -math.huge, nil
local hurtAt, health = -math.huge, nil
local swings, threats, candidates = {}, {}, {}
local holdUntil = 0
function Target.setup(deps)
  native, tuning, players = deps.Native, deps.Options.tuning, game:GetService("Players")
  return true
end
function Target.reset()
  current, pending, attempt, owner = nil, nil, nil, nil
  clicks, clickAt, contact, switchAt, holdUntil = 0, -math.huge, 0, 0, 0
  hitAt, hitCharacter, hurtAt, health = -math.huge, nil, -math.huge, nil
  swings, threats, candidates = {}, {}, {}
end
local function candidate(player, snap)
  if player == snap.player or player.Parent ~= players or player:GetAttribute("ArenaProtected") == true or player:GetAttribute("InArena") == false then
    return nil
  end
  local char = player.Character
  local root = char and char:FindFirstChild("HumanoidRootPart")
  local human = char and char:FindFirstChildOfClass("Humanoid")
  if not root or not human or human.Health <= 0 or char:FindFirstChildOfClass("ForceField") then
    return nil
  end
  local distance = (root.Position - snap.root.Position).Magnitude
  if distance > tuning.maxRange and (not current or current.character ~= char or distance > tuning.chaseRange) then
    return nil
  end
  return { player = player, character = char, root = root, humanoid = human, distance = distance }
end
function Target.noteSwing(source)
  if typeof(source) ~= "Instance" then
    return
  end
  if source:IsA("Player") then
    source = source.Character
  end
  if source and source:IsA("Model") and players:GetPlayerFromCharacter(source) then
    swings[source] = os.clock()
  end
end
function Target.noteAttack(snap, chosen) attempt = { character = chosen.character, time = snap.now } end
function Target.confirmHit(now)
  if not attempt or now - attempt.time > 0.7 then
    return
  end
  serial, hitAt, hitCharacter = serial + 1, now, attempt.character
  if current and current.character == hitCharacter then
    contact = now
  end
  attempt = nil
end
function Target.hitToken() return serial, hitAt, hitCharacter end
function Target.observe(snap)
  if owner ~= snap.character then
    Target.reset()
    owner, health = snap.character, snap.humanoid.Health
  end
  if health and snap.humanoid.Health < health then
    hurtAt = snap.now
  end
  health = snap.humanoid.Health
  if attempt and snap.now - attempt.time > 0.7 then
    attempt = nil
  end
  candidates = {}
  for char, at in pairs(swings) do
    if not char.Parent or snap.now - at > tuning.threatWindow then
      swings[char], threats[char] = nil, nil
    end
  end
  for _, player in ipairs(players:GetPlayers()) do
    local value = candidate(player, snap)
    if not value then
      continue
    end
    candidates[#candidates + 1] = value
    local swing = swings[value.character]
    if swing and snap.now - swing < 0.5 and value.distance < 16 and native.incomingHit(snap, value) then
      threats[value.character] = { at = swing, hurt = math.abs(hurtAt - swing) < 0.5 }
    end
  end
end
function Target.manual(snap)
  if native.stats(snap.tool).type ~= "sword" then
    return
  end
  local best, angle = nil, math.cos(math.rad(tuning.acquireAngle))
  for _, player in ipairs(players:GetPlayers()) do
    local value = candidate(player, snap)
    if not value or not native.canHit(snap, value) then
      continue
    end
    local delta = value.root.Position - snap.camera.CFrame.Position
    if delta.Magnitude < 0.001 then
      continue
    end
    local dot = delta.Unit:Dot(snap.camera.CFrame.LookVector)
    if dot > angle then
      best, angle = value, dot
    end
  end
  if not best then
    return
  end
  clicks = pending == best.character and snap.now - clickAt <= tuning.clickWindow and clicks + 1 or 1
  pending, clickAt = best.character, snap.now
  Target.noteAttack(snap, best)
  if clicks >= tuning.clicksToStart then
    current, contact, switchAt, holdUntil = best, snap.now, snap.now, 0
  end
end
function Target.get(snap)
  if not current then
    return nil
  end
  local fresh = candidate(current.player, snap)
  if fresh and fresh.character ~= current.character then
    fresh = nil
  end
  local close = fresh and native.canHit(snap, fresh) and not native.aerialMace(snap, fresh)
  local best, score
  if not close or not Target.finishPriority(snap, fresh) then
    for _, value in ipairs(candidates) do
      local threat = threats[value.character]
      if not threat or snap.now - threat.at > tuning.threatWindow or native.aerialMace(snap, value) or not native.canHit(snap, value) then
        continue
      end
      local rank = threat.at + (threat.hurt and 0.4 or 0) - value.distance * 0.02
      if fresh and value.character == fresh.character then
        rank += 0.35
      end
      if not score or rank > score then
        best, score = value, rank
      end
    end
  end
  if best and (not close or snap.now - switchAt >= 0.35) and (not fresh or best.character ~= fresh.character) then
    fresh, contact, switchAt, holdUntil = best, snap.now, snap.now, 0
  end
  if not fresh then
    Target.reset()
    return nil
  end
  local distance = fresh.distance
  if distance <= (native.stats(native.findSword(snap)).reach or 9.6) * 3 then
    contact = snap.now
  end
  if snap.now > holdUntil and snap.now - contact > tuning.targetMemory then
    Target.reset()
    return nil
  end
  current = fresh
  if native.aerialMace(snap, fresh) then
    return nil
  end
  return fresh
end
function Target.finishPriority(_snap, chosen)
  return chosen ~= nil and chosen.humanoid.Health > 0 and chosen.humanoid.Health / math.max(1, chosen.humanoid.MaxHealth) <= 0.25
end
function Target.hold(char, untilTime)
  if current and current.character == char then
    holdUntil = math.min(os.clock() + 7, untilTime)
  end
end
function Target.release(char)
  if current and current.character == char then
    holdUntil = 0
  end
end
function Target.locked() return current end
function Target.quiet(snap, duration) return snap.now - math.max(clickAt, hurtAt, hitAt) >= (duration or 4) end
Target.__contract = {
  provides = {
    "setup",
    "reset",
    "observe",
    "manual",
    "get",
    "noteSwing",
    "noteAttack",
    "confirmHit",
    "hitToken",
    "finishPriority",
    "hold",
    "release",
    "locked",
    "quiet",
  },
  requires = { Native = "mcpnative", Options = "mcpoptions" },
  requiresMethods = { Native = { "stats", "findSword", "canHit", "incomingHit", "aerialMace" } },
  requiresData = { Options = { "tuning" } },
}
return Target
