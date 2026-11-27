-- [[ mm2 movement ]]
--!optimize 2

local Movement = {}
local Pathfinding = game:GetService("PathfindingService")
local scope, job, serial = nil, nil, 0
local nextPlan = 0
function Movement.setup() return true end
function Movement.cancel(owner)
  if not job or owner and job.owner ~= owner then
    return
  end
  local old = job
  job = nil
  serial += 1
  old.scope.destroy()
end
function Movement.teardown()
  Movement.cancel()
  scope = nil
  nextPlan = 0
end
function Movement.bind(lifetime)
  Movement.teardown()
  scope = lifetime.child()
end
function Movement.busy() return job ~= nil end
function Movement.owner() return job and job.owner end
function Movement.walk(snap, destination, owner, speed)
  if not scope or not scope.alive or not destination then
    return false
  end
  if job and job.owner == owner and job.character == snap.character and (job.destination - destination).Magnitude < 4 then
    return true
  end
  if not job and os.clock() < nextPlan then
    return false
  end
  Movement.cancel()
  nextPlan = os.clock() + 0.75
  serial += 1
  local generation = serial
  local lifetime = scope.child()
  local original, applied = snap.humanoid.WalkSpeed, math.clamp(tonumber(speed) or snap.humanoid.WalkSpeed, 5, 100)
  job = { owner = owner, character = snap.character, destination = destination, scope = lifetime, deadline = os.clock() + 12 }
  snap.humanoid.WalkSpeed = applied
  lifetime.add(function()
    if snap.humanoid.Parent then
      snap.humanoid:Move(Vector3.zero)
      if snap.humanoid.WalkSpeed == applied then
        snap.humanoid.WalkSpeed = original
      end
    end
  end)
  local thread = task.defer(function()
    local path = Pathfinding:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
    lifetime.add(function() path:Destroy() end)
    local ok = pcall(function() path:ComputeAsync(snap.root.Position, destination) end)
    if not lifetime.alive or serial ~= generation then
      return
    end
    if not ok or path.Status ~= Enum.PathStatus.Success then
      job = nil
      lifetime.destroy()
      return
    end
    local waypoints, index = path:GetWaypoints(), 2
    local function advance(reached)
      if serial ~= generation or not lifetime.alive then
        return
      end
      if not reached or not waypoints[index] or snap.humanoid.Health <= 0 then
        job = nil
        lifetime.destroy()
        return
      end
      local waypoint = waypoints[index]
      index += 1
      if waypoint.Action == Enum.PathWaypointAction.Jump then
        snap.humanoid.Jump = true
      end
      snap.humanoid:MoveTo(waypoint.Position)
    end
    lifetime.connect(snap.humanoid.MoveToFinished, advance)
    lifetime.connect(path.Blocked, function(blocked)
      if blocked >= index - 1 then
        Movement.cancel(owner)
      end
    end)
    advance(true)
  end)
  lifetime.add(thread, function() pcall(task.cancel, thread) end)
  return true
end
function Movement.step()
  if job and (not job.character.Parent or os.clock() > job.deadline) then
    Movement.cancel()
  end
end
function Movement.teleport(snap, destination)
  Movement.cancel()
  snap.character:PivotTo(typeof(destination) == "CFrame" and destination or CFrame.new(destination))
  snap.root.AssemblyLinearVelocity, snap.root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
  return true
end
Movement.__contract = { provides = { "setup", "teardown", "bind", "cancel", "busy", "owner", "walk", "step", "teleport" }, requires = {} }
return Movement
