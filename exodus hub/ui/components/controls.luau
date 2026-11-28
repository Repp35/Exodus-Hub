--!optimize 2
-- @modules uicontrols

local Components = {}

function Components.setup() return true end
function Components.install(context)
  local kit = context.kit
  local Theme = context.Theme
  local options = context.options
  local components = context.components
  local C = context.C
  local inst = context.inst

  local control = context.control
  local title = context.title

  local hitbox = context.hitbox
  local commit = context.commit
  local shortcut = context.shortcut
  local bind = context.bind
  local read = context.read
  function components.keybind(parent, definition)
    assert(kit.isDesktop(), "Keybind controls are unavailable in mobile mode; enable PC UI in settings")
    local height = Theme.CARD_H
    local handle = control(parent, definition, height)
    title(handle, definition, 64, height)
    shortcut(handle, definition.key, -64)
    return handle
  end
  function components.button(parent, definition)
    definition = definition or {}
    local height = definition.description and Theme.CARD_H + 22 or Theme.CARD_H
    local handle = control(parent, definition, height)
    title(handle, definition, definition.shortcutKey and 64 or 0, height)
    function handle.activate()
      if not handle.enabled or kit.suspended then
        return false
      end
      if definition.onClick then
        return definition.onClick() ~= false
      end
      return true
    end
    hitbox(handle, handle.activate)
    shortcut(handle, definition.shortcutKey, -64)
    function handle.setText(value) handle.Root.Title.Text = tostring(value) end
    return handle
  end
  function components.toggle(parent, definition)
    definition = definition or {}
    local height = definition.description and Theme.CARD_H + 22 or Theme.CARD_H
    if definition.expandedDescription and definition.description then
      height = Theme.CARD_H + 40
    end
    local handle = control(parent, definition, height)
    title(handle, definition, definition.shortcutKey and 120 or 58, height)
    local checkbox = definition.kind == "checkbox"
    local tint = definition.color or C.toggleOn
    local track = inst("Frame", {
      Size = checkbox and UDim2.fromOffset(28, 28) or UDim2.fromOffset(48, 30),
      Position = checkbox and UDim2.new(1, -46, 0.5, -14) or UDim2.new(1, -62, 0.5, -15),
      BackgroundColor3 = C.toggleOff,
      ZIndex = 8,
    }, handle.Root)
    if definition.expandedDescription and definition.description then
      track.Position = UDim2.new(1, checkbox and -46 or -62, 0, 8)
    end
    kit.corner(track, checkbox and 8 or Theme.RADIUS.pill)
    kit.stroke(track, checkbox and tint or nil)
    local thumb
    if checkbox then
      thumb = inst("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "✓",
        TextColor3 = C.text,
        TextSize = 22,
        TextTransparency = 1,
        Font = Theme.FONT.strong,
        ZIndex = 9,
      }, track)
    else
      thumb = inst("Frame", { Size = UDim2.fromOffset(20, 20), BackgroundColor3 = C.text, ZIndex = 9 }, track)
      kit.corner(thumb, Theme.RADIUS.pill)
    end
    local checkScale = checkbox and inst("UIScale", { Scale = 0.8 }, track) or nil
    local value
    function handle.setValue(nextValue)
      nextValue = nextValue == true
      if value == nextValue then
        return
      end
      local first = value == nil
      value = nextValue
      if first then
        track.BackgroundColor3 = value and tint or C.toggleOff
        if checkbox then
          thumb.TextTransparency = value and 0 or 1
          checkScale.Scale = value and 1 or 0.9
        else
          thumb.Position = UDim2.new(0, value and 24 or 4, 0.5, -10)
        end
        return
      end
      handle.motion.play(track, "control", { BackgroundColor3 = value and tint or C.toggleOff })
      if checkbox then
        handle.motion.play(thumb, "control", { TextTransparency = value and 0 or 1 })
        handle.motion.play(checkScale, "feedback", { Scale = value and 1 or 0.9 })
      else
        handle.motion.play(thumb, "control", { Position = UDim2.new(0, value and 24 or 4, 0.5, -10) })
      end
    end
    function handle.getValue() return value end
    function handle.activate()
      if not handle.enabled or kit.suspended then
        return false
      end
      local current = value
      if definition.getState then
        current = definition.getState()
      end
      local requested = not current
      if commit(handle, definition, requested) then
        if definition.getState then
          handle.setValue(definition.getState())
        else
          handle.setValue(requested)
        end
        if options.notify and definition.toast ~= false then
          options.notify(tostring(definition.title or definition.text or "Option") .. (handle.getValue() and " On" or " Off"))
        end
        return true
      end
      return false
    end
    hitbox(handle, handle.activate)
    shortcut(handle, definition.shortcutKey, nil, definition.expandedDescription and definition.description ~= nil)
    if definition.getState then
      handle.setValue(definition.getState())
    else
      handle.setValue(read(definition.key, definition.value))
    end
    bind(handle, definition.key, handle.setValue)
    return handle
  end
  components.checkbox = components.toggle
end
Components.__contract = { component = true, provides = { "setup", "install" }, requires = {} }
return Components
