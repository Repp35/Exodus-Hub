-- [[ mcpsurvival ]]
--!optimize 2
local Survival = {}
local native, geometry, target, pearl, inventory, units, utils
local owner, apple, escape, routeJob, walking
local health, damage, interval, hurtAt, hits = nil, 0, 0.6, nil, 0
local nextApple, nextRoute, episode = 0, 0, false
local generation, eatingDuration = 0, 1.6
local FLAT = Vector3.new(1, 0, 1)
function Survival.setup(deps)
  native, geometry, target, pearl, inventory, units, utils = deps.Native, deps.Geometry, deps.Target, deps.Pearl, deps.Inventory, deps.Units, deps.Utils
  return true
end
local function stopWalking(snap)
  if not walking then
    return
  end
  walking = nil
  if snap then
    snap.humanoid:Move(Vector3.zero, false)
  end
end
function Survival.reset()
  local snap = native.snapshot()
  if apple and snap and owner == snap.character and snap.character:GetAttribute("EatingApple") then
    return
  end
  native.holdUse(nil, false)
  stopWalking(snap)
  owner, apple, escape, routeJob, health = nil, nil, nil, nil, nil
  damage, interval, hurtAt, hits, nextApple, nextRoute, episode = 0, 0.6, nil, 0, 0, 0, false
  generation += 1
end
function Survival.busy() return apple ~= nil or escape ~= nil end
local function findApple()
  local slots = inventory.slots()
  for slot = 1, 9 do
    local tool = slots and slots[slot]
    if tool and tool.Parent and tool.Name == "Gold Apple" and (tonumber(tool:GetAttribute("Count")) or 1) > 0 then
      return tool
    end
  end
  return nil
end
local function finishApple(snap, completed)
  native.holdUse(nil, false)
  if not native.restore(snap, apple.previous) then
    return false
  end
  apple, nextApple = nil, snap.now + (completed and eatingDuration or 0.8)
  if escape then
    escape.fed = completed == true
  end
  return true
end
local function eat(snap)
  if not apple then
    return false
  end
  local tool = apple.tool
  local consumed = not tool.Parent or (tonumber(tool:GetAttribute("Count")) or apple.count) < apple.count
  if consumed then
    finishApple(snap, true)
    return true
  end
  if apple.started then
    local untilAt = tonumber(tool:GetAttribute("EatingUntil")) or 0
    local since = tonumber(tool:GetAttribute("EatingStarted")) or 0
    local duration = tonumber(tool:GetAttribute("EatingDuration")) or untilAt - since
    if duration > 0 and duration < 10 then
      eatingDuration = duration
    end
    if snap.character:GetAttribute("EatingApple") or untilAt > workspace:GetServerTimeNow() then
      apple.ack = true
      return true
    end
    -- No synthetic release or equipment change while the native eating action is active.
    if snap.tool ~= tool or apple.ack or snap.now - apple.started > 2.5 then
      finishApple(snap)
    end
    return true
  end
  if snap.now > apple.deadline then
    finishApple(snap)
  elseif native.equip(snap, tool) and native.holdUse(snap, true) then
    apple.started = snap.now
  end
  return true
end
local function beginApple(snap)
  if apple or snap.now < nextApple or native.blocked(snap) then
    return false
  end
  local tool = findApple()
  if not tool then
    return false
  end
  apple = { tool = tool, previous = snap.tool, count = tonumber(tool:GetAttribute("Count")) or 1, deadline = snap.now + 1 }
  return eat(snap)
end
local function rayParams(snap)
  local ray = RaycastParams.new()
  local ignored = { snap.character, snap.camera }
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player.Character then
      ignored[#ignored + 1] = player.Character
    end
  end
  ray.FilterType, ray.RespectCanCollide, ray.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, true, ignored
  return ray
end
local function away(snap)
  local source = escape and escape.foe
  if source and source.Parent then
    escape.position = source.Position
  end
  local direction = escape and escape.position and (snap.root.Position - escape.position) * FLAT or -snap.camera.CFrame.LookVector * FLAT
  return direction.Magnitude > 0.001 and direction.Unit or Vector3.new(1, 0, 0)
end
local function turn(direction, angle)
  local sine, cosine = math.sin(math.rad(angle)), math.cos(math.rad(angle))
  return Vector3.new(direction.X * cosine - direction.Z * sine, 0, direction.X * sine + direction.Z * cosine)
end
local ESCAPE_DISTANCES, ESCAPE_ANGLES = { 24, 18, 12, 8, 4, 2 }, { 0, 35, -35, 70, -70, 110, -110, 180 }
local function escapeRoute(snap)
  local origin = units.toBlocks(snap.root.Position)
  if not escape.search or (escape.search.origin - origin).Magnitude > 0.5 then
    escape.search = { origin = origin, direction = away(snap), index = 1 }
  end
  local search = escape.search
  local threat = escape.position and units.toBlocks(escape.position)
  -- Bound trajectory work per frame, including a completely enclosed hole.
  for _ = 1, 4 do
    local distance = ESCAPE_DISTANCES[math.floor((search.index - 1) / #ESCAPE_ANGLES) + 1]
    if not distance then
      escape.search = nil
      return nil, false
    end
    local angle = ESCAPE_ANGLES[(search.index - 1) % #ESCAPE_ANGLES + 1]
    search.index += 1
    local route = pearl.route(snap, origin + turn(search.direction, angle) * distance, true)
    if route and (not threat or (route.landing - threat).Magnitude > (origin - threat).Magnitude + 1) then
      escape.search = nil
      return route, false
    end
  end
  return nil, true
end
local function requestWalk(snap)
  if routeJob or walking then
    return
  end
  local token, character, origin, direction = generation, snap.character, snap.root.Position, away(snap)
  routeJob = token
  task.spawn(function()
    local success, reason = pcall(function()
      local ray = rayParams(snap)
      local pathService = game:GetService("PathfindingService")
      for _, angle in ipairs({ 0, 60, -60, 120, -120, 180 }) do
        if token ~= generation then
          return
        end
        local destination = origin + units.toWorld(turn(direction, angle) * 5)
        local floor = workspace:Raycast(destination + units.offset(0, 6, 0), units.offset(0, -12, 0), ray)
        local key = floor and floor.Instance:GetAttribute("BlockKey")
        if not floor or floor.Normal.Y < 0.65 or floor.Material == Enum.Material.Water or key == "lava" or key == "water" then
          continue
        end
        if workspace:Raycast(floor.Position + units.offset(0, 1 / 64, 0), units.offset(0, 2, 0), ray) then
          continue
        end
        local path = pathService:CreatePath({
          AgentRadius = units.toWorld(0.28),
          AgentHeight = units.toWorld(1.96),
          AgentCanJump = true,
          AgentJumpHeight = units.toWorld(1.25),
          WaypointSpacing = units.toWorld(0.75),
        })
        local ok = pcall(path.ComputeAsync, path, origin, floor.Position + units.offset(0, 1.25, 0))
        if token ~= generation then
          return
        end
        if ok and path.Status == Enum.PathStatus.Success then
          local points = path:GetWaypoints()
          if #points > 1 then
            walking = { character = character, points = points, index = 2, at = os.clock(), position = origin, progress = os.clock() }
            break
          end
        end
      end
    end)
    if token == generation then
      routeJob = nil
      if not success then
        utils.recordError("mcpvp.escape.path", tostring(reason))
      end
    end
  end)
end
function Survival.move(snap)
  if not walking or not escape or walking.character ~= snap.character then
    return
  end
  local point = walking.points[walking.index]
  if not point or snap.now - walking.at > 5 then
    stopWalking(snap)
    return
  end
  if units.distance(snap.root.Position, walking.position) > 0.3 then
    walking.position, walking.progress = snap.root.Position, snap.now
  end
  if snap.now - walking.progress > 0.8 then
    stopWalking(snap)
    return
  end
  local delta = (point.Position - snap.root.Position) * FLAT
  if units.toBlocks(delta.Magnitude) < 0.5 then
    walking.index += 1
    return
  end
  snap.humanoid:Move(delta.Unit, false)
  if point.Action == Enum.PathWaypointAction.Jump and geometry.grounded(snap) and geometry.headroom(snap) and not geometry.jumpRisk(snap) then
    native.jump(snap)
  end
end
local function observeHealth(snap)
  if health and snap.humanoid.Health < health then
    local loss = health - snap.humanoid.Health
    if hurtAt and snap.now - hurtAt >= 0.15 and snap.now - hurtAt <= 3 then
      interval = interval * 0.5 + (snap.now - hurtAt) * 0.5
      hits += 1
    else
      hits = 1
    end
    damage = damage > 0 and damage * 0.5 + loss * 0.5 or loss
    hurtAt = snap.now
    if not escape then
      episode = false
    end
  end
  health = snap.humanoid.Health
end
local function appleDue(snap, value)
  if not value or hits < 2 or not hurtAt or snap.now - hurtAt > 3 or damage <= 0 then
    return false
  end
  if geometry.stats(value.character:FindFirstChildOfClass("Tool")).type ~= "sword" then
    return false
  end
  local absorption = tonumber(snap.character:GetAttribute("Absorption")) or tonumber(snap.player:GetAttribute("Absorption")) or 0
  local hitsLeft = math.max(1, math.ceil((snap.humanoid.Health + absorption) / damage))
  local nextHit = math.max(0, interval - (snap.now - hurtAt))
  local timeToPop = nextHit + (hitsLeft - 1) * interval
  local tool = findApple()
  local duration = tool and tonumber(tool:GetAttribute("EatingDuration")) or eatingDuration
  return timeToPop <= duration + 0.2
end
function Survival.step(snap, available)
  if owner ~= snap.character then
    Survival.reset()
    owner = snap.character
  end
  observeHealth(snap)
  if escape and escape.foe and escape.foe.Parent then
    escape.position = escape.foe.Position
  end
  if apple then
    eat(snap)
    return true
  end
  if utils.getConfigValue("MCAutoEscape") ~= true then
    if escape or routeJob or walking then
      escape, routeJob = nil, nil
      generation += 1
      stopWalking(snap)
    end
    return false
  end
  local hasTotem = snap.character:GetAttribute("OffhandItem") == "totem" or native.find(snap, "Totem") ~= nil
  if hasTotem or snap.humanoid.Health > snap.humanoid.MaxHealth * 0.6 then
    episode = false
  end
  local value = target.current(snap)
  if not escape and not episode and not hasTotem and snap.humanoid.Health <= snap.humanoid.MaxHealth * 0.5 then
    local threat = value or target.threat(snap)
    escape = { foe = threat and threat.root, position = threat and threat.root.Position, origin = snap.root.Position, at = snap.now, fed = false }
    pearl.cancelPrepared(snap)
    target.abandon(snap)
    generation += 1
  end
  if not escape then
    if available and hasTotem and appleDue(snap, value) then
      return beginApple(snap)
    end
    return false
  end
  if not available then
    return true
  end
  if pearl.busy() then
    pearl.advance(snap)
    return true
  end
  if pearl.escaping() then
    escape.launched = true
  end
  if (escape.launched or pearl.pending() or not native.find(snap, "Pearl", true)) and not escape.fed then
    if beginApple(snap) then
      return true
    end
    if not findApple() then
      escape.fed = true
    end
  end
  if (escape.search or snap.now >= nextRoute) and not pearl.pending() and not escape.launched then
    nextRoute = snap.now + 0.5
    local route, searching
    if native.find(snap, "Pearl", true) then
      route, searching = escapeRoute(snap)
    end
    if route then
      stopWalking(snap)
      pearl.launch(snap, route, true)
    elseif not searching then
      requestWalk(snap)
      if not escape.fed and beginApple(snap) then
        return true
      end
    end
  end
  local far = escape.position and units.distance(snap.root.Position, escape.position) >= 12
  local moved = units.distance(snap.root.Position, escape.origin) >= 8
  if escape.fed and (far or not escape.position and moved or snap.humanoid.Health > snap.humanoid.MaxHealth * 0.6 or hasTotem) then
    escape, episode, routeJob = nil, true, nil
    generation += 1
    stopWalking(snap)
    return false
  end
  -- A failed landing or a closing opponent permits another escape route.
  if escape.launched and not pearl.pending() and not far and (escape.position or not moved) then
    escape.launched = false
  end
  Survival.move(snap)
  return true
end
Survival.__contract = {
  provides = { "setup", "reset", "busy", "step", "move" },
  requires = {
    Native = "mcpnative",
    Geometry = "mcpgeometry",
    Target = "mcptarget",
    Pearl = "autopearl",
    Inventory = "mcpinventory",
    Units = "mcpunits",
    Utils = "utils",
  },
  requiresMethods = {
    Native = { "snapshot", "restore", "equip", "holdUse", "blocked", "find", "jump" },
    Geometry = { "stats", "grounded", "headroom", "jumpRisk" },
    Target = { "current", "threat", "abandon" },
    Pearl = { "route", "launch", "advance", "busy", "pending", "escaping", "cancelPrepared" },
    Inventory = { "slots" },
    Units = { "toBlocks", "toWorld", "offset", "distance" },
    Utils = { "getConfigValue", "recordError" },
  },
}
return Survival
