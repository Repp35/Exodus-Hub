-- [[ mm2 map ]]
--!optimize 2

-- module
local Map = {}
function Map.setup() return true end

-- instance
function Map.create(deps)
  local map, current, added, removed = {}, nil, nil, nil
  local positions = {}
  local function disconnect()
    if added then
      added:Disconnect()
      added = nil
    end
    if removed then
      removed:Disconnect()
      removed = nil
    end
    current = nil
    table.clear(positions)
  end
  local function index(coin)
    if coin:IsA("BasePart") and deps.util.IsFiniteVector3(coin.Position) then
      positions[coin] = coin.Position
    end
  end

  -- index
  function map:GetCoinContainer()
    local _, _, container = deps.match:GetRoundContext()
    return container
  end
  function map:GetCoinPositions(container)
    if container == current then
      return positions
    end
    disconnect()
    current = container
    if container then
      for _, coin in ipairs(container:GetChildren()) do
        index(coin)
      end
      added = container.ChildAdded:Connect(index)
      removed = container.ChildRemoved:Connect(function(coin) positions[coin] = nil end)
    end
    return positions
  end

  -- selection
  function map:GetNearestCoin(container, origin, retryAfter, passed, filter)
    if not container or not container.Parent or not deps.util.IsFiniteVector3(origin) then
      return nil, math.huge
    end
    local nearest, distance, point = nil, math.huge, nil
    for coin in pairs(self:GetCoinPositions(container)) do
      if not coin.Parent or not coin:IsDescendantOf(container) then
        positions[coin] = nil
        continue
      end
      if passed and passed[coin] or retryAfter and (retryAfter[coin] or 0) > os.clock() or not deps.coin:IsCollectable(coin, container) then
        continue
      end
      local position = coin.Position
      if not deps.util.IsFiniteVector3(position) then
        continue
      end
      positions[coin] = position
      if filter and not filter(coin, position) then
        continue
      end
      local gap = (origin - position).Magnitude
      if gap < distance then
        nearest, distance, point = coin, gap, position
      end
    end
    return nearest, distance, point
  end
  deps.runtime:OnShutdown(disconnect)
  return map
end

-- contract
Map.__contract = { provides = { "setup", "create" }, requires = {} }
return Map
