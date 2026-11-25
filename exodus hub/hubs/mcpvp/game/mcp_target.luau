-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, players
local current, character, localHealth
local records, nearby = {}, {}
local pending, memory = nil, 3
local lastAttempt
local crystalAttempt
function Target.setup(deps)
  native, players = deps.Native, game:GetService("Players")
  return true
end
function Target.reset()
  current, character, localHealth, pending = nil, nil, nil, nil
  records, nearby = {}, {}
  lastAttempt, crystalAttempt = nil, nil
end
local function record(char)
  local entry = records[char]
  if not entry then
    entry = {
      dealt = -math.huge,
      received = -math.huge,
      intent = -math.huge,
      swing = -math.huge,
      duelUntil = -math.huge,
      hits = 0,
      manual = -math.huge,
      clicks = 0,
      authorized = -math.huge,
      contact = -math.huge,
      crystalDamage = -math.huge,
    }
    records[char] = entry
  end
  return entry
end
local function refreshDuel(entry, now)
  if entry.duelUntil > now or (now - entry.dealt < memory and now - entry.received < memory) then
    entry.duelUntil = now + memory
  end
end
local function angle(snap, point)
  local view = snap.camera.CFrame
  local delta = point - view.Position
  return delta.Magnitude < 0.01 and 0 or math.deg(math.acos(math.clamp(view.LookVector:Dot(delta.Unit), -1, 1)))
end
local function candidates(snap, cfg)
  local result = {}
  for _, other in ipairs(players:GetPlayers()) do
    if
      other == snap.player
      or (cfg("MCTeamCheck") and not other.Neutral and not snap.player.Neutral and other.Team == snap.player.Team)
      or other:GetAttribute("ArenaProtected") == true
      or other:GetAttribute("InArena") == false
    then
      continue
    end
    local char = other.Character
    local human = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not human or human.Health <= 0 or not root then
      continue
    end
    local distance = (root.Position - snap.root.Position).Magnitude
    local entry = records[char]
    local pursuing = entry and snap.now - math.max(entry.dealt, entry.received, entry.intent) < cfg("MCComboLifetime")
    if distance > (pursuing and math.max(cfg("MCTargetRange"), cfg("MCSwordPearlMax")) or cfg("MCTargetRange")) * 3.2 then
      continue
    end
    result[#result + 1] = {
      player = other,
      character = char,
      humanoid = human,
      root = root,
      distance = distance,
      angle = angle(snap, root.Position),
      visible = native.visible(snap.eye, root.Position, char),
    }
  end
  table.sort(result, function(a, b) return a.distance < b.distance end)
  return result
end
function Target.canHit(snap, target, reach, direction)
  direction = direction or snap.camera.CFrame.LookVector
  local geometry = native.data().geometry
  if geometry and type(geometry.Hit) == "function" then
    local distance = geometry.Hit(snap.eye, direction, target.root.Position, target.character:GetAttribute("Sneaking"), reach)
    return distance ~= nil and native.visible(snap.eye, snap.eye + direction * distance, target.character)
  end
  local delta = target.root.Position - snap.eye
  local forward = delta:Dot(direction)
  return forward > 0 and forward <= reach and (delta - direction * forward).Magnitude < 0.7 and native.visible(snap.eye, target.root.Position, target.character)
end
function Target.noteAttack(snap, chosen, manual)
  if not snap or not snap.equipped or native.stats(snap.equipped).type ~= "sword" then
    return
  end
  local reach = native.stats(snap.equipped).reach
  if not chosen then
    for _, candidate in ipairs(nearby) do
      if Target.canHit(snap, candidate, reach) then
        chosen = candidate
        break
      end
    end
  end
  if not chosen or chosen.distance > reach + 2 then
    return
  end
  local entry = record(chosen.character)
  lastAttempt = { character = chosen.character, at = snap.now, health = chosen.humanoid.Health }
  if manual then
    entry.clicks = snap.now - entry.manual < 1 and entry.clicks + 1 or 1
    entry.manual = snap.now
  end
  if not pending or pending.character ~= chosen.character or snap.now - pending.at > 0.7 then
    pending = { character = chosen.character, at = snap.now, health = chosen.humanoid.Health }
  end
end
function Target.confirmHit(now)
  -- Feedback.HitConfirm is local to the attacker but has no victim ID. Correlate only with the pending geometric sword candidate.
  if not pending or now - pending.at > 0.7 then
    return
  end
  local entry = record(pending.character)
  entry.hits = now - entry.dealt <= memory and entry.hits + 1 or 1
  entry.dealt = now
  if (entry.clicks >= 2 and now - entry.manual < 1) or entry.authorized > now then
    entry.authorized = now + memory
  end
  if entry.hits >= 2 then
    entry.duelUntil = now + memory
  end
  refreshDuel(entry, now)
  pending = nil
end
function Target.noteSwing(char, now)
  if char and char ~= character then
    record(char).swing = now
  end
end
function Target.noteVictim(char, now)
  -- ConfirmedMeleeFlash supplies the victim; an incoming hit is attributed only if a unique nearby recent swinger exists.
  if char == character then
    Target.receive(now)
  elseif lastAttempt and lastAttempt.character == char and now - lastAttempt.at <= 0.7 then
    record(char).contact = now
    lastAttempt = nil
    if pending and pending.character == char then
      Target.confirmHit(now)
    end
  end
end
function Target.receive(now)
  local attacker
  for _, candidate in ipairs(nearby) do
    local entry = record(candidate.character)
    local tool = candidate.character:FindFirstChildOfClass("Tool")
    local stats = native.stats(tool)
    local delta = candidate.root.Position
      - (character and character:FindFirstChild("HumanoidRootPart") and character.HumanoidRootPart.Position or candidate.root.Position)
    if stats.type == "sword" and now - entry.swing < 0.55 and candidate.visible and delta.Magnitude <= stats.reach + 2 then
      if attacker then
        return
      end
      attacker = candidate
    end
  end
  if attacker then
    local entry = record(attacker.character)
    entry.received = now
    if entry.crystalDamage > -math.huge then
      entry.authorized = now + memory
      entry.contact = now
      current = attacker.character
    end
    refreshDuel(entry, now)
  end
end
function Target.noteCrystal(snap, crystal, point)
  if not snap or not crystal or not point then
    return
  end
  local victims = {}
  for _, candidate in ipairs(nearby) do
    if candidate.humanoid.Health > 0 and (candidate.root.Position - point).Magnitude <= 38.4 then
      victims[#victims + 1] = { character = candidate.character, humanoid = candidate.humanoid, health = candidate.humanoid.Health }
    end
  end
  crystalAttempt = { crystal = crystal, point = point, at = snap.now, victims = victims }
end
function Target.hold(char, now)
  local entry = record(char)
  entry.intent = now
  current = char
end
function Target.active(now)
  for char, entry in pairs(records) do
    local human = char.Parent and char:FindFirstChildOfClass("Humanoid")
    if human and human.Health > 0 and entry.authorized > now then
      return true
    end
  end
  return false
end
function Target.nearby() return nearby end
function Target.combatNearby(now)
  if Target.active(now) then
    return nearby
  end
  local result = {}
  for _, candidate in ipairs(nearby) do
    if candidate.manualCombo then
      result[#result + 1] = candidate
    end
  end
  return result
end
function Target.resume(char, now, duration)
  local human = char.Parent and char:FindFirstChildOfClass("Humanoid")
  if not human or human.Health <= 0 then
    return
  end
  record(char).authorized = now + duration
  current = char
end
function Target.lastContact(char) return record(char).contact end
function Target.lastHit(char) return record(char).dealt end
function Target.update(snap, cfg)
  if character ~= snap.character then
    Target.reset()
    character = snap.character
  end
  memory = cfg("MCTargetMemory")
  nearby = candidates(snap, cfg)
  if crystalAttempt then
    local attempt = crystalAttempt
    if snap.now - attempt.at > 1.2 then
      crystalAttempt = nil
    elseif not attempt.crystal.Parent then
      for index = #attempt.victims, 1, -1 do
        local victim = attempt.victims[index]
        if victim.character.Parent and victim.humanoid.Health < victim.health then
          local entry = record(victim.character)
          entry.crystalDamage = snap.now
          if snap.now - entry.received <= memory then
            entry.authorized, entry.contact = snap.now + memory, snap.now
            current = victim.character
          end
          table.remove(attempt.victims, index)
        end
      end
    end
  end
  if localHealth and snap.humanoid.Health < localHealth then
    Target.receive(snap.now)
  end
  localHealth = snap.humanoid.Health
  if lastAttempt then
    for _, candidate in ipairs(nearby) do
      if candidate.character == lastAttempt.character and candidate.humanoid.Health < lastAttempt.health and snap.now - lastAttempt.at <= 0.7 then
        record(candidate.character).contact = snap.now
        lastAttempt = nil
        break
      end
    end
    if lastAttempt and snap.now - lastAttempt.at > 0.7 then
      lastAttempt = nil
    end
  end
  if pending then
    for _, candidate in ipairs(nearby) do
      if candidate.character == pending.character and candidate.humanoid.Health < pending.health and snap.now - pending.at < 0.7 then
        Target.confirmHit(snap.now)
        break
      end
    end
    if pending and snap.now - pending.at > 0.7 then
      pending = nil
    end
  end
  local selected, score
  for _, candidate in ipairs(nearby) do
    local entry = record(candidate.character)
    local recent = math.max(entry.dealt, entry.received, entry.intent)
    candidate.lastHit, candidate.lastDamage = entry.dealt, entry.received
    candidate.duel = entry.authorized > snap.now
    candidate.engaged = entry.authorized > snap.now
    local retained = current == candidate.character and candidate.engaged
    -- FOV gates idle acquisition only. Actual combat and combo intent remain valid behind the camera or briefly behind a block.
    if not candidate.engaged and (candidate.angle > cfg("MCAcquireFov") or not candidate.visible) then
      continue
    end
    local value = candidate.distance / 50 + candidate.angle / 180
    if entry.crystalDamage > -math.huge and snap.now - entry.received <= memory and candidate.duel then
      value -= 8
    end
    if candidate.duel then
      value -= 3
    end
    if retained then
      value -= 1.5
    end
    if not score or value < score then
      selected, score = candidate, value
    end
  end
  current = selected and selected.character or nil
  for char in pairs(records) do
    if not char.Parent then
      records[char] = nil
    end
  end
  return selected
end
function Target.point(snap, target, tolerance)
  local delta = target.root.Position - snap.camera.CFrame.Position
  local closest = snap.camera.CFrame.Position + snap.camera.CFrame.LookVector * math.max(0, delta:Dot(snap.camera.CFrame.LookVector))
  local radius = math.max(0.2, 0.9 - tolerance * 3.2)
  return target.root.Position
    + Vector3.new(
      math.clamp(closest.X - target.root.Position.X, -radius, radius),
      math.clamp(closest.Y - target.root.Position.Y, -1.2, 1.6),
      math.clamp(closest.Z - target.root.Position.Z, -radius, radius)
    )
end
Target.__contract = {
  requires = { Native = "mcpnative" },
  provides = {
    "setup",
    "reset",
    "update",
    "point",
    "canHit",
    "noteAttack",
    "noteCrystal",
    "confirmHit",
    "noteSwing",
    "noteVictim",
    "receive",
    "hold",
    "nearby",
    "lastHit",
    "lastContact",
    "active",
    "combatNearby",
    "resume",
  },
}
return Target
