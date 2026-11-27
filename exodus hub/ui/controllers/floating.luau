-- [[ floating ]]
--!optimize 2
-- @modules uifloating

local Controller = {}
function Controller.setup() return true end
function Controller.create(context)
  local utils, controls = context.deps.Utils, context.deps.Controls
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
    elseif d.key then
      handle.setValue(utils.getConfigValue(d.key) == true)
    end
    if d.scaleKey or d.squareKey then
      handle.setAppearance(d.scaleKey and utils.getConfigValue(d.scaleKey) or 1, d.squareKey and utils.getConfigValue(d.squareKey) ~= false)
    end
    local visible = (not d.visibleKey and d.visible ~= false) or utils.getConfigValue(d.visibleKey) == true or automatic[d.visibleKey] == true
    if d.mobileOnly == true and context.state.desktop then
      visible = false
    end
    if d.ability then
      visible = visible and context.deps.Hub.getAbilityAvailability(d.ability) == true
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
    local handle
    handle = context.kit.Components.mini(context.refs.screenGui, {
      name = "Mini_" .. id,
      text = d.text or d.label or d.title,
      value = d.value,
      color = d.color,
      size = d.size,
      shape = d.shape,
      visible = false,
      onActivate = function()
        if d.modeKey and utils.getConfigValue(d.modeKey) == "Hold" then
          return
        end
        if d.key then
          context.setConfigValue(d.key, utils.getConfigValue(d.key) ~= true)
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
    local entry = { definition = d, handle = handle }
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
    function entry.layout()
      local size = (d.size or 64) * (d.scaleKey and tonumber(utils.getConfigValue(d.scaleKey)) or 1)
      local scale = math.max(0.01, context.refs.responsiveScale.Scale)
      local view = context.viewport() / scale
      local index = table.find(order, entry) or 1
      local x = d.xKey and utils.getConfigValue(d.xKey) or nil
      local y = d.yKey and utils.getConfigValue(d.yKey) or nil
      local target = UDim2.fromOffset(
        math.clamp(x or (14 + ((index - 1) % 2) * (size + 8)), 0, math.max(0, view.X - size)),
        math.clamp(y or (view.Y / 2 - size + math.floor((index - 1) / 2) * (size + 8)), 0, math.max(0, view.Y - size))
      )
      context.twPlay(handle.Root, "control", { Position = target })
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
  function controller.refreshAbilities() controller.sync() end
  function controller.setSpam(value)
    context.state.spamOn = value == true
    local primary = context.inputDefinition.primary
    call(primary and primary.write, value == true)
    controller.sync()
  end
  function controller.showMini(value)
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
