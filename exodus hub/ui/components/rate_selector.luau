-- [[ reusable mode and numeric value selector ]]
--!optimize 2
-- @modules uirateselector
local Selector = {}
function Selector.setup() return true end
function Selector.install(context)
  local components, inst, kit = context.components, context.inst, context.kit
  local C, FONT, TEXT, UIS = context.C, context.FONT, context.TEXT, context.UIS
  local bind, read, finite, options = context.bind, context.read, context.finite, context.options
  function components.rate_selector(parent, definition)
    local choices = assert(definition.options, "Selector options required")
    local modeKey = assert(definition.key, "Selector mode key required")
    for _, choice in ipairs(choices) do
      assert(type(choice) == "table" and (type(choice.valueKey) == "string" or choice.readOnly == true), "Each mode needs a value key or readOnly")
    end
    local handle = components.segmented(parent, { title = definition.title, key = modeKey, options = choices })
    local updateMode = handle.setValue
    handle.Root.Track.Size = UDim2.new(1, -88, 0, 30)
    local input = inst("TextBox", {
      Name = "ValueInput",
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
    local function selected()
      local mode = read(modeKey, definition.value or choices[1].value)
      for _, choice in ipairs(choices) do
        if choice.value == mode then
          return choice
        end
      end
    end
    local function paint()
      local choice = selected()
      if not choice then
        return
      end
      updateMode(choice.value)
      input.TextEditable = choice.readOnly ~= true
      if UIS:GetFocusedTextBox() ~= input then
        input.Text = choice.readOnly and tostring(choice.label or choice.value) or tostring(read(choice.valueKey, 0))
      end
    end
    bind(handle, modeKey, paint)
    local seen = {}
    for _, choice in ipairs(choices) do
      if choice.valueKey and not seen[choice.valueKey] then
        bind(handle, choice.valueKey, paint)
        seen[choice.valueKey] = true
      end
    end
    handle.scope.connect(input.FocusLost, function()
      local choice, value = selected(), finite(input.Text)
      if choice and not choice.readOnly and value and value >= (definition.min or 0) and (not definition.max or value <= definition.max) and options.write then
        options.write(choice.valueKey, value)
      end
      paint()
    end)
    paint()
    return handle
  end
end
Selector.__contract = { component = true, provides = { "setup", "install" }, requires = {} }
return Selector
