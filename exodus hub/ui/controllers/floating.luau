-- [[ floating ]]
--!optimize 2
-- @modules uifloating

local Controller = {}
function Controller.setup() return true end
function Controller.create(context)
  local utils, controls = context.deps.State, context.deps.Controls
  local entries, order, automatic = {}, {}, {}
  local controller = {}
  local function call(name, ...)
    local callback = type(name) == "function" and name or name and controls[name]
    if callback then
      local ok, accepted, reason = pcall(callback, ...)
      if not ok or accepted == false then
        context.notifications.toast(tostring(ok and reason or accepted), true)
        return false
      end
    end
    return true
  end
  local function refresh(entry)
    local d, handle = entry.definition, entry.handle
    if d.read and controls[d.read] then
      handle.setValue(controls[d.read]())
    elseif d.key or d.option then
      handle.setValue(utils.getConfigValue(d.key or d.option) == true)
    end
    if d.scaleKey or d.squareKey then
      handle.setAppearance(
        d.scaleKey and utils.getConfigValue(d.scaleKey) or 1,
        d.squareKey and utils.getConfigValue(d.squareKey) == true or not d.squareKey and d.shape == "square"
      )
    end
    local visible = (not d.visibleKey and d.visible ~= false) or utils.getConfigValue(d.visibleKey) == true or automatic[d.visibleKey] == true
    if d.mobileOnly == true and context.state.desktop then
      visible = false
    end
    if d.ability then
      visible = visible and context.deps.Model.getAvailability(d.ability) == true
    end
    if not context.state.initializing then
      handle.setVisible(visible)
    end
    handle.setInvisible(d.invisibleKey and utils.getConfigValue(d.invisibleKey) == true)
  end
  function controller.add(definition)
    assert(type(definition) == "table", "Mini UI definition required")
    local d = table.clone(definition)
    local id = assert(d.id or d.prefix, "Mini UI id required")
    assert(not entries[id], "Duplicate Mini UI: " .. id)
    local function color(value) return type(value) == "string" and context.theme.COLORS[value] or value end
    local caption = d.text or d.label or d.title
    local action = d.action and not d.key and not d.read
    local handle, entry
    handle = context.kit.Components.mini(context.refs.screenGui, {
      name = "Mini_" .. id,
      text = d.text or d.label or d.title,
      value = d.value,
      color = color(d.color),
      onColor = color(d.onColor),
      offColor = color(d.offColor),
      onText = d.onText or (action and caption or nil),
      offText = d.offText or (action and caption or nil),
      textSize = d.textSize,
      onTextSize = d.onTextSize,
      offTextSize = d.offTextSize,
      pulse = d.pulse == true,
      panel = d.panel == true,
      action = action == true,
      title = d.title,
      draggable = false,
      size = d.size,
      shape = d.shape,
      visible = false,
      onScaleChanged = function()
        if entry then
          entry.layout()
        end
      end,
      onActivate = function()
        if d.modeKey and utils.getConfigValue(d.modeKey) == "Hold" then
          return
        end
        if d.key or d.option then
          local key = d.key or d.option
          context.setConfigValue(key, utils.getConfigValue(key) ~= true)
        elseif d.action then
          call(d.action, not handle.getValue())
        end
        if d.onActivate then
          call(d.onActivate, not handle.getValue())
        end
        if entries[id] then
          refresh(entries[id])
        end
      end,
      onPress = function(input)
        if d.modeKey and utils.getConfigValue(d.modeKey) == "Hold" then
          call(d.action, true)
        elseif d.onPress then
          call(d.onPress, input)
        end
        if entries[id] then
          refresh(entries[id])
        end
      end,
      onRelease = function(input)
        if d.modeKey and utils.getConfigValue(d.modeKey) == "Hold" then
          call(d.action, false)
        elseif d.onRelease then
          call(d.onRelease, input)
        end
        if entries[id] then
          refresh(entries[id])
        end
      end,
      onDragEnd = function(position)
        if d.xKey and d.yKey then
          utils.setConfig({ [d.xKey] = position.X.Offset, [d.yKey] = position.Y.Offset })
        end
      end,
    })
    entry = { definition = d, handle = handle }
    entries[id], order[#order + 1] = entry, entry
    handle.scope.add(function()
      entries[id] = nil
      local index = table.find(order, entry)
      if index then
        table.remove(order, index)
      end
      context.refs[id] = nil
      local ref = table.find(context.miniBallRefs, id)
      if ref then
        table.remove(context.miniBallRefs, ref)
      end
    end)
    context.refs[id] = handle.Root
    context.miniBallRefs[#context.miniBallRefs + 1] = id
    handle.isDragging = context.makeDraggable(handle.Header, handle.Root, function()
      if d.xKey and d.yKey then
        utils.setConfig({ [d.xKey] = handle.Root.Position.X.Offset, [d.yKey] = handle.Root.Position.Y.Offset })
      end
    end, false, nil, nil, handle.scope)
    function entry.layout()
      local factor = math.clamp(d.scaleKey and tonumber(utils.getConfigValue(d.scaleKey)) or 1, 0.5, 2)
      local multiplier = handle.getScale()
      local size = math.clamp((d.size or context.theme.CLASH_SIZE) * factor, 28, 384) * multiplier
      local scale = math.max(0.01, context.refs.responsiveScale.Scale)
      local raw = context.viewport()
      local view = raw / scale
      local index = table.find(order, entry) or 1
      local x = d.xKey and utils.getConfigValue(d.xKey) or nil
      local y = d.yKey and utils.getConfigValue(d.yKey) or nil
      local width, height = size, size
      local defaultX, defaultY, offscreen = 14, 0, -size - 40
      if d.panel then
        width = math.min(context.theme.MINI_W * factor * multiplier * (d.widthKey and utils.getConfigValue(d.widthKey) or 1), view.X)
        height = math.min(context.theme.MINI_H * factor * multiplier * (d.heightKey and utils.getConfigValue(d.heightKey) or 1), view.Y)
        defaultX, defaultY, offscreen = view.X - width - 14, view.Y / 2 - height / 2, view.X + 30
        handle.setDimensions(width / multiplier, height / multiplier)
      elseif d.defaultX then
        defaultX, defaultY = d.defaultX, view.Y / 2 + (d.offsetY or 0)
      else
        local gap, rows = size + 8, math.ceil(#order / 2)
        defaultX = 14 + ((index - 1) % 2) * gap
        defaultY = (view.Y - rows * gap) / 2 + math.floor((index - 1) / 2) * gap
      end
      local target = UDim2.fromOffset(math.clamp(x or defaultX, 0, math.max(0, view.X - width)), math.clamp(y or defaultY, 0, math.max(0, view.Y - height)))
      handle.setPosition(target, offscreen)
    end
    entry.layout()
    refresh(entry)
    return handle
  end
  context.miniBallRefs = {}
  for _, definition in ipairs(context.miniBalls or {}) do
    controller.add(definition)
  end
  function controller.sync()
    for _, entry in ipairs(order) do
      refresh(entry)
      entry.layout()
    end
  end
  function controller.layout()
    for _, entry in ipairs(order) do
      entry.layout()
    end
  end
  function controller.applyVisibility(rules)
    automatic = rules or {}
    controller.sync()
  end
  function controller.refreshAbilities()
    for _, entry in ipairs(order) do
      if entry.definition.ability then
        refresh(entry)
      end
    end
  end
  function controller.setPrimaryActive(value)
    context.state.primaryActive = value == true
    local primary = context.inputDefinition.primary
    call(primary and primary.write, value == true)
    controller.sync()
  end
  function controller.showPrimary(value)
    local primary = context.inputDefinition.primary
    if primary and primary.visibleKey then
      utils.setConfig({ [primary.visibleKey] = value == true })
    end
  end
  function controller.applyMiniScale() controller.layout() end
  context.scope.connect(context.refs.responsiveScale:GetPropertyChangedSignal("Scale"), controller.layout)
  return controller
end
Controller.__contract = { provides = { "setup", "create" }, requires = {} }
return Controller
