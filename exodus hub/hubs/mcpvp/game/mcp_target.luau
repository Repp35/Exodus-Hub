-- [[ mcptarget ]]
--!optimize 2
local Target = {}
local native, tuning, players
local current, pending, clicks, lastClick, contact = nil, nil, 0, -math.huge, -math.huge
function Target.setup(deps)
  native, tuning, players = deps.Native, deps.Options.tuning, game:GetService("Players")
  return true
end
function Target.reset()
  current, pending, clicks, lastClick, contact = nil, nil, 0, -math.huge, -math.huge
end
local function candidate(other, snap)
  if other == snap.player or other.Parent ~= players or other:GetAttribute("ArenaProtected") == true or other:GetAttribute("InArena") == false then
    return nil
  end
  local char = other.Character
  local human = char and char:FindFirstChildOfClass("Humanoid")
  local root = char and char:FindFirstChild("HumanoidRootPart")
  if not root or not human or human.Health <= 0 then
    return nil
  end
  if (root.Position - snap.root.Position).Magnitude > tuning.maxRange then
    return nil
  end
  return { player = other, character = char, root = root, humanoid = human }
end
function Target.manual(snap)
  if native.stats(snap.tool).type ~= "sword" then
    return
  end
  local chosen, best = nil, tuning.acquireAngle
  for _, other in ipairs(players:GetPlayers()) do
    local target = candidate(other, snap)
    if not target or not native.canHit(snap, target) then
      continue
    end
    local point, visible = snap.camera:WorldToViewportPoint(target.root.Position)
    if not visible or point.Z <= 0 then
      continue
    end
    local delta = target.root.Position - snap.camera.CFrame.Position
    if delta.Magnitude < 0.01 then
      continue
    end
    local angle = math.deg(math.acos(math.clamp(delta.Unit:Dot(snap.camera.CFrame.LookVector), -1, 1)))
    if angle < best then
      chosen, best = target, angle
    end
  end
  if not chosen then
    return
  end
  clicks = pending == chosen.character and snap.now - lastClick <= tuning.clickWindow and clicks + 1 or 1
  pending, lastClick = chosen.character, snap.now
  if clicks >= tuning.clicksToStart then
    current, contact = chosen, snap.now
  end
end
function Target.get(snap)
  if not current then
    return nil
  end
  local fresh = candidate(current.player, snap)
  if not fresh or fresh.character ~= current.character or snap.now - contact > tuning.targetMemory then
    Target.reset()
    return nil
  end
  current = fresh
  return current
end
function Target.touch(now) contact = now end
Target.__contract = {
  provides = { "setup", "reset", "manual", "get", "touch" },
  requires = { Native = "mcpnative", Options = "mcpoptions" },
  requiresMethods = { Native = { "stats", "canHit" } },
  requiresData = { Options = { "tuning" } },
}
return Target
