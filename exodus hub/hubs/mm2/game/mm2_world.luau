-- [[ mm2 world ]]
--!optimize 2

local World = {}
local Collection = game:GetService("CollectionService")
local coinScope
local state, scope, map, coins, guns = nil, nil, nil, {}, {}
function World.setup(deps)
  state = deps.State
  return true
end
function World.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  map, coins, guns, coinScope = nil, {}, {}, nil
end
function World.bind(lifetime)
  World.teardown()
  scope = lifetime.child()
  local function tagged(object) guns[object] = true end
  for _, object in ipairs(Collection:GetTagged("GunDrop")) do
    tagged(object)
  end
  scope.connect(Collection:GetInstanceAddedSignal("GunDrop"), tagged)
  scope.connect(Collection:GetInstanceRemovedSignal("GunDrop"), function(object) guns[object] = nil end)
end
function World.refresh()
  local current = state.map()
  local container = current and current:FindFirstChild("CoinContainer")
  if container == map then
    return
  end
  if scope and coinScope then
    scope.remove(coinScope)
    coinScope = nil
  end
  map, coins = container, {}
  if not container or not scope then
    return
  end
  local owner = scope.child()
  coinScope = owner
  local function add(object)
    if object:IsA("BasePart") then
      coins[object] = true
    end
  end
  owner.connect(container.ChildAdded, add)
  owner.connect(container.ChildRemoved, function(object) coins[object] = nil end)
  for _, object in ipairs(container:GetChildren()) do
    add(object)
  end
end
function World.collectable(part)
  if not part.Parent or not map or not part:IsDescendantOf(map) or part:GetAttribute("Collected") or not part:FindFirstChild("TouchInterest") then
    return false
  end
  local kind = string.lower(tostring(part:GetAttribute("CoinID") or ""))
  local visual = part:FindFirstChild("CoinVisual")
  if visual and (visual:GetAttribute("Delete") or visual:GetAttribute("Collected")) then
    return false
  end
  if kind == "candy" then
    return true
  end
  local main = visual and visual:FindFirstChild("MainCoin")
  return main ~= nil and main:IsA("BasePart") and main.Transparency < 0.95
end
function World.position(object)
  if object:IsA("BasePart") then
    return object.Position
  end
  if object:IsA("Model") then
    return object:GetPivot().Position
  end
end
function World.coins() return coins end
function World.guns() return guns end
function World.nearest(origin, objects, filter)
  local best, point, distance = nil, nil, math.huge
  for object in pairs(objects) do
    if object.Parent and object:IsDescendantOf(workspace) and (not filter or filter(object)) then
      local position = World.position(object)
      local delta = position and (origin - position).Magnitude
      if delta and delta < distance then
        best, point, distance = object, position, delta
      end
    end
  end
  return best, point, distance
end
World.__contract = {
  provides = { "setup", "teardown", "bind", "refresh", "collectable", "position", "coins", "guns", "nearest" },
  requires = { State = "mm2state" },
  requiresMethods = { State = { "map" } },
}
return World
