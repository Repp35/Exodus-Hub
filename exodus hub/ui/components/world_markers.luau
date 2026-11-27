-- [[ reusable world-space labels and outlines ]]
--!optimize 2
-- @modules uiworldmarkers
local Markers = {}
local Services = { TweenService = game:GetService("TweenService") }
local function destroySafely(object)
  if object then
    pcall(function() object:Destroy() end)
  end
end
function Markers.setup() return true end
function Markers.label(name, parent)
  local label = Instance.new("TextLabel")
  label.Name = name
  label.BackgroundTransparency = 1
  label.BorderSizePixel = 0
  label.Font = Enum.Font.GothamBold
  label.TextColor3 = Color3.new(1, 1, 1)
  label.TextStrokeColor3 = Color3.new(0, 0, 0)
  label.TextStrokeTransparency = 0
  label.TextTruncate = Enum.TextTruncate.None
  label.TextWrapped = false
  label.TextXAlignment = Enum.TextXAlignment.Center
  label.TextYAlignment = Enum.TextYAlignment.Center
  label.Parent = parent
  return label
end
function Markers.billboard(name, adornee, parent)
  local gui = Instance.new("BillboardGui")
  gui.Name = name
  gui.Adornee = adornee
  gui.AlwaysOnTop = true
  gui.LightInfluence = 0
  gui.MaxDistance = 0
  gui.Size = UDim2.fromOffset(260, 24)
  gui.Parent = parent
  return gui
end
function Markers.highlight(esp, name, adornee, color)
  local highlight = Instance.new("Highlight")
  highlight:SetAttribute("UIComponent", true)
  highlight.Name = name
  highlight.Adornee = adornee
  highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
  highlight.FillColor = color
  highlight.FillTransparency = 1
  highlight.OutlineColor = color
  highlight.OutlineTransparency = 1
  highlight.Parent = adornee
  Services.TweenService
    :Create(highlight, TweenInfo.new(0.18), { FillTransparency = esp.FillTransparency, OutlineTransparency = esp.OutlineTransparency })
    :Play()
  return highlight
end
function Markers.destroy(marker)
  if not marker then
    return
  end
  local gui, highlight = marker.Gui, marker.Highlight
  if gui and gui.Parent then
    for _, label in ipairs(gui:GetDescendants()) do
      if label:IsA("TextLabel") then
        Services.TweenService:Create(label, TweenInfo.new(0.16), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
      end
    end
  end
  if highlight and highlight.Parent then
    Services.TweenService:Create(highlight, TweenInfo.new(0.16), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
  end
  task.delay(0.18, function()
    destroySafely(gui)
    destroySafely(highlight)
  end)
end

Markers.__contract = { access = { default = "ui.use" }, provides = { "setup", "label", "billboard", "highlight", "destroy" }, requires = {} }
return Markers
