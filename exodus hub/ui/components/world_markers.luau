-- [[ world markers ]]
--!optimize 2
-- @modules uiworldmarkers

local Markers = {}
local Runtime, Theme
function Markers.setup(deps)
  Runtime, Theme = deps.Runtime, deps.Theme.tokens
  return true
end
function Markers.create(parent, scope)
  local entries = {}
  local folder = Instance.new("Folder")
  folder.Name, folder.Parent = "ExodusWorldMarkers", parent
  scope.add(function()
    folder:Destroy()
    table.clear(entries)
  end)
  local function remove(key)
    local entry = entries[key]
    if entry then
      entry.gui:Destroy()
      entry.highlight:Destroy()
      entries[key] = nil
    end
  end
  local function update(key, target, label, color)
    if not scope.alive then
      return
    end
    if not target or not target.Parent then
      remove(key)
      return
    end
    local entry = entries[key]
    if entry and entry.target ~= target then
      remove(key)
      entry = nil
    end
    if not entry then
      local anchor = target:IsA("Model") and (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")) or target
      if not anchor then
        return
      end
      local gui = Instance.new("BillboardGui")
      gui.Name, gui.Adornee, gui.AlwaysOnTop = "Marker", anchor, true
      gui.Size, gui.StudsOffset, gui.MaxDistance = UDim2.fromOffset(220, 48), Vector3.new(0, 3, 0), 1800
      gui.Parent = folder
      local text = Instance.new("TextLabel")
      text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
      text.TextSize, text.Font, text.TextStrokeTransparency = 12, Theme.FONT.strong, 0.4
      text.Parent = gui
      local highlight = Instance.new("Highlight")
      highlight.Adornee, highlight.FillTransparency, highlight.OutlineTransparency = target, 0.8, 0.15
      highlight.Parent = folder
      entry = { gui = gui, text = text, highlight = highlight, target = target }
      entries[key] = entry
    end
    entry.text.Text, entry.text.TextColor3 = label, color
    entry.highlight.FillColor, entry.highlight.OutlineColor = color, color
  end
  local function retain(keys)
    for key in pairs(entries) do
      if not keys[key] then
        remove(key)
      end
    end
  end
  return { update = update, retain = retain, clear = function() retain({}) end }
end
Markers.__contract = {
  provides = { "setup", "create" },
  requires = { Runtime = "uiruntime", Theme = "uitheme" },
  requiresData = { Theme = { "tokens" } },
}
return Markers
