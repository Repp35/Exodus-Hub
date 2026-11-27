-- [[ spatial visual selection ]]
--!optimize 2
--!native
-- @modules renderspatial

-- code
local Spatial = {}
function Spatial.setup() return true end
local function verticalDecision(minY, maxY, cameraY, previous, options)
  if options.CullFloorY and maxY < options.CullFloorY then
    return "floor"
  end
  if not options.CullVertical then
    return nil
  end
  local margin = options.CullVerticalMargin or 20
  local above = (options.CullAbove or 200) - (if previous == "above" then margin else 0)
  local below = (options.CullBelow or 100) - (if previous == "below" then margin else 0)
  local anchorY = options.CullAnchorY or cameraY
  if minY > math.max(cameraY, anchorY) + above then
    return "above"
  end
  if maxY < math.min(cameraY, anchorY) - below then
    return "below"
  end
  return nil
end
local function boundsHalf(frame, size)
  local right, up, look = frame.RightVector, frame.UpVector, frame.LookVector
  return Vector3.new(
    (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z) * 0.5,
    (math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z) * 0.5,
    (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z) * 0.5
  )
end
local function cameraPlanes(view)
  local normals = {
    view.look,
    view.look * view.options.ViewTanX + view.right,
    view.look * view.options.ViewTanX - view.right,
    view.look * view.options.ViewTanY + view.up,
    view.look * view.options.ViewTanY - view.up,
  }

  local planes = {}
  for _, normal in ipairs(normals) do
    planes[#planes + 1] = { normal = normal, padding = view.options.CullViewPadding * normal.Magnitude }
  end
  return planes
end
local function inCameraView(delta, half, view)
  for _, plane in ipairs(view.planes) do
    local normal = plane.normal
    local support = math.abs(normal.X) * half.X + math.abs(normal.Y) * half.Y + math.abs(normal.Z) * half.Z
    if normal:Dot(delta) + support + plane.padding < 0 then
      return false
    end
  end
  return true
end
local function renderDecision(position, half, previous, outsideSince, now, view, turnHold)
  local delta = position - view.position
  local options = view.options
  local origin = view.focus or view.position
  local rangeDelta = position - origin
  local dx, dy, dz = math.max(0, math.abs(rangeDelta.X) - half.X), math.max(0, math.abs(rangeDelta.Y) - half.Y), math.max(0, math.abs(rangeDelta.Z) - half.Z)
  local surfaceDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
  if surfaceDistance > options.CullDistance then
    return "distance", nil
  end
  local vertical = verticalDecision(position.Y - half.Y, position.Y + half.Y, view.position.Y, previous, options)
  if vertical then
    return vertical, nil
  end
  if turnHold or inCameraView(delta, half, view) then
    return nil, nil
  end
  if not options.CullView or surfaceDistance <= options.CullKeepNear then
    return nil, nil
  end
  outsideSince = outsideSince or now
  if now - outsideSince >= options.CullHideDelay then
    return "view", outsideSince
  end
  return nil, outsideSince
end
local function createSpatialController(services, getOption, PROFILE)
  local Workspace = services.Workspace
  local controller = {}
  local roots = services.Roots or { Workspace }
  local function inScope(object)
    for _, root in ipairs(roots) do
      if object == root or object:IsDescendantOf(root) then
        return true
      end
    end
    return false
  end
  local active, alive = false, true
  local records, chunks, chunkList = {}, {}, {}
  local stack, pending, queued = {}, {}, {}
  local head, tail, chunkIndex = 1, 0, 1
  local driver
  local connections = {}
  local hiddenCount, trackedCount = 0, 0
  local elapsed, holdUntil, lastLook = 1, 0, nil
  local cameraSnapshot
  local function option(key, fallback)
    local value = getOption(key)
    return if value == nil then fallback else value
  end
  local function setHidden(entry, hidden)
    if entry.hidden == hidden then
      return
    end
    entry.hidden = hidden
    hiddenCount += if hidden then 1 else -1
    services.OnHidden(entry.object, hidden)
  end
  local function forget(object)
    local entry = records[object]
    if not entry then
      return
    end
    setHidden(entry, false)
    records[object] = nil
    trackedCount -= 1
    local chunk = entry.chunk
    local last = chunk.parts[#chunk.parts]
    chunk.parts[entry.index] = last
    if last then
      last.index = entry.index
    end
    chunk.parts[#chunk.parts] = nil
    if #chunk.parts == 0 then
      chunks[chunk.key] = nil
      local lastChunk = chunkList[#chunkList]
      chunkList[chunk.index] = lastChunk
      if lastChunk then
        lastChunk.index = chunk.index
      end
      chunkList[#chunkList] = nil
    end
  end
  local modelBounds = setmetatable({}, { __mode = "k" })
  local function visualBounds(object)
    if object:IsA("BasePart") and not object:IsA("Terrain") then
      return object.Position, boundsHalf(object.CFrame, object.Size)
    end
    if object:IsA("Explosion") then
      return object.Position, Vector3.zero
    end
    if object:IsA("Beam") or object:IsA("Trail") then
      local first, second = object.Attachment0, object.Attachment1
      if first and second then
        local a, b = first.WorldPosition, second.WorldPosition
        return (a + b) * 0.5, Vector3.new(math.abs(a.X - b.X), math.abs(a.Y - b.Y), math.abs(a.Z - b.Z)) * 0.5
      end
    end
    local subject = object
    if object:IsA("Highlight") or object:IsA("BillboardGui") or object:IsA("SurfaceGui") or object:IsA("PVAdornment") then
      subject = object.Adornee or object.Parent
    end
    while subject and subject ~= Workspace do
      if subject:IsA("Attachment") then
        return subject.WorldPosition, Vector3.zero
      end
      if subject:IsA("BasePart") then
        return subject.Position, boundsHalf(subject.CFrame, subject.Size)
      end
      if subject:IsA("Model") then
        local cached = modelBounds[subject]
        if not cached then
          local frame, size = subject:GetBoundingBox()
          cached = { frame.Position, boundsHalf(frame, size) }
          modelBounds[subject] = cached
        end
        return cached[1], cached[2]
      end
      subject = subject.Parent
    end
  end
  local function eligible(object)
    return (object:IsA("BasePart") and not object:IsA("Terrain"))
      or object:IsA("ParticleEmitter")
      or object:IsA("Beam")
      or object:IsA("Trail")
      or object:IsA("Smoke")
      or object:IsA("Fire")
      or object:IsA("Sparkles")
      or object:IsA("Light")
      or object:IsA("Highlight")
      or object:IsA("ForceField")
      or object:IsA("Explosion")
      or object:IsA("BillboardGui")
      or object:IsA("SurfaceGui")
      or object:IsA("PVAdornment")
      or object:IsA("Humanoid")
      or object:IsA("Decal")
      or object:IsA("Texture")
  end
  local function register(object)
    if records[object] then
      return
    end
    if not eligible(object) then
      return
    end
    local position = visualBounds(object) or Vector3.zero
    local size = 64
    local x, y, z = math.floor(position.X / size), math.floor(position.Y / size), math.floor(position.Z / size)
    local key = x .. ":" .. y .. ":" .. z
    local chunk = chunks[key]
    if not chunk then
      chunk = {
        key = key,
        index = #chunkList + 1,
        parts = {},
      }

      chunks[key], chunkList[chunk.index] = chunk, chunk
    end
    local entry = { object = object, position = position, chunk = chunk, index = #chunk.parts + 1, hidden = false }
    chunk.parts[entry.index], records[object] = entry, entry
    trackedCount += 1
    if cameraSnapshot then
      local actualPosition, half = visualBounds(object)
      if actualPosition then
        entry.reason, entry.outsideSince = renderDecision(actualPosition, half, nil, nil, os.clock(), cameraSnapshot, false)
      end
      setHidden(entry, entry.reason ~= nil)
    end
  end
  local function enqueue(object)
    if not active or not option("CullEnabled", true) or queued[object] then
      return
    end
    tail += 1
    pending[tail], queued[object] = object, true
  end
  local function nextNode()
    if head <= tail then
      local object = pending[head]
      pending[head], queued[object] = nil, nil
      head += 1
      if head > tail then
        pending, head, tail = {}, 1, 0
      end
      return object, false
    end
    while #stack > 0 do
      local frame = stack[#stack]
      local object = frame.items[frame.index]
      if not object then
        stack[#stack] = nil
        continue
      end
      frame.index += 1
      return object, true
    end
    return nil, false
  end
  local function currentOptions(camera)
    local aspect = camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1)
    local margin = math.rad(option("CullViewDegrees", PROFILE.CullViewDegrees))
    local vertical = math.rad(camera.FieldOfView * 0.5)
    local horizontal = math.atan(math.tan(vertical) * aspect)
    return {
      CullDistance = option("CullDistance", PROFILE.CullDistance),
      CullKeepNear = option("CullKeepNear", PROFILE.CullKeepNear),
      CullView = option("CullView", true),
      CullViewPadding = option("CullViewPadding", PROFILE.CullViewPadding),
      CullHideDelay = option("CullHideDelay", PROFILE.CullHideDelay),
      ViewTanX = math.tan(math.min(math.rad(89), horizontal + margin)),
      ViewTanY = math.tan(math.min(math.rad(89), vertical + margin)),
      CullVertical = option("CullVertical", false),
      CullAbove = option("CullAbove", PROFILE.CullAbove),
      CullBelow = option("CullBelow", PROFILE.CullBelow),
      CullVerticalMargin = option("CullVerticalMargin", PROFILE.CullVerticalMargin),
    }
  end
  function controller:Tick(now, camera)
    table.clear(modelBounds)
    if not active or not alive or not option("CullEnabled", true) then
      return
    end
    local indexing = #stack > 0 or head <= tail
    local budget = indexing and 0.004 or option("CullBudgetMs", 0.8) / 1000
    local deadline = os.clock() + budget
    local count = 0
    if not camera then
      return
    end
    local look = camera.CFrame.LookVector
    if lastLook and look:Dot(lastLook) < 0.75 then
      holdUntil = now + 0.15
    end
    lastLook = look
    cameraSnapshot = {
      position = camera.CFrame.Position,
      focus = services.GetFocusPosition and services.GetFocusPosition(),
      look = look,
      right = camera.CFrame.RightVector,
      up = camera.CFrame.UpVector,
      options = currentOptions(camera),
    }

    cameraSnapshot.planes = cameraPlanes(cameraSnapshot)
    if services.GetFocusY then
      cameraSnapshot.options.CullAnchorY = services.GetFocusY()
    end
    if services.GetFloorY then
      cameraSnapshot.options.CullFloorY = services.GetFloorY()
    end
    if not active or not alive then
      return
    end
    local scanDeadline = os.clock() + budget * 0.65
    while count < (indexing and 4096 or 160) and os.clock() < scanDeadline do
      local object, descend = nextNode()
      if not object then
        break
      end
      if inScope(object) then
        if descend then
          local children = object:GetChildren()
          if #children > 0 then
            stack[#stack + 1] = { items = children, index = 1 }
          end
        end
        register(object)
      end
      count += 1
    end
    -- Revisit visible and hidden entries; moving cameras and objects can cross either boundary.
    local visited = 0
    while #chunkList > 0 and visited < #chunkList and os.clock() < deadline do
      if chunkIndex > #chunkList then
        chunkIndex = 1
      end
      local chunk = chunkList[chunkIndex]
      chunkIndex += 1
      visited += 1
      chunk.cursor = chunk.cursor or 1
      local countInChunk = 0
      while #chunk.parts > 0 and countInChunk < #chunk.parts and os.clock() < deadline do
        if chunk.cursor > #chunk.parts then
          chunk.cursor = 1
        end
        local entry = chunk.parts[chunk.cursor]
        chunk.cursor += 1
        countInChunk += 1
        if not entry.object.Parent or not inScope(entry.object) then
          forget(entry.object)
        else
          local position, half = visualBounds(entry.object)
          if position then
            entry.reason, entry.outsideSince = renderDecision(position, half, entry.reason, entry.outsideSince, now, cameraSnapshot, now < holdUntil)
            setHidden(entry, entry.reason ~= nil)
          end
        end
      end
    end
  end
  local function clearSpatial()
    for _, entry in pairs(records) do
      setHidden(entry, false)
    end
    records, chunks, chunkList, stack, pending, queued = {}, {}, {}, {}, {}, {}
    head, tail, chunkIndex, trackedCount = 1, 0, 1, 0
    lastLook, elapsed = nil, 1
  end
  local function refreshDriver()
    if driver then
      driver:Disconnect()
      driver = nil
    end
    if not active or not option("CullEnabled", true) then
      return
    end
    driver = services.RunService.Heartbeat:Connect(function(dt)
      elapsed += dt
      if (#stack > 0 or head <= tail) or elapsed >= option("CullInterval", 0.1) then
        elapsed = 0
        controller:Tick(os.clock(), Workspace.CurrentCamera)
      end
    end)
  end
  function controller:SetEnabled(value)
    if not alive then
      return
    end
    active = value
    clearSpatial()
    if active and option("CullEnabled", true) then
      stack = { { items = table.clone(roots), index = 1 } }
    end
    refreshDriver()
    if active then
      self:Tick(os.clock(), Workspace.CurrentCamera)
    end
  end
  function controller:Refresh()
    if not active then
      return
    end
    self:Tick(os.clock(), Workspace.CurrentCamera)
  end
  function controller:GetStatus() return { Tracked = trackedCount, Hidden = hiddenCount, Chunks = #chunkList, Indexing = #stack > 0 or head <= tail } end
  function controller:Destroy()
    if not alive then
      return
    end
    self:SetEnabled(false)
    alive = false
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
  end
  for _, root in ipairs(roots) do
    connections[#connections + 1] = root.DescendantAdded:Connect(function(object) enqueue(object) end)
    connections[#connections + 1] = root.DescendantRemoving:Connect(function(object) forget(object) end)
  end
  return controller
end
Spatial.create = createSpatialController
Spatial.__contract = {
  access = { default = "render.write" },
  requires = {},
  provides = { "setup", "create" },
}

return Spatial
