-- [[ mm2 targeting ]]
--!optimize 2

local Targeting = {}
local State
local Collection = game:GetService("CollectionService")
function Targeting.setup(deps)
  State = deps.State
  return true
end
function Targeting.clear(snap, target, origin, point)
  local delta = point - origin
  if delta.Magnitude < 0.01 then
    return false
  end
  local parameters = RaycastParams.new()
  parameters.FilterType = Enum.RaycastFilterType.Exclude
  local ignored = { snap.character }
  for _, object in ipairs(Collection:GetTagged("WeaponPassthrough")) do
    ignored[#ignored + 1] = object
  end
  parameters.FilterDescendantsInstances = ignored
  local hit = workspace:Raycast(origin, delta, parameters)
  return not hit or hit.Instance:IsDescendantOf(target.character)
end
function Targeting.select(snap, mode, maxDistance)
  local best, distance, rank = nil, maxDistance or math.huge, math.huge
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player == snap.player then
      continue
    end
    local candidate = State.live(player, true)
    if not candidate then
      continue
    end
    local armed = candidate.role == "Sheriff" or candidate.role == "Hero" or State.tool(candidate, "Gun", false) ~= nil
    if mode == "Sheriff/Hero" and not armed or mode == "Innocent" and candidate.role ~= "Innocent" then
      continue
    end
    local delta = (snap.root.Position - candidate.root.Position).Magnitude
    local priority = mode == "Auto" and (armed and 0 or 1) or 0
    if delta <= (maxDistance or math.huge) and (priority < rank or priority == rank and delta < distance) then
      if Targeting.clear(snap, candidate, snap.root.Position, candidate.root.Position) then
        best, distance, rank = candidate, delta, priority
      end
    end
  end
  return best
end
function Targeting.predict(origin, target, speed)
  local lead = math.clamp((target.root.Position - origin).Magnitude / math.max(speed, 1), 0, 1)
  return target.root.Position + target.root.AssemblyLinearVelocity * lead
end
Targeting.__contract = {
  provides = { "setup", "clear", "select", "predict" },
  requires = { State = "mm2state" },
  requiresMethods = { State = { "live", "tool" } },
}
return Targeting
