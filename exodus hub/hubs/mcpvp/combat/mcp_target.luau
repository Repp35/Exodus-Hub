-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local geometry, native, units, tuning, players, aim
local owner, fight
local serial = 0
local swings = {}
function Target.setup(deps)
  geometry, native, units, tuning, players, aim = deps.Geometry, deps.Native, deps.Units, deps.Options.tuning, game:GetService("Players"), deps.Aim
  return true
end
function Target.reset()
  owner, fight, swings = nil, nil, {}
  serial += 1
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
    fight, swings = nil, {}
    return nil
  end
  value.id = fight.id
  return value
end
function Target.current(snap)
  local value = Target.tracked(snap)
  return value and not fight.awayAt and value or nil
end
function Target.pursuing(snap, untilAt)
  if fight and owner == snap.character then
    fight.pursueUntil = math.max(fight.pursueUntil or 0, untilAt)
  end
end
function Target.abandon(snap, value)
  if fight and (not value or value.id == fight.id) and owner == snap.character then
    aim.dismiss(fight.character)
    fight, swings = nil, {}
    aim.pause(snap)
  end
end
local function resume()
  if fight.awayAt or fight.turnUntil then
    aim.reset()
  end
  fight.awayAt, fight.turnUntil = nil, nil
end
function Target.observeView(snap)
  local value = Target.tracked(snap)
  if not value then
    return
  end
  local delta = (value.root.Position - snap.root.Position) * Vector3.new(1, 0, 1)
  local move = snap.humanoid.MoveDirection
  local advancing = delta.Magnitude > 0.001 and move.Magnitude > 0.1 and move.Unit:Dot(delta.Unit) > 0.25
  local nearby = value.distance <= tuning.pursuitAwayRangeBlocks
  local arriving = snap.now < (fight.pursueUntil or 0)
  -- Close combat, deliberate approach and an outstanding pearl all preserve PvP.
  if nearby or advancing or arriving then
    resume()
    return
  end
  local looking = aim.looking(snap, value)
  if aim.yielding(snap, value) then
    fight.turnUntil = snap.now + tuning.manualTurnSeconds
  end
  if looking then
    if fight.awayAt or not fight.turnUntil or snap.now >= fight.turnUntil then
      resume()
    else
      -- Allow a deliberate turn to leave the viewport before restoring the lock.
      aim.pause(snap)
    end
    return
  end
  if not fight.turnUntil then
    return
  end
  -- A distant offscreen target alone never cancels pursuit. Require a manual
  -- turn away and no approach, continuously, after any pearl has finished.
  fight.awayAt = fight.awayAt or snap.now
  aim.pause(snap)
  if snap.now - fight.awayAt >= tuning.lookAwaySeconds then
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
  fight = { player = value.player, character = value.character, id = serial }
  aim.reset()
  value.id, swings = serial, {}
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
  if not chosen then
    return nil
  end
  local current = Target.current(snap)
  if not current or current.character ~= chosen.character then
    select(snap, chosen)
  else
    chosen.id = current.id
  end
  resume()
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
  for player, at in pairs(swings) do
    if snap.now - at > 0.35 or player.Parent ~= players then
      swings[player] = nil
    end
  end
  Target.observeView(snap)
end
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
    "noteSwing",
    "abandon",
    "threat",
    "observeView",
    "pursuing",
  },
  requires = { Geometry = "mcpgeometry", Native = "mcpnative", Units = "mcpunits", Options = "mcpoptions", Aim = "mcpaim" },
  requiresMethods = {
    Geometry = { "allowed", "hit", "incoming" },
    Native = { "snapshot", "blocked" },
    Units = { "distance" },
    Aim = { "reset", "pause", "looking", "yielding", "dismiss" },
  },
  requiresData = { Options = { "tuning" } },
}
return Target
