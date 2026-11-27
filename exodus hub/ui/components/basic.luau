-- [[ basic ]]
--!optimize 2
-- @modules uidisplay, uicontrols, uiselection

-- code
local __part_uicontrols = (function()
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
    local function booleanControl(parent, definition, checkbox)
      definition = definition or {}
      local height = definition.description and Theme.CARD_H + 22 or Theme.CARD_H
      if definition.expandedDescription and definition.description then
        height = Theme.CARD_H + 40
      end
      local handle = control(parent, definition, height)
      title(handle, definition, definition.shortcutKey and 120 or 58, height)
      local track = inst("Frame", {
        Name = checkbox and "Checkbox" or "Track",
        Size = UDim2.fromOffset(checkbox and 30 or 48, 30),
        Position = UDim2.new(1, checkbox and -44 or -62, 0.5, -15),
        BackgroundColor3 = definition.offColor or C.toggleOff,
        ZIndex = 8,
      }, handle.Root)
      if definition.expandedDescription and definition.description then
        track.Position = UDim2.new(1, checkbox and -44 or -62, 0, 8)
      end
      kit.corner(track, checkbox and 7 or Theme.RADIUS.pill)
      kit.stroke(track)
      local thumb, check
      if checkbox then
        check = inst("Frame", { Name = "Check", Size = UDim2.fromOffset(18, 14), Position = UDim2.new(0.5, -9, 0.5, -7), BackgroundTransparency = 1, ZIndex = 9 }, track)
        for _, segment in ipairs({ { 7, 4, 8, 45 }, { 13, 11, 6, -45 } }) do
          local line = inst("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(segment[1], 2),
            Position = UDim2.fromOffset(segment[2], segment[3]),
            Rotation = segment[4],
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 9,
          }, check)
          kit.corner(line, 1)
        end
      else
        thumb = inst("Frame", { Size = UDim2.fromOffset(20, 20), BackgroundColor3 = C.text, ZIndex = 9 }, track)
        kit.corner(thumb, Theme.RADIUS.pill)
      end
      local value = false
      local activeColor = definition.color or definition.onColor or (checkbox and C.accent or C.toggleOn)
      function handle.setValue(nextValue)
        value = nextValue == true
        handle.motion.play(track, "control", { BackgroundColor3 = value and activeColor or definition.offColor or C.toggleOff })
        if checkbox then
          check.Visible = value
        else
          handle.motion.play(thumb, "control", { Position = UDim2.new(0, value and 24 or 4, 0.5, -10) })
        end
      end
      function handle.setColor(color)
        if typeof(color) == "Color3" then
          activeColor = color
          handle.setValue(value)
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
    function components.toggle(parent, definition) return booleanControl(parent, definition, false) end
    function components.checkbox(parent, definition) return booleanControl(parent, definition, true) end
  end
  Components.__contract = { provides = { "setup", "install" }, requires = {} }
  return Components
end)()
local __part_uidisplay = (function()
  local Components = {}

  function Components.setup() return true end
  function Components.install(context)
    local kit = context.kit
    local components = context.components
    local C = context.C
    local TEXT = context.TEXT
    local inst = context.inst
    local text = context.text
    local control = context.control

    local bind = context.bind
    local read = context.read
    local finite = context.finite
    function components.label(parent, definition)
      definition = definition or {}
      definition = table.clone(definition)
      definition.kind = "label"
      local handle = control(parent, definition, 24)
      handle.Root.BackgroundTransparency = 1
      local outline = handle.Root:FindFirstChildOfClass("UIStroke")
      if outline then
        outline:Destroy()
      end
      local label = text(handle.Root, definition.title or definition.text, { Size = UDim2.fromScale(1, 1), TextSize = TEXT.caption, TextColor3 = C.accent })
      function handle.setText(value) label.Text = tostring(value) end
      return handle
    end
    function components.readout(parent, definition)
      local handle = control(parent, definition, 40)
      local value = text(handle.Root, "", {
        Name = "Value",
        RichText = true,
        Position = UDim2.fromOffset(12, 10),
        Size = UDim2.new(1, -24, 0, 20),
        TextSize = TEXT.body,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
      })
      local function resize()
        local scale, ancestor = 1, handle.Root
        while ancestor do
          local transform = ancestor:FindFirstChildOfClass("UIScale")
          if transform then
            scale *= transform.Scale
          end
          ancestor = ancestor.Parent
        end
        local width = math.max(40, handle.Root.AbsoluteSize.X / math.max(0.01, scale) - 24)
        local bounds = game:GetService("TextService"):GetTextSize(value.Text:gsub("<[^>]->", ""), value.TextSize, value.Font, Vector2.new(width, 100000))
        local height = math.max(20, math.ceil(bounds.Y))
        value.Size = UDim2.new(1, -24, 0, height)
        handle.Root.Size = UDim2.new(1, -8, 0, height + 20)
      end
      function handle.setValue(nextValue)
        local content = tostring(nextValue or "")
        if value.Text ~= content then
          value.Text = content
          resize()
        end
      end
      handle.scope.connect(handle.Root:GetPropertyChangedSignal("AbsoluteSize"), resize)
      return handle
    end
    function components.progressBar(parent, definition)
      definition = definition or {}
      local handle = control(parent, definition, 8)
      handle.Root.ClipsDescendants = true
      local fill = inst("Frame", { Name = "Fill", BackgroundColor3 = definition.color or C.accent, Size = UDim2.fromScale(0, 1), ZIndex = 8 }, handle.Root)
      kit.corner(fill)
      local value
      function handle.setValue(nextValue)
        value = math.clamp(finite(nextValue) or 0, 0, 1)
        handle.motion.play(fill, "control", { Size = UDim2.fromScale(value, 1) })
      end
      function handle.getValue() return value end
      handle.setValue(read(definition.key, definition.value))
      bind(handle, definition.key, handle.setValue)
      return handle
    end
    function components.divider(parent, definition)
      local handle = components.label(parent, definition or {})
      handle.Root.Size = UDim2.new(1, -8, 0, 1)
      handle.Root.BackgroundTransparency = 0
      handle.Root.BackgroundColor3 = C.border
      return handle
    end
  end
  Components.__contract = { provides = { "setup", "install" }, requires = {} }
  return Components
end)()
local __part_uiselection = (function()
  local Components = {}

  function Components.setup() return true end
  function Components.install(context)
    local kit = context.kit
    local Theme = context.Theme
    local UIS = context.UIS
    local options = context.options
    local components = context.components
    local C = context.C
    local FONT = context.FONT
    local TEXT = context.TEXT
    local inst = context.inst

    local control = context.control
    local title = context.title
    local button = context.button
    local commit = context.commit
    local bind = context.bind
    local read = context.read
    local finite = context.finite
    local choiceValue = context.choiceValue
    local choiceLabel = context.choiceLabel
    function components.segmented(parent, definition)
      definition = definition or {}
      local choices = definition.options or definition.choices or {}
      assert(#choices > 0, "segmented requires options")
      local handle = control(parent, definition, Theme.RATE_CARD_H)
      title(handle, definition, 0, 24)
      local track = inst(
        "Frame",
        { Name = "Track", Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 28), BackgroundColor3 = C.inputBg, ZIndex = 8 },
        handle.Root
      )
      kit.corner(track)
      local thumb = inst("Frame", { Name = "Thumb", Size = UDim2.new(1 / #choices, -4, 1, -4), BackgroundColor3 = C.accent, ZIndex = 9 }, track)
      kit.corner(thumb)
      local buttons, value = {}, nil
      function handle.setValue(nextValue)
        if value == nextValue then
          return
        end
        value = nextValue
        for index, choice in ipairs(choices) do
          local selected = choiceValue(choice) == value
          if selected then
            local color = type(choice) == "table" and choice.color or nil
            color = color or (definition.colors and definition.colors[value]) or Theme.SELECTOR_COLORS[value] or C.accent
            handle.motion.play(thumb, "control", { Position = UDim2.new((index - 1) / #choices, 2, 0, 2), BackgroundColor3 = color })
          end
          handle.motion.play(buttons[index], "control", { TextColor3 = selected and C.text or C.subtext })
        end
      end
      function handle.getValue() return value end
      for index, choice in ipairs(choices) do
        local item = button(
          track,
          choiceLabel(choice),
          { Size = UDim2.new(1 / #choices, 0, 1, 0), Position = UDim2.fromScale((index - 1) / #choices, 0), BackgroundTransparency = 1, ZIndex = 10 }
        )
        buttons[index] = item
        handle.scope.connect(item.Activated, function()
          local nextValue = choiceValue(choice)
          if nextValue ~= value and commit(handle, definition, nextValue) then
            handle.setValue(nextValue)
          end
        end)
      end
      handle.setValue(read(definition.key, definition.value or choiceValue(choices[1])))
      bind(handle, definition.key, handle.setValue)
      return handle
    end
    function components.rate_selector(parent, definition)
      local modes = { { value = "CPS", label = "CPS" }, { value = "CPF", label = "CPF" }, { value = "MS", label = "MS" }, { value = "Auto", label = "Auto" } }
      local handle = components.segmented(parent, { title = definition.title or "Spam Rate", key = "SpamRateMode", options = modes })
      local updateMode = handle.setValue
      local track = handle.Root.Track
      track.Size = UDim2.new(1, -88, 0, 30)
      local input = inst("TextBox", {
        Name = "RateInput",
        Size = UDim2.fromOffset(58, 30),
        Position = UDim2.new(1, -68, 0, 28),
        BackgroundColor3 = C.inputBg,
        TextColor3 = C.text,
        TextSize = TEXT.control,
        Font = FONT.strong,
        ClearTextOnFocus = false,
        ZIndex = 11,
      }, handle.Root)
      kit.corner(input)
      kit.stroke(input)
      local function paint()
        local mode = read("SpamRateMode", "CPF")
        updateMode(mode)
        input.TextEditable = mode ~= "Auto"
        if UIS:GetFocusedTextBox() ~= input then
          input.Text = mode == "Auto" and "Auto" or tostring(read(mode, 0))
        end
      end
      for _, key in ipairs({ "SpamRateMode", "CPS", "CPF", "MS" }) do
        bind(handle, key, paint)
      end
      handle.scope.connect(input.FocusLost, function()
        local mode = read("SpamRateMode", "CPF")
        local value = finite(input.Text)
        if mode ~= "Auto" and value and value >= 0 and options.write then
          options.write(mode, value)
        end
        paint()
      end)
      paint()
      return handle
    end
  end
  Components.__contract = { provides = { "setup", "install" }, requires = {} }
  return Components
end)()

return { __bundle = { uicontrols = __part_uicontrols, uidisplay = __part_uidisplay, uiselection = __part_uiselection } }
