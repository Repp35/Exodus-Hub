-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players
local current, pending, clicks, lastClick, contact, holdUntil = nil, nil, 0, -math.huge, -math.huge, 0
local owner, health, hurtAt, scanAt, attempt = nil, nil, -math.huge, 0, nil
local swings, threats = {}, {}
function Target.setup(deps)
  native, tuning, players = deps.Native, deps.Options.tuning, game:GetService("Players")
  return true
end
function Target.reset()
  current, pending, clicks, lastClick, contact, holdUntil = nil, nil, 0, -math.huge, -math.huge, 0
  owner, health, hurtAt, scanAt, attempt = nil, nil, -math.huge, 0, nil
  swings, threats = {}, {}
end
local function candidate(player, snap)
  if player == snap.player or player.Parent ~= players or player:GetAttribute("ArenaProtected") == true or player:GetAttribute("InArena") == false then
    return nil
  end
  local character = player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if
    not humanoid
    or not root
    or humanoid.Health <= 0
    or character:GetAttribute("ArenaProtected") == true
    or character:GetAttribute("DuelCombatActive") == false
    or player:GetAttribute("DuelCombatActive") == false
    or character:FindFirstChildOfClass("ForceField")
  then
    return nil
  end
  if (root.Position - snap.root.Position).Magnitude > tuning.maxRange then
    return nil
  end
  return { player = player, character = character, root = root, humanoid = humanoid }
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
  if attempt and now - attempt.time <= 0.7 and current and current.character == attempt.character then
    contact = now
  end
  attempt = nil
end
function Target.observe(snap)
  if owner ~= snap.character then
    Target.reset()
    owner, health = snap.character, snap.humanoid.Health
  end
  if snap.humanoid.Health < health then
    hurtAt = snap.now
  end
  health = snap.humanoid.Health
  if attempt and snap.now - attempt.time > 0.7 then
    attempt = nil
  end
  if snap.now < scanAt then
    return
  end
  scanAt = snap.now + 0.1
  for character, time in pairs(swings) do
    if not character.Parent or snap.now - time > 0.5 then
      swings[character] = nil
    elseif character ~= snap.character then
      local player = players:GetPlayerFromCharacter(character)
      local chosen = player and candidate(player, snap)
      if
        chosen
        and (chosen.root.Position - snap.root.Position).Magnitude <= 16
        and native.incomingHit(snap, chosen)
        and native.visible(snap, chosen.root.Position, chosen.character)
      then
        threats[character] = { player = player, time = time, hurt = math.abs(hurtAt - time) <= 0.4 }
      end
    end
  end
  for character, entry in pairs(threats) do
    if not character.Parent or snap.now - entry.time > tuning.threatWindow then
      threats[character] = nil
    end
  end
end
function Target.manual(snap)
  if native.stats(snap.tool).type ~= "sword" then
    return
  end
  local best, angle = nil, tuning.acquireAngle
  for _, player in ipairs(players:GetPlayers()) do
    local chosen = candidate(player, snap)
    if not chosen or not native.canHit(snap, chosen) then
      continue
    end
    local point, visible = snap.camera:WorldToViewportPoint(chosen.root.Position)
    if not visible or point.Z <= 0 then
      continue
    end
    local delta = chosen.root.Position - snap.camera.CFrame.Position
    if delta.Magnitude < 0.01 then
      continue
    end
    local value = math.deg(math.acos(math.clamp(delta.Unit:Dot(snap.camera.CFrame.LookVector), -1, 1)))
    if value < angle or value == angle and best and player.UserId < best.player.UserId then
      best, angle = chosen, value
    end
  end
  if not best then
    pending, clicks = nil, 0
    return
  end
  clicks = pending == best.character and snap.now - lastClick <= tuning.clickWindow and clicks + 1 or 1
  pending, lastClick = best.character, snap.now
  if clicks >= tuning.clicksToStart then
    current, contact, holdUntil = best, snap.now, snap.now + tuning.targetMemory
  end
  Target.noteAttack(snap, best)
end
function Target.get(snap)
  local fresh = current and candidate(current.player, snap)
  if fresh and fresh.character ~= current.character then
    fresh = nil
  end
  if fresh and not native.aerialMace(snap, fresh) then
    if native.canHit(snap, fresh) then
      contact = snap.now
    end
    if snap.now <= holdUntil or snap.now - contact <= tuning.targetMemory then
      current = fresh
      return current
    end
  end
  current, holdUntil = nil, 0
  local best, bestTime, bestDistance
  for _, entry in pairs(threats) do
    local chosen = candidate(entry.player, snap)
    if not chosen or native.aerialMace(snap, chosen) or not native.canHit(snap, chosen) then
      continue
    end
    local time = entry.time + (entry.hurt and 0.4 or 0)
    local distance = (chosen.root.Position - snap.root.Position).Magnitude
    if
      not best
      or time > bestTime
      or time == bestTime and (distance < bestDistance or distance == bestDistance and chosen.player.UserId < best.player.UserId)
    then
      best, bestTime, bestDistance = chosen, time, distance
    end
  end
  if best then
    current, contact = best, snap.now
  end
  return current
end
function Target.locked() return current end
function Target.hold(character, untilTime)
  if current and current.character == character then
    holdUntil = math.max(holdUntil, math.min(untilTime, os.clock() + 5))
  end
end
Target.__contract = {
  provides = { "setup", "reset", "manual", "get", "locked", "noteSwing", "noteAttack", "confirmHit", "observe", "hold" },
  requires = { Native = "mcpnative", Options = "mcpoptions" },
  requiresMethods = { Native = { "aerialMace", "stats", "canHit", "visible", "incomingHit" } },
  requiresData = { Options = { "tuning" } },
}
return Target
