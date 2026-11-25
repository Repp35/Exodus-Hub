-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, players
local current, previousHealth, lastOwnSwing = nil, nil, 0
local engagedAt, hitAt, damagedAt = -math.huge, -math.huge, -math.huge
local localHealth, character
function Target.setup(deps)
  native, players = deps.Native, game:GetService("Players")
  return true
end
local function angle(snap, point)
  local view = snap.targetCFrame or snap.camera.CFrame
  local delta = point - view.Position
  if delta.Magnitude < 0.01 then
    return 0
  end
  return math.deg(math.acos(math.clamp(view.LookVector:Dot(delta.Unit), -1, 1)))
end
function Target.reset()
  current, previousHealth, localHealth, character = nil, nil, nil, nil
  engagedAt, hitAt, damagedAt, lastOwnSwing = -math.huge, -math.huge, -math.huge, 0
end
function Target.update(snap, cfg)
  if character ~= snap.character then
    Target.reset()
    character = snap.character
  end
  if localHealth and snap.humanoid.Health < localHealth then
    damagedAt = snap.now
  end
  localHealth = snap.humanoid.Health
  local swing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or 0
  local candidates = {}
  for _, other in ipairs(players:GetPlayers()) do
    if other == snap.player or (cfg("MCTeamCheck") and not other.Neutral and not snap.player.Neutral and other.Team == snap.player.Team) then
      continue
    end
    if other:GetAttribute("ArenaProtected") == true or other:GetAttribute("InArena") == false then
      continue
    end
    local char = other.Character
    local human = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not human or human.Health <= 0 then
      continue
    end
    local distance = (root.Position - snap.root.Position).Magnitude
    local degrees = angle(snap, root.Position)
    local retained = current and current.player == other and current.character == char
    local cone = retained and cfg("MCKeepFov") or cfg("MCAcquireFov")
    if distance > cfg("MCTargetRange") * 3.2 or degrees > cone then
      continue
    end
    if not native.visible(snap.eye, root.Position, char) then
      continue
    end
    local score = degrees / math.max(1, cone) + distance / (cfg("MCTargetRange") * 3.2) * 0.4
    if retained then
      score -= 0.5
    end
    candidates[#candidates + 1] = { player = other, character = char, humanoid = human, root = root, distance = distance, angle = degrees, score = score }
  end
  table.sort(candidates, function(a, b) return a.score < b.score end)
  local selected = candidates[1]
  if not selected then
    current, previousHealth = nil, nil
    return nil
  end
  if not current or current.character ~= selected.character then
    previousHealth = selected.humanoid.Health
    engagedAt, hitAt = -math.huge, -math.huge
  end
  local manualSwing = swing > lastOwnSwing and snap.equipped and native.stats(snap.equipped).type == "sword"
  if manualSwing and selected.distance <= 11 and selected.angle < 14 then
    engagedAt = snap.now
  end
  -- Health loss plus a recent in-range sword swing is evidence, not a fabricated server hit acknowledgement.
  if
    previousHealth
    and selected.humanoid.Health < previousHealth
    and snap.now - engagedAt < cfg("MCTargetMemory")
    and snap.now - swing < 0.45
    and selected.distance <= 13
    and selected.angle < 25
  then
    hitAt, engagedAt = snap.now, snap.now
  end
  if snap.now - damagedAt < 0.15 and selected.distance < 12 and selected.angle < 25 then
    engagedAt = snap.now
  end
  lastOwnSwing, previousHealth, current = swing, selected.humanoid.Health, selected
  current.engaged = snap.now - engagedAt < cfg("MCTargetMemory")
  current.lastHit, current.lastDamage = hitAt, damagedAt
  return current
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
function Target.canHit(snap, target, reach)
  local geometry = native.data().geometry
  local direction = snap.camera.CFrame.LookVector
  if geometry and type(geometry.Hit) == "function" then
    local distance = geometry.Hit(snap.eye, direction, target.root.Position, target.character:GetAttribute("Sneaking"), reach)
    return distance ~= nil and native.visible(snap.eye, snap.eye + direction * distance, target.character)
  end
  local delta = target.root.Position - snap.eye
  local forward = delta:Dot(direction)
  return forward > 0 and forward <= reach and (delta - direction * forward).Magnitude < 0.7 and native.visible(snap.eye, target.root.Position, target.character)
end
Target.__contract = { requires = { Native = "mcpnative" }, provides = { "setup", "reset", "update", "point", "canHit" } }
return Target
