-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players
local current, attempt, owner, health, engaged
local clickAt, hurtAt, hitAt = -math.huge, -math.huge, -math.huge
function Target.setup(deps)
  native, tuning, players = deps.Native, deps.Options.tuning, game:GetService("Players")
  return true
end
function Target.reset()
  current, attempt, owner, health, engaged = nil, nil, nil, nil, false
  clickAt, hurtAt, hitAt = -math.huge, -math.huge, -math.huge
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
  if distance > tuning.focusRange then
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
  if attempt and snap.now - attempt > 0.7 then
    attempt = nil
  end
end
function Target.noteAttack(snap, _chosen) attempt = snap.now end
function Target.confirmHit(now)
  if not attempt or now - attempt > 0.7 then
    return
  end
  -- A late confirmation must never restore a target that has already fled.
  hitAt, attempt = now, nil
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
  current, engaged = best, true
  Target.noteAttack(snap, best)
  return best
end
function Target.get(snap)
  if not engaged then
    return nil
  end
  local nearest, distance
  for _, player in ipairs(players:GetPlayers()) do
    local value = candidate(player, snap)
    if not value then
      continue
    end
    if not native.visible(snap, value.root.Position, value.character) then
      continue
    end
    if not distance or value.distance < distance then
      nearest, distance = value, value.distance
    end
  end
  current = nearest
  if not current then
    engaged, attempt = false, nil
  end
  return current
end
function Target.quiet(snap, duration) return snap.now - math.max(clickAt, hurtAt, hitAt) >= (duration or 4) end
Target.__contract = {
  provides = { "setup", "reset", "observe", "manual", "get", "noteAttack", "confirmHit", "quiet" },
  requires = { Native = "mcpnative", Options = "mcpoptions" },
  requiresMethods = { Native = { "blocked", "aimDirection", "hitDistance", "visible" } },
  requiresData = { Options = { "tuning" } },
}
return Target
