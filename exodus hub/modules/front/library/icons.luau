-- [[ uiicons ]]

-- module
local Icons = {}
local Theme

-- configuration
local CONFIG = { SYMBOLS = { settings = "⚙", chevron = "▾", minimize = "—" } }

-- setup
function Icons.setup(deps)
  Theme = deps.Theme.tokens; return true
end

-- public-api
function Icons.create(parent, name, properties)
  local symbol = assert(CONFIG.SYMBOLS[name], "Unknown UI icon: " .. tostring(name)); local icon = Instance.new("TextLabel")
  icon.Name = "Icon_" .. name; icon.BackgroundTransparency = 1
  icon.Active = false; icon.Selectable = false
  icon.BorderSizePixel = 0; icon.Text = symbol
  icon.TextColor3 = Theme.COLORS.text; icon.TextSize = name == "settings" and 18 or 14
  icon.Font = Enum.Font.GothamBold; icon.AnchorPoint = Vector2.new(0.5, 0.5)
  icon.Position = UDim2.fromScale(0.5, 0.5); icon.Size = UDim2.fromOffset(18, 18)
  icon.ZIndex = parent.ZIndex + 1
  for key, value in pairs(properties or {}) do
    icon[key] = value
  end
  icon.Parent = parent; return icon
end

-- contract
Icons.__contract = {
  provides = { "setup", "create" },
  requires = { Theme = "uitheme" },
  requiresData = { Theme = { "tokens" } },
}

return Icons
