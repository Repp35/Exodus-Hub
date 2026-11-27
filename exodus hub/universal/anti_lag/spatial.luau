-- [[ budgeted distance detail; never deletes objects or culls by height ]]
--!optimize 2
--!native
-- @modules renderspatial
local Spatial = {}
function Spatial.setup() return true end
local function halfSize(object)
  local frame, size = object.CFrame, object.Size
  local right, up, look = frame.RightVector, frame.UpVector, frame.LookVector
  return Vector3.new(
    (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z) * 0.5,
    (math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z) * 0.5,
    (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z) * 0.5
  )
end
local function distance(position, half, origin)
  local delta = position - origin
  local x, y, z = math.max(0, math.abs(delta.X) - half.X), math.max(0, math.abs(delta.Y) - half.Y), math.max(0, math.abs(delta.Z) - half.Z)
  return math.sqrt(x * x + y * y + z * z)
end
function Spatial.create(services, option)
  local controller = {}
  local active, alive, driver = false, true, nil
  local records, byObject, scan, pending = {}, {}, {}, {}
  local head, tail, cursor, hidden, simple = 1, 0, 1, 0, 0
  local function state(entry, value)
    if entry.state == value then
      return
    end
    if entry.state == "hidden" then
      hidden -= 1
    elseif entry.state == "simple" then
      simple -= 1
    end
    entry.state = value
    if value == "hidden" then
      hidden += 1
    elseif value == "simple" then
      simple += 1
    end
    services.OnState(entry.object, value)
  end
  local function forget(object)
    local entry = byObject[object]
    if not entry then
      return
    end
    state(entry, nil)
    local last = records[#records]
    records[entry.index] = last
    if last then
      last.index = entry.index
    end
    records[#records], byObject[object] = nil, nil
  end
  local function dynamic(object)
    if not object.Anchored then
      return true
    end
    local parent = object.Parent
    while parent and parent ~= services.Workspace do
      if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
        return true
      end
      parent = parent.Parent
    end
    return false
  end
  local function register(object)
    if byObject[object] or not object:IsA("BasePart") or object:IsA("Terrain") then
      return
    end
    local entry = { object = object, index = #records + 1 }
    byObject[object], records[entry.index] = entry, entry
  end
  local function nextObject()
    if head <= tail then
      local object = pending[head]
      pending[head] = nil
      head += 1
      if head > tail then
        pending, head, tail = {}, 1, 0
      end
      return object, false
    end
    while #scan > 0 do
      local frame = scan[#scan]
      local object = frame.items[frame.index]
      if not object then
        scan[#scan] = nil
      else
        frame.index += 1
        return object, true
      end
    end
  end
  function controller:Tick()
    if not active or not alive then
      return
    end
    local camera = services.Workspace.CurrentCamera
    if not camera then
      return
    end
    local focus = services.GetFocusPosition() or camera.CFrame.Position
    local view = camera.CFrame.Position
    local near = math.max(64, option("CullKeepNear") or 128)
    local limit = math.max(near * 2, option("CullDistance") or 1200)
    -- One fixed budget per phase, including indexing. No expensive bootstrap mode.
    local deadline, count = os.clock() + 0.0004, 0
    while count < 40 and os.clock() < deadline do
      local object, descend = nextObject()
      if not object then
        break
      end
      if object == services.Workspace or object:IsDescendantOf(services.Workspace) then
        if descend then
          local children = object:GetChildren()
          if #children > 0 then
            scan[#scan + 1] = { items = children, index = 1 }
          end
        end
        register(object)
      end
      count += 1
    end
    count = 0
    while count < math.min(#records, 100) and os.clock() < deadline do
      if cursor > #records then
        cursor = 1
      end
      local entry = records[cursor]
      if not entry then
        break
      end
      cursor += 1
      count += 1
      local object = entry.object
      if not object.Parent or not object:IsDescendantOf(services.Workspace) then
        forget(object)
      else
        local detail
        if not dynamic(object) then
          local half = halfSize(object)
          local range = math.min(distance(object.Position, half, focus), distance(object.Position, half, view))
          -- The nearest surface wins: large floors, nearby geometry and characters remain visible.
          if range > near then
            local margin = entry.state == "hidden" and -near * 0.15 or near * 0.15
            if option("CullEnabled") and range > limit + margin then
              detail = "hidden"
            elseif option("SimplifyFar") then
              detail = "simple"
            end
          end
        end
        state(entry, detail)
      end
    end
  end
  local function clear()
    for _, entry in ipairs(records) do
      state(entry, nil)
    end
    records, byObject, scan, pending = {}, {}, {}, {}
    head, tail, cursor, hidden, simple = 1, 0, 1, 0, 0
  end
  local connections = {}
  function controller:SetEnabled(value)
    if not alive or active == value then
      return
    end
    active = value
    if driver then
      driver:Disconnect()
      driver = nil
    end
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
    table.clear(connections)
    clear()
    if active then
      scan = { { items = { services.Workspace }, index = 1 } }
      connections[1] = services.Workspace.DescendantAdded:Connect(function(object)
        tail += 1
        pending[tail] = object
      end)
      connections[2] = services.Workspace.DescendantRemoving:Connect(forget)
      driver = services.ConnectPhysics(function() self:Tick() end)
    end
  end
  function controller:Refresh() self:Tick() end
  function controller:GetStatus() return { Tracked = #records, Hidden = hidden, Simplified = simple, Indexing = #scan > 0 or head <= tail } end
  function controller:Destroy()
    if not alive then
      return
    end
    self:SetEnabled(false)
    alive = false
  end
  return controller
end
Spatial.__contract = { access = { default = "render.write" }, provides = { "setup", "create" }, requires = {} }
return Spatial
