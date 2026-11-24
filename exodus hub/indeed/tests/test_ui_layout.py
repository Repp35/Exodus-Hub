"""Layout and layer regressions using real UI controllers with lightweight instances."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PRELUDE = r'''
local function signal()
  local callbacks = {}
  local event = {}
  function event:Connect(callback)
    local connection = {Connected = true}
    callbacks[connection] = callback
    function connection:Disconnect() self.Connected = false; callbacks[self] = nil end
    return connection
  end
  function event:Fire(...)
    for connection, callback in pairs(table.clone(callbacks)) do if connection.Connected then callback(...) end end
  end
  return event
end
local queue = {}
local task = {delay = function() end, defer = function(callback) queue[#queue + 1] = callback end}
local function flush()
  local pending = queue; queue = {}
  for _, callback in ipairs(pending) do callback() end
end
local function warn() end
local function dimension(scale, offset) return {Scale = scale or 0, Offset = offset or 0} end
local UDim = {new = dimension}
local UDim2 = {new = function(xs, xo, ys, yo) return {X = dimension(xs, xo), Y = dimension(ys, yo)} end}
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
local Enum = setmetatable({}, {__index = function(_, name) return setmetatable({}, {__index = function(_, key) return name .. '.' .. key end}) end})
local function instance(class, props, parent)
  local data = {ClassName = class, Visible = true, DisplayOrder = 0, children = {}, attributes = {}, signals = {}, ChildAdded = signal(), ChildRemoved = signal(), Destroying = signal()}
  local object = {}
  function data:IsA(kind) return kind == class end
  function data:GetChildren() return table.clone(data.children) end
  function data:GetAttribute(key) return data.attributes[key] end
  function data:SetAttribute(key, value) data.attributes[key] = value end
  function data:GetPropertyChangedSignal(key)
    data.signals[key] = data.signals[key] or signal(); return data.signals[key]
  end
  function data:FindFirstChildOfClass(kind)
    for _, child in ipairs(data.children) do if child:IsA(kind) then return child end end
  end
  function data:Destroy()
    self.Destroying:Fire()
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
    self.Parent = nil
  end
  setmetatable(object, {__index = data, __newindex = function(self, key, value)
    if key == 'Parent' then
      local old = data.Parent
      if old == value then return end
      data.Parent = value
      if old then table.remove(old.children, table.find(old.children, self)); old.ChildRemoved:Fire(self) end
      if value then value.children[#value.children + 1] = self; value.ChildAdded:Fire(self) end
    else data[key] = value end
    if data.signals[key] then data.signals[key]:Fire() end
  end})
  for key, value in pairs(props or {}) do object[key] = value end
  object.Parent = parent
  return object
end
local game = {GetService = function() return {} end}
'''


class UILayout(unittest.TestCase):
    def run_luau(self, modules, body):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('Luau required')
        code = PRELUDE
        for name, path in modules.items():
            code += f'\nlocal {name} = (function()\n{(ROOT / path).read_text()}\nend)()\n'
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'ui.luau'
            path.write_text(code + body)
            result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_layers_keep_game_gui_below_hub_without_entering_coregui(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Runtime': 'ui/runtime.luau'}, r'''
Runtime.setup({Theme = {tokens = {DISPLAY_ORDER = 2147483647}}, Lifetime = Lifetime})
local player = instance('PlayerGui')
local main = instance('ScreenGui', {Name = 'Hub'}, player)
local mount = Runtime.mountLayer(main, player, 1)
local popup = instance('ScreenGui', {Name = 'Dropdown'}, player)
Runtime.mountLayer(popup, player, 4)
flush()
local foreign = instance('ScreenGui', {DisplayOrder = 2147483647}, player)
flush()
assert(player.children[#player.children] == popup)
assert(player.children[#player.children - 1] == main)
assert(foreign.Parent == player and foreign.DisplayOrder == 2147483647)
main.DisplayOrder = 10
assert(main.DisplayOrder == 2147483647)
foreign.DisplayOrder = 100; foreign.DisplayOrder = 2147483647; flush()
assert(player.children[#player.children] == popup)
assert(not pcall(Runtime.mountLayer, main, instance('CoreGui'), 1))
mount:Disconnect(); main:Destroy(); Runtime.teardown(); flush()
assert(foreign.Parent == player)
''')

    def test_rows_reserve_outline_pixels_without_increasing_card_pitch(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Pages': 'ui/pages.luau'}, r'''
local theme = {PANEL_W = 540, PANEL_H = 380, PAD = 14, TITLE_H = 50, GAP = 12, CARD_GAP = 8, CONTROL_BLEED = 2, SCROLLBAR = 3, COLORS = {accent = 'purple'}}
local kit = {Theme = theme, instance = instance, scope = Lifetime.scope(), Components = {}}
function kit.createMotion() return {cancel = function() end, play = function(object, _, goals, callback)
  for key, value in pairs(goals) do object[key] = value end
  if callback then callback() end
end} end
function kit.observe() return {Disconnect = function() end} end
function kit.dismiss() end
function kit.Components.toggle(parent, options)
  local root = instance('Frame', {Name = options.key, Size = UDim2.fromOffset(100, 48)}, parent)
  return {Root = root, destroy = function() root:Destroy() end}
end
local parent = instance('CanvasGroup')
local controller = Pages.create(kit, parent, {{id = 'main', title = 'Main', columns = 1, sections = {{components = {
  {kind = 'toggle', key = 'parent'}, {kind = 'toggle', key = 'child', parentKey = 'parent'}, {kind = 'toggle', key = 'next'},
}}}}}, {read = function() return true end})
local section = controller.get('main').columns[1]:GetChildren()[3]
-- Find the section by name, independent of padding/layout insertion order.
for _, child in ipairs(controller.get('main').columns[1]:GetChildren()) do if child.Name == 'Section1' then section = child end end
assert(section.ClassName == 'Frame', 'Section CanvasGroups clip their own boundaries')
local row = controller.getControl('next').Root.Parent
local pad = row:FindFirstChildOfClass('UIPadding')
assert(pad.PaddingTop.Offset >= 1 and pad.PaddingBottom.Offset >= 1)
local gap = section:FindFirstChildOfClass('UIListLayout').Padding.Offset
assert(48 + pad.PaddingTop.Offset + pad.PaddingBottom.Offset + gap == 48 + theme.CARD_GAP)
local ownerRow = controller.getControl('parent').Root.Parent
local children
for _, child in ipairs(ownerRow:GetChildren()) do if child.Name == 'Children' then children = child end end
assert(children.Size.Y.Offset == 48 + theme.CONTROL_BLEED * 2, 'Expanded children must include outline padding')
controller.destroy()
''')


if __name__ == '__main__':
    unittest.main()
