-- [[ uiruntime ]]
-- @modules uiruntime

-- module
local Runtime = {}
local Theme
local lifetime
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

-- configuration
local CONFIG = { DEFAULT_MOTION = "control" }

-- setup
function Runtime.setup(deps)
  Theme, lifetime = deps.Theme.tokens, deps.Lifetime
  return true
end

-- lifetime
function Runtime.scope() return lifetime.scope() end

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
  provides = { "setup", "scope", "motion", "isVisible", "bindDrag" },
  requires = { Theme = "uitheme", Lifetime = "lifetime" },
  requiresMethods = { Lifetime = { "scope" } },
  requiresData = { Theme = { "tokens" } },
}

return Runtime
