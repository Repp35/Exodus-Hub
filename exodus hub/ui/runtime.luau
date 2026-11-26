-- [[ runtime ]]
--!optimize 2
-- @modules uiruntime

-- module
local Runtime = {}
local Theme
local lifetime
local layerScope
local layerParent
local layers, gameLayers = {}, {}
local layerSequence, reorderQueued = 0, false
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

-- configuration
local CONFIG = { DEFAULT_MOTION = "control" }
local faded = setmetatable({}, { __mode = "k" })

-- setup
function Runtime.setup(deps)
  Runtime.teardown()
  Theme, lifetime = deps.Theme.tokens, deps.Lifetime
  return true
end

-- lifetime
function Runtime.scope() return lifetime.scope() end

local function reorderLayers()
  if reorderQueued or not layerScope or not layerScope.alive then
    return
  end
  reorderQueued = true
  local owner = layerScope
  task.defer(function()
    if layerScope ~= owner or not owner.alive then
      return
    end
    reorderQueued = false
    local ordered = {}
    for gui, entry in pairs(layers) do
      if gui.Parent == layerParent then
        ordered[#ordered + 1] = entry
      end
    end
    table.sort(ordered, function(a, b) return a.rank == b.rank and a.sequence < b.sequence or a.rank < b.rank end)
    for _, entry in ipairs(ordered) do
      entry.gui.Parent = nil
      entry.gui.Parent = layerParent
    end
  end)
end
local function watchGameLayer(gui)
  if not gui:IsA("ScreenGui") or layers[gui] or gui:GetAttribute("ExodusLayer") or gameLayers[gui] then
    return
  end
  local scope = layerScope.child()
  gameLayers[gui] = scope
  scope.connect(gui:GetPropertyChangedSignal("DisplayOrder"), function()
    if gui.DisplayOrder >= Theme.DISPLAY_ORDER then
      reorderLayers()
    end
  end)
  scope.add(function() gameLayers[gui] = nil end)
  if gui.DisplayOrder >= Theme.DISPLAY_ORDER then
    reorderLayers()
  end
end
function Runtime.mountLayer(gui, parent, rank)
  assert(parent:IsA("PlayerGui"), "Hub layers must remain in PlayerGui")
  if not layerScope then
    layerParent, layerScope = parent, lifetime.scope()
    layerScope.connect(parent.ChildAdded, watchGameLayer)
    layerScope.connect(parent.ChildRemoved, function(child)
      if gameLayers[child] then
        gameLayers[child].destroy()
      end
    end)
    for _, child in ipairs(parent:GetChildren()) do
      watchGameLayer(child)
    end
  end
  assert(parent == layerParent, "Mixed PlayerGui layer owners")
  if gameLayers[gui] then
    gameLayers[gui].destroy()
  end
  layerSequence += 1
  local entry = { gui = gui, rank = rank, sequence = layerSequence, Connected = true }
  layers[gui] = entry
  gui:SetAttribute("ExodusLayer", true)
  gui.DisplayOrder = Theme.DISPLAY_ORDER
  local scope = layerScope.child()
  function entry:Disconnect()
    if not self.Connected then
      return
    end
    self.Connected = false
    if layers[gui] == self then
      layers[gui] = nil
    end
    scope.destroy()
  end
  scope.connect(gui.Destroying, function() entry:Disconnect() end)
  scope.connect(gui:GetPropertyChangedSignal("DisplayOrder"), function()
    if gui.DisplayOrder ~= Theme.DISPLAY_ORDER then
      gui.DisplayOrder = Theme.DISPLAY_ORDER
    end
    reorderLayers()
  end)
  reorderLayers()
  return entry
end
function Runtime.teardown()
  if layerScope then
    layerScope.destroy()
  end
  for _, entry in pairs(layers) do
    entry.Connected = false
  end
  layers, gameLayers, layerScope, layerParent = {}, {}, nil, nil
  layerSequence, reorderQueued = 0, false
  return true
end

-- motion
function Runtime.motion(scope, reducedMotion)
  local owners, active = setmetatable({}, { __mode = "k" }), {}
  local motion = {}
  local paused = false
  local function release(tween)
    local entry = active[tween]
    if not entry then
      return
    end
    active[tween] = nil
    scope.remove(entry.connection)
    local properties = owners[entry.object]
    if properties then
      for key in pairs(entry.goals) do
        if properties[key] == tween then
          properties[key] = nil
        end
      end
    end
  end
  function motion.cancel(tween)
    if not tween then
      return
    end
    release(tween)
    tween:Cancel()
  end
  function motion.cancelAll(preserve)
    local pending = {}
    for tween in pairs(active) do
      if not preserve or not preserve(active[tween].object) then
        pending[#pending + 1] = tween
      end
    end
    for _, tween in ipairs(pending) do
      motion.cancel(tween)
    end
  end
  function motion.pause()
    paused = true
    motion.cancelAll()
  end
  function motion.resume() paused = false end
  function motion.play(object, preset, goals, onComplete)
    if paused or not scope.alive or not object or not object.Parent then
      return nil
    end
    local profile = Theme.MOTION[type(preset) == "string" and preset or CONFIG.DEFAULT_MOTION]
    assert(profile, "Unknown motion preset: " .. tostring(preset))
    local duration = reducedMotion and 0 or (type(preset) == "number" and preset or profile.duration)
    local properties = owners[object] or {}
    owners[object] = properties
    for key in pairs(goals) do
      motion.cancel(properties[key])
    end
    if duration <= 0 then
      for key, value in pairs(goals) do
        object[key] = value
      end
      if onComplete then
        onComplete()
      end
      return nil
    end
    local tween = TweenService:Create(object, TweenInfo.new(duration, profile.style, profile.direction), goals)
    local entry = { object = object, goals = goals }
    active[tween] = entry
    for key in pairs(goals) do
      properties[key] = tween
    end
    entry.connection = scope.connect(tween.Completed, function(state)
      release(tween)
      if state == Enum.PlaybackState.Completed and onComplete then
        onComplete()
      end
    end)
    tween:Play()
    return tween
  end
  function motion.fade(root, preset, alpha, onComplete)
    root:SetAttribute("ExodusFadeAlpha", alpha)
    local objects = root:GetDescendants()
    table.insert(objects, 1, root)
    local rootTween
    for _, object in ipairs(objects) do
      local fields = {}
      if object:IsA("GuiObject") then
        fields[#fields + 1] = "BackgroundTransparency"
      end
      if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
        fields[#fields + 1] = "TextTransparency"
      end
      if object:IsA("ImageLabel") or object:IsA("ImageButton") then
        fields[#fields + 1] = "ImageTransparency"
      end
      if object:IsA("UIStroke") then
        fields[#fields + 1] = "Transparency"
      end
      if object:IsA("ScrollingFrame") then
        fields[#fields + 1] = "ScrollBarImageTransparency"
      end
      local saved = faded[object] or {}
      faded[object] = saved
      local goals = {}
      local opacity, ancestor = 1, object
      while ancestor do
        opacity *= 1 - (ancestor:GetAttribute("ExodusFadeAlpha") or 0)
        ancestor = ancestor.Parent
      end
      for _, field in ipairs(fields) do
        if saved[field] == nil then
          saved[field] = object[field]
        end
        goals[field] = saved[field] + (1 - saved[field]) * (1 - opacity)
      end
      if next(goals) then
        local tween = motion.play(object, preset, goals, object == root and onComplete or nil)
        if object == root then
          rootTween = tween
        end
      end
    end
    return rootTween
  end
  function motion.group(object, preset, goals, onComplete)
    if paused or not scope.alive or not object or not object.Parent then
      return nil
    end
    if goals.GroupTransparency ~= nil then
      for _, child in ipairs(object:GetChildren()) do
        if child:IsA("UIStroke") then
          local base = child:GetAttribute("ExodusBaseTransparency")
          if base == nil then
            base = child.Transparency
            child:SetAttribute("ExodusBaseTransparency", base)
          end
          child.Transparency = base + (1 - base) * object.GroupTransparency
          motion.play(child, preset, { Transparency = base + (1 - base) * goals.GroupTransparency })
        end
      end
    end
    return motion.play(object, preset, goals, onComplete)
  end
  scope.add(motion.cancelAll)
  return motion
end

-- input
function Runtime.isVisible(object)
  while object do
    if object:IsA("GuiObject") and not object.Visible then
      return false
    end
    if object:IsA("LayerCollector") and not object.Enabled then
      return false
    end
    object = object.Parent
  end
  return true
end
function Runtime.bindDrag(scope, target, onChange, canStart)
  local owner
  local function release() owner = nil end
  local function available() return target.Parent ~= nil and Runtime.isVisible(target) and (not canStart or canStart()) end
  local function startsOnTarget(input)
    local point, position, size = input.Position, target.AbsolutePosition, target.AbsoluteSize
    if point.X < position.X or point.Y < position.Y or point.X > position.X + size.X or point.Y > position.Y + size.Y then
      return false
    end
    local gui = target:FindFirstAncestorOfClass("PlayerGui") or target:FindFirstAncestorOfClass("CoreGui")
    if not gui then
      return true
    end
    local ok, objects = pcall(function() return gui:GetGuiObjectsAtPosition(point.X, point.Y) end)
    if not ok or type(objects) ~= "table" or #objects == 0 then
      return true
    end
    for _, object in ipairs(objects) do
      if object == target or object:IsDescendantOf(target) then
        return true
      end
      if object:IsA("GuiButton") and object.Active and not target:IsDescendantOf(object) then
        return false
      end
    end
    return true
  end
  scope.connect(UIS.InputBegan, function(input)
    if owner or not available() then
      return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
      return
    end
    if not startsOnTarget(input) then
      return
    end
    owner = input
    onChange(input)
  end)
  scope.connect(UIS.InputChanged, function(input)
    if not owner then
      return
    end
    if not available() or owner.UserInputState == Enum.UserInputState.End or owner.UserInputState == Enum.UserInputState.Cancel then
      release()
      return
    end
    local mouse = owner.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
    if mouse then
      if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        release()
        return
      end
      onChange(input)
    elseif input == owner then
      onChange(input)
    end
  end)
  scope.connect(UIS.InputEnded, function(input)
    if input == owner then
      release()
    end
  end)
  scope.connect(UIS.WindowFocusReleased, release)
  scope.add(release)
  return release
end

-- contract
Runtime.__contract = {
  provides = { "setup", "scope", "motion", "isVisible", "bindDrag", "mountLayer", "teardown" },
  requires = { Theme = "uitheme", Lifetime = "lifetime" },
  requiresMethods = { Lifetime = { "scope" } },
  requiresData = { Theme = { "tokens" } },
}

return Runtime
