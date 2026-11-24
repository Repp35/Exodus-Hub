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
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end
local Vector2 = {new = function(x,y) return {X=x,Y=y} end}
local function hsv(h, s, v)
  return {H = h, S = s, V = v, ToHSV = function() return h, s, v end}
end
local Color3 = {fromHSV = hsv}
function Color3.new(r, g, b)
  local high, low = math.max(r,g,b), math.min(r,g,b)
  local d, h = high-low, 0
  if d > 0 then
    if high == r then h = ((g-b)/d)%6 elseif high == g then h = (b-r)/d+2 else h = (r-g)/d+4 end
  end
  return hsv(h/6, high == 0 and 0 or d/high, high)
end
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
local Enum = setmetatable({}, {__index = function(_, name) return setmetatable({}, {__index = function(_, key) return name .. '.' .. key end}) end})
local function instance(class, props, parent)
  local data = {ClassName = class, Visible = true, DisplayOrder = 0, children = {}, attributes = {}, signals = {}, ChildAdded = signal(), ChildRemoved = signal(), Destroying = signal(), Activated = signal(), MouseEnter = signal(), MouseLeave = signal()}
  local object = {}
  function data:IsA(kind)
    return kind == class or (kind == 'GuiButton' and (class == 'TextButton' or class == 'ImageButton'))
      or (kind == 'GuiObject' and (class == 'Frame' or class == 'CanvasGroup' or class == 'TextLabel' or class == 'TextButton' or class == 'ScrollingFrame' or class == 'ImageLabel'))
  end
  function data:GetChildren() return table.clone(data.children) end
  function data:GetAttribute(key) return data.attributes[key] end
  function data:SetAttribute(key, value) data.attributes[key] = value end
  function data:GetPropertyChangedSignal(key)
    data.signals[key] = data.signals[key] or signal(); return data.signals[key]
  end
  function data:FindFirstChild(name)
    for _, child in ipairs(data.children) do if child.Name == name then return child end end
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
  if parent then object.Parent = parent end
  return object
end
local Instance = {new = function(class) return instance(class) end}
local textService = {}
function textService:GetTextSize(text, size, _, bound)
  local width, lines, count = 0, 0, math.max(1, math.floor(bound.X / (size * .55)))
  for line in (text .. '\n'):gmatch('(.-)\n') do
    width = math.max(width, math.min(bound.X, #line * size * .55))
    lines += math.max(1, math.ceil(#line / count))
  end
  return Vector2.new(width, lines * size * 1.2)
end
local game = {GetService = function(_, name) return name == 'TextService' and textService or {} end}
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

    def test_long_notifications_fit_small_viewports(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Appearance': 'ui/appearance.luau', 'Notifications': 'ui/controllers/notifications.luau'}, r'''
local player = instance('Player')
local playerGui = instance('PlayerGui', {}, player)
local context = {
  state = {desktop = true}, refs = {}, scope = Lifetime.scope(),
  services = {Players = {LocalPlayer = player}},
  theme = {DISPLAY_ORDER = 2147483647, SCREEN_LAYERS = {notifications = 3}, COLORS = {btnBlue = 'purple', accent = 'violet'}},
  deps = {Appearance = Appearance, Utils = {getConfig = function() return {DesktopNotifications = true} end},
    NotificationPolicy = Notifications.__bundle.uinotifications,
    Runtime = {mountLayer = function(gui) return {gui = gui, Disconnect = function() end} end}},
  inst = instance, corner = function() end, stroke = function() end,
  safeCancel = function() end, viewport = function() return {X = 200, Y = 180} end,
  twPlay = function(object, _, goals) for key, value in pairs(goals) do object[key] = value end end,
}
local notifications = Notifications.__bundle.uinotificationview.create(context)
assert(notifications.persistent(string.rep('Long message ', 50), 'test', 'info', 0))
local gui = playerGui:FindFirstChild('ExodusPersistentNotifications')
local card = gui:FindFirstChild('NotificationLayer'):FindFirstChild('Notification_test')
assert(card.Size.X.Offset <= 200 - 24 and card.ClipsDescendants)
local content = card:FindFirstChild('Content')
local message = content:FindFirstChild('Message')
assert(message.TextWrapped and message.TextTruncate == Enum.TextTruncate.None and message.TextSize == 11)
assert(card.Size.Y.Offset <= 180 - 48 and content.ScrollingEnabled, 'Huge messages must stay inside a scrollable notification')
assert(content.Position.X.Offset >= 8 and content.Position.Y.Offset == 6)
assert(notifications.toast('OK', true))
local toast = gui:FindFirstChild('NotificationLayer'):FindFirstChild('Notification_toast')
assert(toast.Size.X.Offset < card.Size.X.Offset and toast.Size.Y.Offset < 46, 'Short notifications must shrink to their content')
local toastMessage = toast:FindFirstChild('Content'):FindFirstChild('Message')
assert(toastMessage.TextSize == message.TextSize and toastMessage.Font == message.Font)
assert(toast:FindFirstChild('Content').Position.Y.Offset == content.Position.Y.Offset)
assert(toast.Position.Y.Offset + 8 <= card.Position.Y.Offset - card.Size.Y.Offset)
context.scope.destroy()
''')

    def test_frame_fades_restore_text_and_outline_transparency(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Runtime': 'ui/runtime.luau'}, r'''
Runtime.setup({Theme = {tokens = {MOTION = {control = {duration = 0}}}}, Lifetime = Lifetime})
local root = instance('Frame', {BackgroundTransparency = 1}, instance('PlayerGui'))
local text = instance('TextLabel', {BackgroundTransparency = 1, TextTransparency = 0.25}, root)
local stroke = instance('UIStroke', {Transparency = 0.3}, text)
function root:GetDescendants() return {text, stroke} end
for _, object in ipairs({root, text}) do
  local previous = object.IsA
  function object:IsA(kind) return kind == 'GuiObject' or previous(self, kind) end
end
local motion = Runtime.motion(Lifetime.scope(), true)
motion.fade(root, 'control', 1)
assert(text.TextTransparency == 1 and stroke.Transparency == 1)
local second = Runtime.motion(Lifetime.scope(), true)
second.fade(root, 'control', 0)
assert(text.TextTransparency == 0.25 and stroke.Transparency == 0.3)
Runtime.teardown()
''')

    def test_nested_fades_compose_without_erasing_child_captions(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Runtime': 'ui/runtime.luau'}, r'''
Runtime.setup({Theme = {tokens = {MOTION = {control = {duration = 0}}}}, Lifetime = Lifetime})
local parent = instance('Frame', {BackgroundTransparency = 1}, instance('PlayerGui'))
local child = instance('Frame', {BackgroundTransparency = 1}, parent)
local title = instance('TextLabel', {BackgroundTransparency = 1, TextTransparency = 0, Text = 'Fly speed'}, child)
local description = instance('TextLabel', {BackgroundTransparency = 1, TextTransparency = .2, Text = 'Change flight speed'}, child)
function parent:GetDescendants() return {child, title, description} end
function child:GetDescendants() return {title, description} end
local motion = Runtime.motion(Lifetime.scope(), true)
for _ = 1, 5 do
  motion.fade(parent, 'control', 1)
  motion.fade(child, 'control', 0)
  assert(title.TextTransparency == 1, 'Refreshing a child must respect its collapsed parent')
  motion.fade(parent, 'control', 0)
  assert(title.TextTransparency == 0 and description.TextTransparency == .2)
  assert(title.Text == 'Fly speed' and description.Text == 'Change flight speed')
end
Runtime.teardown()
''')

    def test_header_reserves_margins_and_scrolls_only_when_full(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Header': 'ui/header.luau'}, r'''
local scope = Lifetime.scope()
local context = {scope = scope, inst = instance, hub = {version = '3.3.0'}, deps = {Utils = {author = function() return 'long_username' end}},
 theme = {PAD = 14, PANEL_W = 540, TITLE_H = 50, TITLE_TEXT_SIZE = 16, AUTHOR_TEXT_SIZE = 14, AUTHOR_TRANSPARENCY = .22, TITLE_SPACING = 7, COLORS = {text = 'gray', subtext = 'gray'}}}
local header = Header.create(context, instance('Frame'))
for i=1,4 do instance('TextButton', {LayoutOrder = i}, header.buttons) end
assert(not header.buttons.ScrollingEnabled)
header.setIcon('rbxassetid://123')
local titleEnd = header.title.Position.X.Offset + header.title.Size.X.Offset
local controlsStart = 540 + header.buttons.Position.X.Offset - header.buttons.Size.X.Offset
assert(titleEnd + 12 <= controlsStart, 'Buttons must keep a margin from the title')
assert(header.icon.Position.X.Offset + header.icon.Size.X.Offset + 12 <= header.title.Position.X.Offset)
for i=5,12 do instance('TextButton', {LayoutOrder = i}, header.buttons) end
assert(header.buttons.ScrollingEnabled and header.buttons.ScrollBarThickness > 0)
for _, child in ipairs(header.buttons:GetChildren()) do
 if child:IsA('GuiButton') then assert(child.Size.X.Offset == 30 and child.Size.Y.Offset == 30) end
end
assert(header.title.Position.X.Offset + header.title.Size.X.Offset + 12 <= 540 - 14 - header.buttons.Size.X.Offset)
for _, child in ipairs(header.buttons:GetChildren()) do if child:IsA('GuiButton') and child.LayoutOrder > 4 then child:Destroy() end end
assert(not header.buttons.ScrollingEnabled and header.buttons.CanvasPosition.X == 0)
header.setIcon(nil)
assert(not header.icon.Visible and header.title.Position.X.Offset == 14)
scope.destroy()
''')

    def test_outline_color_preserves_hue_and_changes_brightness(self):
        self.run_luau({'Appearance': 'ui/appearance.luau'}, r'''
for _, base in ipairs({Color3.fromRGB(153,27,27), Color3.fromRGB(34,197,94), Color3.fromRGB(151,66,221)}) do
 local border = Appearance.borderColor(base)
 assert(border.H == base.H and border.S == base.S and border.V > base.V)
end
local base = Color3.fromRGB(14,14,34)
local border = Appearance.borderColor(base, true)
assert(border.H == base.H and border.S == base.S and border.V > base.V)
''')

    def test_icon_loading_keeps_initial_and_recovers_from_failure(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Header': 'ui/header.luau', 'Window': 'ui/controllers/window.luau'}, r'''
local pending, callbacks, errors = {}, {}, 0
task.spawn = function(callback) pending[#pending+1] = callback end
local provider = {PreloadAsync = function(_, _, callback) callbacks[#callbacks+1] = callback end}
local previous = game.GetService
game.GetService = function(self, name) return name == 'ContentProvider' and provider or previous(self, name) end
local scope = Lifetime.scope()
local colors = {bg='bg',header='header',accent='purple',text='white',subtext='gray',btnDark='dark',redDark='red',btnBlue='blue'}
local context = {scope=scope, refs={screenGui=instance('ScreenGui')}, state={}, combatUI=false,
 theme={PANEL_W=540,PANEL_H=380,PAD=14,TITLE_H=50,BTN_SIZE=56,PARTICLE_COLORS={},LAYERS={panel=5},
 COLORS=colors,TITLE_TEXT_SIZE=16,AUTHOR_TEXT_SIZE=14,AUTHOR_TRANSPARENCY=.22,TITLE_SPACING=7},
 hub={}, deps={Header=Header,Utils={getConfig=function() return {} end,author=function() return 'Dev' end,
 setConfig=function() end,recordError=function() errors+=1 end}},inst=instance,
 corner=function() end,stroke=function(parent) return instance('UIStroke',{},parent) end,
 makeDraggable=function() return function() return false end end, setConfigValue=function() end,
 makeBtn=function(text,_,_,w,h,parent) return instance('TextButton',{Text=text,Size=UDim2.fromOffset(w,h)},parent) end,
 trackConn=scope.add,untrackConn=scope.forget,safeDisconnect=function(connection) connection:Disconnect() end,
 safeCancel=function() end,notifications={toast=function() end},
 twPlay=function(object,_,goals) for key,value in pairs(goals) do object[key]=value end end,
}
context.kit={stroke=context.stroke,icon=function(parent) return instance('ImageLabel',{},parent) end}
local window = Window.create(context)
window.setIcon('rbxassetid://1')
assert(context.refs.floatingButton.Text == 'E', 'Initial must remain visible while the image loads')
pending[#pending]()
window.setIcon('rbxassetid://2')
pending[#pending]()
callbacks[1]('rbxassetid://1', Enum.AssetFetchStatus.Failure)
assert(errors == 0, 'A stale request must not affect the current icon')
callbacks[2]('rbxassetid://2', Enum.AssetFetchStatus.Success)
assert(context.refs.floatingButton.Text == '' and context.refs.floatingButton:FindFirstChild('HubIcon').Visible)
window.setIcon('rbxassetid://3'); pending[#pending]()
callbacks[3]('rbxassetid://3', Enum.AssetFetchStatus.Failure)
assert(errors == 1 and context.refs.floatingButton.Text == 'E')
assert(not context.refs.floatingButton:FindFirstChild('HubIcon').Visible)
window.setIcon(nil)
assert(context.refs.floatingButton.Text == 'E')
for _, alpha in ipairs({0, .6, 1, .1}) do
 context.refs.floatingButton.BackgroundTransparency = alpha
 assert(context.refs.floatingButtonStroke.Transparency == alpha, 'Launcher border must track its background')
end
scope.destroy()
''')

    def test_failed_component_shows_error_and_keeps_siblings(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Pages': 'ui/pages.luau'}, r'''
local failures = {}
local kit = {Theme = {PANEL_W = 540, PANEL_H = 380, PAD = 14, TITLE_H = 50, GAP = 12, CARD_GAP = 8, CONTROL_BLEED = 2, SCROLLBAR = 3, COLORS = {accent = 'purple'}},
 instance = instance, scope = Lifetime.scope(), Components = {}}
function kit.createMotion() return {fade = function(_, _, _, callback) if callback then callback() end end, cancel = function() end, play = function() end} end
function kit.observe() return {Disconnect = function() end} end
function kit.dismiss() end
function kit.Components.readout(parent)
 local root = instance('Frame', {Size = UDim2.fromOffset(100,40)}, parent)
 return {Root = root, setValue = function(value) root.message = value end, destroy = function() root:Destroy() end}
end
kit.Components.toggle = kit.Components.readout
local controller = Pages.create(kit, instance('Frame'), {{id='main', title='Main', columns=1, sections={{components={
 {kind='toggle', key='broken'}, {kind='toggle', key='valid', title='Valid'},
}}}}}, {read=function() return false end, onError=function(key, reason) failures[key] = reason end})
assert(failures.broken and not failures.valid)
assert(controller.getControl('broken').Root.message:find('Erro:'))
assert(controller.getControl('valid').Root.Parent.Visible)
controller.destroy()
''')

    def test_right_only_sections_move_left_and_restore_when_left_returns(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Pages': 'ui/pages.luau'}, r'''
local state = false
local kit = {Theme = {PANEL_W=540,PANEL_H=380,PAD=14,TITLE_H=50,GAP=12,CARD_GAP=8,CONTROL_BLEED=2,SCROLLBAR=3,COLORS={}},
 instance=instance,scope=Lifetime.scope(),Components={}}
function kit.createMotion() return {fade=function(_,_,_,cb) if cb then cb() end end,cancel=function() end,play=function() end} end
function kit.observe() return {Disconnect=function() end} end
function kit.dismiss() end
function kit.Components.toggle(parent, options)
 local root=instance('Frame',{Size=UDim2.fromOffset(100,48)},parent)
 return {Root=root,destroy=function() root:Destroy() end}
end
local controller=Pages.create(kit,instance('Frame'),{{id='main',title='Main',columns=2,sections={
 {column=1,components={{kind='toggle',title='Left',key='left',visibleWhen='showLeft'}}},
 {column=2,components={{kind='toggle',title='Right',key='right'}}},
}}},{read=function() return state end})
local columns=controller.get('main').columns
assert(not columns[1].Visible and columns[2].Position.X.Offset == 0)
state=true; controller.refresh()
assert(columns[1].Visible and columns[1].Position.X.Offset == 0 and columns[2].Position.X.Offset > 0)
state=false; controller.refresh()
assert(not columns[1].Visible and columns[2].Position.X.Offset == 0)
controller.destroy()
''')

    def test_rows_reserve_outline_pixels_without_increasing_card_pitch(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Pages': 'ui/pages.luau'}, r'''
local theme = {PANEL_W = 540, PANEL_H = 380, PAD = 14, TITLE_H = 50, GAP = 12, CARD_GAP = 8, CONTROL_BLEED = 2, SCROLLBAR = 3, COLORS = {accent = 'purple'}}
local kit = {Theme = theme, instance = instance, scope = Lifetime.scope(), Components = {}}
function kit.createMotion() return {fade = function(_, _, _, callback) if callback then callback() end end, cancel = function() end, play = function(object, _, goals, callback)
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
  {kind = 'toggle', key = 'parent', title = 'Parent'}, {kind = 'toggle', key = 'child', title = 'Child', parentKey = 'parent'}, {kind = 'toggle', key = 'next', title = 'Next'},
}}}}}, {read = function() return true end})
local section = controller.get('main').columns[1]:GetChildren()[3]
-- Find the section by name, independent of padding/layout insertion order.
for _, child in ipairs(controller.get('main').columns[1]:GetChildren()) do if child.Name == 'Section1' then section = child end end
assert(section.ClassName == 'Frame', 'Section CanvasGroups clip their own boundaries')
local row = controller.getControl('next').Root.Parent
assert(row.ClassName == 'Frame', 'Rows must not allocate composited surfaces')
local pad = row:FindFirstChildOfClass('UIPadding')
assert(pad.PaddingTop.Offset >= 1 and pad.PaddingBottom.Offset >= 1)
local gap = section:FindFirstChildOfClass('UIListLayout').Padding.Offset
assert(48 + pad.PaddingTop.Offset + pad.PaddingBottom.Offset + gap == 48 + theme.CARD_GAP)
local ownerRow = controller.getControl('parent').Root.Parent
local children
for _, child in ipairs(ownerRow:GetChildren()) do if child.Name == 'Children' then children = child end end
assert(children.ClassName == 'Frame', 'Disclosures must not nest CanvasGroups')
assert(children.Size.Y.Offset == 48 + theme.CONTROL_BLEED * 2, 'Expanded children must include outline padding')
local childRow = controller.getControl('child').Root.Parent
local childPad = childRow:FindFirstChildOfClass('UIPadding')
local ownerPad = ownerRow:FindFirstChildOfClass('UIPadding')
local innerGap = ownerRow:FindFirstChildOfClass('UIListLayout').Padding.Offset
assert(innerGap + childPad.PaddingTop.Offset == theme.CARD_GAP, 'Parent-to-child gap must equal regular gap')
assert(childPad.PaddingBottom.Offset + ownerPad.PaddingBottom.Offset + gap + pad.PaddingTop.Offset == theme.CARD_GAP, 'Child-to-next gap must equal regular gap')
controller.destroy()
''')


if __name__ == '__main__':
    unittest.main()
