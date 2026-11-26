-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players
local current, attempt, owner, health
local contact, holdUntil, clickAt, hurtAt, hitAt = 0, 0, -math.huge, -math.huge, -math.huge
function Target.setup(deps)
  native, tuning, players = deps.Native, deps.Options.tuning, game:GetService("Players")
  return true
end
function Target.reset()
  current, attempt, owner, health = nil, nil, nil, nil
  contact, holdUntil, clickAt, hurtAt, hitAt = 0, 0, -math.huge, -math.huge, -math.huge
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
  if distance > tuning.chaseRange then
    return nil
  end
  return { player = player, character = char, root = root, humanoid = human, distance = distance }
end
function Target.observe(snap)
  if owner ~= snap.character then
    Target.reset()
    owner = snap.character
  end
  if health and snap.humanoid.Health < health then
    hurtAt = snap.now
  end
  health = snap.humanoid.Health
  if attempt and snap.now - attempt.time > 0.7 then
    attempt = nil
  end
end
function Target.noteAttack(snap, chosen)
  attempt = { target = chosen, time = snap.now }
  if current and current.character == chosen.character then
    contact = snap.now
  end
end
function Target.confirmHit(now)
  if not attempt or now - attempt.time > 0.7 then
    return
  end
  local chosen = attempt.target
  if chosen.character.Parent and chosen.humanoid.Health > 0 then
    current, contact, hitAt = chosen, now, now
  end
  attempt = nil
end
function Target.manual(snap)
  Target.observe(snap)
  if native.blocked(snap) then
    return nil
  end
  clickAt = snap.now
  local best, distance
  local direction = native.aimDirection(snap)
  -- Match the native attack ray: only a player actually under our strike can start PvP.
  for _, player in ipairs(players:GetPlayers()) do
    local value = candidate(player, snap)
    local hit = value and native.hitDistance(snap, value, snap.tool, direction)
    if hit and (not distance or hit < distance) then
      best, distance = value, hit
    end
  end
  if not best then
    return nil
  end
  current, contact, holdUntil = best, snap.now, 0
  Target.noteAttack(snap, best)
  return best
end
function Target.get(snap)
  if not current then
    return nil
  end
  local fresh = candidate(current.player, snap)
  if not fresh or fresh.character ~= current.character then
    current, attempt, holdUntil = nil, nil, 0
    return nil
  end
  if fresh.distance <= (native.stats(snap.tool).reach or 9.6) * 3 then
    contact = snap.now
  end
  if snap.now > holdUntil and snap.now - contact > tuning.targetMemory then
    current, attempt = nil, nil
    return nil
  end
  current = fresh
  if native.aerialMace(snap, fresh) then
    return nil
  end
  return fresh
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
function Target.quiet(snap, duration) return snap.now - math.max(clickAt, hurtAt, hitAt) >= (duration or 4) end
Target.__contract = {
  provides = { "setup", "reset", "observe", "manual", "get", "noteAttack", "confirmHit", "hold", "release", "quiet" },
  requires = { Native = "mcpnative", Options = "mcpoptions" },
  requiresMethods = { Native = { "stats", "blocked", "aimDirection", "hitDistance", "aerialMace" } },
  requiresData = { Options = { "tuning" } },
}
return Target
