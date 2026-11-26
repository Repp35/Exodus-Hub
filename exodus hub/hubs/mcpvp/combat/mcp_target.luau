-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local geometry, native, units, tuning, players, aim
local owner, fight, health, attempted
local serial, activity = 0, -math.huge
local swings = {}
function Target.setup(deps)
  geometry, native, units, tuning, players, aim = deps.Geometry, deps.Native, deps.Units, deps.Options.tuning, game:GetService("Players"), deps.Aim
  return true
end
function Target.reset()
  owner, fight, health, attempted, swings = nil, nil, nil, nil, {}
  serial, activity = serial + 1, -math.huge
end
local function candidate(player, snap, range)
  local character = player and player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  local human = character and character:FindFirstChildOfClass("Humanoid")
  if
    not player
    or player == snap.player
    or player.Parent ~= players
    or not root
    or not human
    or human.Health <= 0
    or character:FindFirstChildOfClass("ForceField")
    or not geometry.allowed(character)
  then
    return nil
  end
  local distance = units.distance(root.Position, snap.root.Position)
  if distance > range then
    return nil
  end
  return { player = player, character = character, root = root, humanoid = human, distance = distance }
end
function Target.tracked(snap)
  if not fight then
    return nil
  end
  local value = owner == snap.character and candidate(fight.player, snap, math.huge)
  if not value or value.character ~= fight.character then
    fight, attempted, swings = nil, nil, {}
    return nil
  end
  value.id = fight.id
  return value
end
function Target.current(snap)
  local value = Target.tracked(snap)
  return fight and not fight.suspended and value or nil
end
local function suspend(snap, value)
  if fight and value.distance > tuning.focusRangeBlocks then
    fight.suspended, fight.resumeUntil, fight.sawOutside = true, snap.now + tuning.pursuitResumeSeconds, not aim.looking(snap, value)
    aim.pause(snap)
  else
    Target.abandon(snap, value)
  end
end
function Target.abandon(snap, value)
  if fight and (not value or value.id == fight.id) and owner == snap.character then
    fight, attempted, swings = nil, nil, {}
    aim.pause(snap)
  end
end
function Target.observeView(snap)
  local value = Target.tracked(snap)
  if not value then
    return
  end
  if fight.suspended then
    if snap.now > fight.resumeUntil then
      Target.abandon(snap, value)
      return
    end
    local looking = aim.looking(snap, value)
    if not looking then
      fight.sawOutside = true
    end
    if looking and (fight.sawOutside or aim.returning(snap, value)) then
      fight.suspended, fight.lookAt = false, snap.now
      aim.reset()
    end
    return
  end
  if aim.yielding(snap, value) then
    suspend(snap, value)
    return
  end
  if aim.looking(snap, value) then
    fight.lookAt = snap.now
  end
  if snap.now - fight.lookAt > tuning.lookAwaySeconds and snap.now - fight.replyAt > tuning.retaliationSeconds then
    Target.abandon(snap, value)
  end
end
function Target.near(snap)
  local value = Target.current(snap)
  return value and value.distance <= tuning.focusRangeBlocks and value or nil
end
function Target.isCurrent(snap, value)
  local current = Target.current(snap)
  return current ~= nil and value ~= nil and current.id == value.id and current.character == value.character
end
local function select(snap, value)
  serial += 1
  fight = { player = value.player, character = value.character, id = serial, at = snap.now, lookAt = snap.now, replyAt = -math.huge }
  aim.reset()
  value.id, attempted, swings = serial, nil, {}
end
function Target.manual(snap, direction)
  if owner ~= snap.character then
    Target.reset()
    owner = snap.character
  end
  if native.blocked(snap) then
    return nil
  end
  direction = direction or snap.player:GetAttribute("FrontCameraAimDirection") or snap.camera.CFrame.LookVector
  local chosen, nearest
  for _, player in ipairs(players:GetPlayers()) do
    local value = candidate(player, snap, tuning.focusRangeBlocks)
    local distance = value and geometry.hit(snap, value, snap.tool, direction)
    if distance and (not nearest or distance < nearest) then
      chosen, nearest = value, distance
    end
  end
  activity = snap.now
  if not chosen then
    return nil
  end
  local current = Target.current(snap)
  if not current or current.character ~= chosen.character then
    select(snap, chosen)
  else
    chosen.id = current.id
  end
  fight.at, attempted = snap.now, { at = snap.now, id = fight.id }
  return chosen
end
function Target.noteSwing(source)
  if typeof(source) ~= "Instance" then
    return
  end
  local character = source
  if source:IsA("Player") then
    character = source.Character
  end
  if not character or not character:IsA("Model") then
    return
  end
  local player = players:GetPlayerFromCharacter(character)
  local snap = native.snapshot()
  local value = snap and candidate(player, snap, tuning.focusRangeBlocks)
  if value and geometry.incoming(snap, value) then
    swings[player] = snap.now
  end
end
function Target.threat(snap)
  local best
  for player, at in pairs(swings) do
    if snap.now - at > 0.35 then
      swings[player] = nil
    else
      local value = candidate(player, snap, tuning.focusRangeBlocks)
      if value and geometry.incoming(snap, value) and (not best or value.distance < best.distance) then
        best = value
      end
    end
  end
  return best
end
function Target.observe(snap)
  if owner ~= snap.character then
    Target.reset()
    owner = snap.character
  end
  local current = Target.current(snap)
  if current and aim.yielding(snap, current) then
    suspend(snap, current)
    current = nil
  end
  local hurt = health and snap.humanoid.Health < health
  health = snap.humanoid.Health
  if hurt then
    activity = snap.now
    if fight then
      fight.hurtAt = snap.now
    end
  end
  if current then
    local best = current
    for player, at in pairs(swings) do
      if snap.now - at > 0.35 then
        swings[player] = nil
        continue
      end
      local value = candidate(player, snap, tuning.focusRangeBlocks)
      local responding = current.distance > tuning.focusRangeBlocks or fight.hurtAt and math.abs(at - fight.hurtAt) <= 0.35
      if value and responding and value.distance < best.distance and geometry.visible(snap, value.root.Position, value.character) then
        best = value
      end
      if value and value.player == current.player then
        fight.replyAt = snap.now
      end
    end
    if best ~= current then
      select(snap, best)
      fight.replyAt = snap.now
    end
  end
  Target.observeView(snap)
end
function Target.hit(now)
  if fight and attempted and attempted.id == fight.id and now - attempted.at < 1 then
    fight.at, activity = now, now
  end
  attempted = nil
end
function Target.attacked(snap, value)
  if Target.isCurrent(snap, value) then
    fight.at, activity, attempted = snap.now, snap.now, { at = snap.now, id = fight.id }
  end
end
function Target.quiet(snap, seconds) return snap.now - activity >= seconds end
Target.__contract = {
  provides = {
    "setup",
    "reset",
    "manual",
    "observe",
    "current",
    "tracked",
    "near",
    "isCurrent",
    "hit",
    "noteSwing",
    "attacked",
    "quiet",
    "abandon",
    "threat",
    "observeView",
  },
  requires = { Geometry = "mcpgeometry", Native = "mcpnative", Units = "mcpunits", Options = "mcpoptions", Aim = "mcpaim" },
  requiresMethods = {
    Geometry = { "allowed", "hit", "incoming", "visible" },
    Native = { "snapshot", "blocked" },
    Units = { "distance" },
    Aim = { "reset", "pause", "looking", "yielding", "returning" },
  },
  requiresData = { Options = { "tuning" } },
}
return Target
