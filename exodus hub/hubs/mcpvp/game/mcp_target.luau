-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players, units
local owner, health, session, attempt
local serial = 0
local swings = {}
local SWITCH_WINDOW = 0.35
local clickAt, hurtAt, hitAt = -math.huge, -math.huge, -math.huge
function Target.setup(deps)
  native, tuning, players, units = deps.Native, deps.Options.tuning, game:GetService("Players"), deps.Units
  return true
end
local function finish()
  session, attempt, swings = nil, nil, {}
  serial += 1
end
function Target.reset()
  finish()
  owner, health = nil, nil
  clickAt, hurtAt, hitAt = -math.huge, -math.huge, -math.huge
end
local function candidate(player, snap, rangeBlocks)
  if
    not player
    or player == snap.player
    or player.Parent ~= players
    or player:GetAttribute("ArenaProtected") == true
    or player:GetAttribute("InArena") == false
  then
    return nil
  end
  local char = player.Character
  local root = char and char:FindFirstChild("HumanoidRootPart")
  local human = char and char:FindFirstChildOfClass("Humanoid")
  if not root or not root.Parent or not human or human.Health <= 0 or char:FindFirstChildOfClass("ForceField") then
    return nil
  end
  local distance = units.distance(root.Position, snap.root.Position)
  if distance > rangeBlocks then
    return nil
  end
  return { player = player, character = char, root = root, humanoid = human, distanceBlocks = distance }
end
local function active(snap)
  if not session then
    return nil
  end
  if owner ~= snap.character or snap.now - session.at > tuning.pursuitSeconds then
    finish()
    return nil
  end
  local chosen = candidate(session.player, snap, tuning.pearlRangeBlocks)
  if not chosen or chosen.character ~= session.character then
    finish()
    return nil
  end
  chosen.sessionId = session.id
  return chosen
end
local function select(snap, chosen)
  finish()
  session = { id = serial, player = chosen.player, character = chosen.character, at = snap.now, startedAt = snap.now, switchedAt = snap.now }
  chosen.sessionId = session.id
end
function Target.noteSwing(source)
  if not session or typeof(source) ~= "Instance" then
    return
  end
  if source:IsA("Player") then
    source = source.Character
  end
  if not source or not source:IsA("Model") or source == owner or not players:GetPlayerFromCharacter(source) then
    return
  end
  swings[source] = { at = os.clock(), sessionId = session.id }
end
local function considerSwitch(snap, current)
  if not session or not session.damageAt or snap.now - session.damageAt > SWITCH_WINDOW or snap.now - session.switchedAt < SWITCH_WINDOW then
    return
  end
  local chosen, distance
  local currentClose = native.canHit(snap, current)
  for character, swing in pairs(swings) do
    if swing.sessionId ~= session.id or not character.Parent or snap.now - swing.at > SWITCH_WINDOW then
      swings[character] = nil
      continue
    end
    if character == session.character or swing.at < session.startedAt or math.abs(swing.at - session.damageAt) > SWITCH_WINDOW then
      continue
    end
    local other = candidate(players:GetPlayerFromCharacter(character), snap, tuning.focusRangeBlocks)
    if not other or other.character ~= character or not native.canHit(snap, other) or not native.incomingHit(snap, other) then
      continue
    end
    if currentClose and other.distanceBlocks + 0.25 >= current.distanceBlocks then
      continue
    end
    if not distance or other.distanceBlocks < distance then
      chosen, distance = other, other.distanceBlocks
    end
  end
  if chosen then
    select(snap, chosen)
  end
end
function Target.observe(snap)
  if owner ~= snap.character then
    Target.reset()
    owner = snap.character
  end
  -- Validate/end the old fight BEFORE considering any incoming swing.
  local current = active(snap)
  if health and snap.humanoid.Health < health then
    hurtAt = snap.now
    if session then
      session.damageAt = snap.now
    end
  end
  health = snap.humanoid.Health
  for character, swing in pairs(swings) do
    if not session or swing.sessionId ~= session.id or not character.Parent or snap.now - swing.at > SWITCH_WINDOW then
      swings[character] = nil
    end
  end
  if current then
    considerSwitch(snap, current)
  end
  if attempt and snap.now - attempt.at > 0.7 then
    attempt = nil
  end
end
function Target.isCurrent(snap, chosen)
  local current = active(snap)
  return current ~= nil and chosen ~= nil and chosen.sessionId == current.sessionId and chosen.character == current.character
end
function Target.follow(snap, chosen)
  -- Automatic actions may extend this fight, but cannot start or replace one.
  if not Target.isCurrent(snap, chosen) then
    return false
  end
  session.at = snap.now
  return true
end
function Target.noteAttack(snap, chosen)
  if not Target.follow(snap, chosen) then
    return false
  end
  attempt = { at = snap.now, sessionId = session.id }
  return true
end
function Target.confirmHit(now)
  if attempt and session and attempt.sessionId == session.id and now - attempt.at <= 0.7 then
    hitAt, session.at = now, now
  end
  attempt = nil
end
function Target.pick(snap, direction)
  direction = direction or native.aimDirection(snap)
  local best, distance
  for _, player in ipairs(players:GetPlayers()) do
    local chosen = candidate(player, snap, tuning.focusRangeBlocks)
    local hit = chosen and native.hitDistanceBlocks(snap, chosen, snap.tool, direction)
    if hit and (not distance or hit < distance) then
      best, distance = chosen, hit
    end
  end
  return best
end
function Target.manual(snap, direction)
  Target.observe(snap)
  if native.blocked(snap) then
    return nil
  end
  clickAt = snap.now
  local chosen = Target.pick(snap, direction)
  if not chosen then
    return nil
  end
  if not session or session.character ~= chosen.character then
    select(snap, chosen)
  end
  chosen.sessionId = session.id
  Target.noteAttack(snap, chosen)
  return chosen
end
function Target.get(snap)
  local chosen = active(snap)
  if not chosen or chosen.distanceBlocks > tuning.focusRangeBlocks then
    return nil
  end
  if not native.visible(snap, chosen.root.Position, chosen.character) then
    return nil
  end
  return chosen
end
function Target.getPearl(snap) return active(snap) end
function Target.quiet(snap, duration) return snap.now - math.max(clickAt, hurtAt, hitAt) >= (duration or 4) end
Target.__contract = {
  provides = { "setup", "reset", "observe", "noteSwing", "manual", "pick", "get", "noteAttack", "confirmHit", "follow", "getPearl", "isCurrent", "quiet" },
  requires = { Native = "mcpnative", Options = "mcpoptions", Units = "mcpunits" },
  requiresMethods = { Units = { "distance" }, Native = { "blocked", "aimDirection", "hitDistanceBlocks", "visible", "canHit", "incomingHit" } },
  requiresData = { Options = { "tuning" } },
}
return Target
